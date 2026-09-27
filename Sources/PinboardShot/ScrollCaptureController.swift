import AppKit
import CoreMedia
import CoreVideo
@preconcurrency import ScreenCaptureKit

enum ScrollCaptureFrameCropper {
    static func crop(_ pixelBuffer: CVPixelBuffer, to rect: CGRect) -> CGImage? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        let bounds = CGRect(
            x: 0, y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        let crop = rect.integral.intersection(bounds)
        guard !crop.isNull, crop.width > 0, crop.height > 0 else { return nil }
        let width = Int(crop.width)
        let height = Int(crop.height)
        let bytesPerRow = width * 4
        guard let data = NSMutableData(length: bytesPerRow * height),
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let sourceStart = baseAddress.advanced(by: Int(crop.minY) * sourceBytesPerRow + Int(crop.minX) * 4)
        for row in 0..<height {
            memcpy(data.mutableBytes.advanced(by: row * bytesPerRow),
                   sourceStart.advanced(by: row * sourceBytesPerRow), bytesPerRow)
        }
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue |
                CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

struct ScrollCaptureProgress: @unchecked Sendable {
    let previewImage: CGImage?
    let pixelWidth: Int
    let pixelHeight: Int
    let result: ScrollCaptureAppendResult
}

final class ScrollCaptureFramePipeline: @unchecked Sendable {
    private let maximumPendingBytes: Int

    private let processingQueue: DispatchQueue
    private let stateLock = NSLock()
    private let accumulator = ScrollCaptureAccumulator()
    private let frameSpool = ScrollCaptureFrameSpool()
    private let onProgress: @Sendable (ScrollCaptureProgress) -> Void
    private let onObservation: @Sendable (ScrollCaptureFrameObservation) -> Void
    private var lastProcessedResult: ScrollCaptureAppendResult?
    private var pendingBytes = 0
    private var didReachLimit = false
    private var isCancelled = false
    private var storageFailed = false
    private var consecutiveUnmatchedFrames = 0
    private var lastPreviewDate = Date.distantPast
    private var previousAutomaticFrame: CGImage?

    init(
        maximumPendingBytes: Int = 256 * 1_024 * 1_024,
        processingQueue: DispatchQueue = DispatchQueue(
            label: "com.ryanwang.PinboardShot.scroll-stitch", qos: .userInitiated
        ),
        onProgress: @escaping @Sendable (ScrollCaptureProgress) -> Void,
        onObservation: @escaping @Sendable (ScrollCaptureFrameObservation) -> Void = { _ in }
    ) {
        self.maximumPendingBytes = max(0, maximumPendingBytes)
        self.processingQueue = processingQueue
        self.onProgress = onProgress
        self.onObservation = onObservation
    }

    @discardableResult
    func submit(_ frame: CGImage, timestamp: TimeInterval = CMClockGetTime(CMClockGetHostTimeClock()).seconds,
                requiresStableFrame: Bool = false) -> Bool {
        let (pixelCount, pixelOverflow) = frame.width.multipliedReportingOverflow(by: frame.height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow, byteCount > 0 else { return false }
        let reservation = stateLock.withLock { () -> Bool? in
            guard !isCancelled, !didReachLimit, !storageFailed else { return nil }
            if byteCount <= maximumPendingBytes - pendingBytes {
                pendingBytes += byteCount
                return true
            }
            return false
        }
        guard let holdsMemory = reservation else { return false }
        let queuedFrame: CGImage
        if holdsMemory {
            queuedFrame = frame
        } else {
            // Preserve intermediate frames when matching falls behind. Dropping the
            // newest frame here can leave a permanent gap once the user scrolls on.
            guard let storedFrame = frameSpool.storeFrame(frame) else {
                stopForStorageFailure()
                return false
            }
            queuedFrame = storedFrame
        }
        // Keep ScreenCaptureKit's callback free to collect intermediate frames while
        // a previous frame is being matched against the growing document.
        processingQueue.async { [self] in
            defer {
                if holdsMemory { stateLock.withLock { pendingBytes -= byteCount } }
                else { frameSpool.releaseFrame() }
            }
            guard !stateLock.withLock({ isCancelled || didReachLimit }) else { return }
            if requiresStableFrame {
                // Keep smooth-scroll intermediate frames out of the final image.
                // Two consecutive samples must agree on the viewport position.
                let previous = previousAutomaticFrame
                previousAutomaticFrame = queuedFrame
                guard let previous,
                      ScrollFrameMatcher.match(previous: previous, current: queuedFrame)?.verticalShift == 0 else { return }
            } else {
                previousAutomaticFrame = nil
            }
            process(queuedFrame, timestamp: timestamp)
        }
        return true
    }

    private func stopForStorageFailure() {
        let shouldReport = stateLock.withLock { () -> Bool in
            guard !storageFailed, !isCancelled else { return false }
            storageFailed = true
            return true
        }
        guard shouldReport else { return }
        // This marker follows all previously accepted frames, so the valid tail is
        // processed before reporting a real storage failure.
        processingQueue.async { [self] in
            guard !stateLock.withLock({ isCancelled }) else { return }
            stateLock.withLock { didReachLimit = true }
            onProgress(ScrollCaptureProgress(
                previewImage: accumulator.makePreviewImage(),
                pixelWidth: accumulator.pixelWidth, pixelHeight: accumulator.pixelHeight,
                result: .limitReached
            ))
        }
    }

    func observeIdle(timestamp: TimeInterval) {
        processingQueue.async { [self] in
            guard !stateLock.withLock({ isCancelled || didReachLimit }),
                  let lastProcessedResult else { return }
            onObservation(ScrollCaptureFrameObservation(
                timestamp: timestamp, pixelHeight: accumulator.pixelHeight,
                result: lastProcessedResult == .unmatched ? .unmatched : .duplicate
            ))
        }
    }

    private func process(_ frame: CGImage, timestamp: TimeInterval) {
        let result = accumulator.append(frame)
        lastProcessedResult = result
        onObservation(ScrollCaptureFrameObservation(
            timestamp: timestamp, pixelHeight: accumulator.pixelHeight, result: result
        ))
        let wasUnmatched = consecutiveUnmatchedFrames >= 5
        switch result {
        case .initial:
            consecutiveUnmatchedFrames = 0
        case .appended:
            consecutiveUnmatchedFrames = 0
        case .duplicate:
            consecutiveUnmatchedFrames = 0
            if !wasUnmatched { return }
        case .revisited:
            consecutiveUnmatchedFrames = 0
        case .unmatched:
            consecutiveUnmatchedFrames += 1
            guard consecutiveUnmatchedFrames == 5 else { return }
        case .limitReached:
            stateLock.withLock { didReachLimit = true }
        }

        let shouldReport = result == .initial || result == .unmatched ||
            result == .limitReached || wasUnmatched ||
            Date().timeIntervalSince(lastPreviewDate) >= 0.12
        guard shouldReport else { return }
        // A fast scroll can produce many matched frames per second. Limit preview
        // reads and main-thread updates so they do not delay the stitcher.
        let preview = accumulator.makePreviewImage()
        lastPreviewDate = Date()
        onProgress(ScrollCaptureProgress(
            previewImage: preview,
            pixelWidth: accumulator.pixelWidth,
            pixelHeight: accumulator.pixelHeight,
            result: result
        ))
    }

    func cancel() {
        stateLock.withLock { isCancelled = true }
    }

    func finalImage() -> CGImage? {
        processingQueue.sync { accumulator.makeImage() }
    }

    func hasAppendedContent() -> Bool {
        processingQueue.sync { accumulator.hasContent }
    }

    func hasUnmatchedFrames() -> Bool {
        processingQueue.sync { consecutiveUnmatchedFrames >= 5 }
    }
}

final class ScrollCaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let captureQueue = DispatchQueue(label: "com.ryanwang.PinboardShot.scroll-frames", qos: .userInitiated)

    private let target: ScrollCaptureTarget
    private let pipeline: ScrollCaptureFramePipeline
    private let onError: @Sendable (Error) -> Void
    private var frameOrder = ScrollCaptureFrameOrder()
    private var automaticSampling = false
    private var capturePaused = false

    init(
        target: ScrollCaptureTarget,
        onProgress: @escaping @Sendable (ScrollCaptureProgress) -> Void,
        onObservation: @escaping @Sendable (ScrollCaptureFrameObservation) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.target = target
        self.pipeline = ScrollCaptureFramePipeline(onProgress: onProgress, onObservation: onObservation)
        self.onError = onError
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard !capturePaused, !automaticSampling, outputType == .screen, sampleBuffer.isValid,
              let status = frameStatus(sampleBuffer) else { return }
        guard status == .complete || status == .started,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let frame = croppedFrame(from: pixelBuffer) else { return }
        let timestamp = sampleBuffer.presentationTimeStamp.seconds
        guard frameOrder.accept(timestamp: timestamp) else { return }
        pipeline.submit(frame, timestamp: timestamp)
    }

    func submitSnapshot(_ image: CGImage, timestamp: TimeInterval) {
        captureQueue.async { [self] in
            guard !capturePaused else { return }
            // A screenshot request may finish after a newer streamed frame. Never
            // append that older viewport after the newer one or acknowledge a step with it.
            guard frameOrder.accept(timestamp: timestamp) else { return }
            let scaleX = CGFloat(image.width) / target.window.frame.width
            let scaleY = CGFloat(image.height) / target.window.frame.height
            let rect = CGRect(x: target.cropRect.minX * scaleX, y: target.cropRect.minY * scaleY,
                              width: target.cropRect.width * scaleX, height: target.cropRect.height * scaleY)
            guard let frame = image.cropping(to: rect.integral) else { return }
            pipeline.submit(frame, timestamp: timestamp, requiresStableFrame: true)
        }
    }

    func setAutomaticSampling(_ enabled: Bool) {
        // Serialize the mode change with frame intake; a stream and a screenshot
        // must never both commit views of the same automatic scrolling step.
        captureQueue.async { [self] in automaticSampling = enabled }
    }

    func setCapturePaused(_ paused: Bool) {
        // Freeze new input on the same queue as stream/snapshot intake. Already
        // accepted frames may finish so the saved image keeps its complete tail.
        captureQueue.async { [self] in capturePaused = paused }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(error)
    }

    func cancel() {
        pipeline.cancel()
    }

    func finalImage() -> CGImage? {
        captureQueue.sync { pipeline.finalImage() }
    }

    func hasAppendedContent() -> Bool {
        captureQueue.sync { pipeline.hasAppendedContent() }
    }

    func hasUnmatchedFrames() -> Bool {
        captureQueue.sync { pipeline.hasUnmatchedFrames() }
    }

    private func frameStatus(_ sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRawValue = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return nil
        }
        return status
    }

    private func croppedFrame(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let scaleX = CGFloat(CVPixelBufferGetWidth(pixelBuffer)) / target.window.frame.width
        let scaleY = CGFloat(CVPixelBufferGetHeight(pixelBuffer)) / target.window.frame.height
        let cropRect = CGRect(
            x: target.cropRect.minX * scaleX,
            y: target.cropRect.minY * scaleY,
            width: target.cropRect.width * scaleX,
            height: target.cropRect.height * scaleY
        )
        // ScreenCaptureKit already supplies BGRA pixels; copying only the chosen rows
        // keeps the stream callback short enough to retain frames during a fast scroll.
        return ScrollCaptureFrameCropper.crop(pixelBuffer, to: cropRect)
    }
}

@MainActor
final class ScrollCaptureController {
    private let previewController = ScrollCapturePreviewController()
    private var continuation: CheckedContinuation<NSImage?, Error>?
    private var browserContinuation: CheckedContinuation<Bool, Never>?
    private var stream: SCStream?
    private var output: ScrollCaptureStreamOutput?
    private var target: ScrollCaptureTarget?
    private var isStopping = false
    private var hasUnmatchedFrames = false
    private var autoScroll: ScrollCaptureAutoScroll?
    private var autoScrollTask: Task<Void, Never>?
    private var targetActivationDeadline: TimeInterval = 0
    private var waitingForPointer = false

    private var hostTime: TimeInterval { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    func confirmBrowserCapture(target: ScrollCaptureTarget) async throws -> Bool {
        guard continuation == nil, browserContinuation == nil else { throw PinboardShotError.captureBusy }
        return await withCheckedContinuation { continuation in
            browserContinuation = continuation
            previewController.onFinish = nil
            previewController.onCancel = { [weak self] in self?.completeBrowserChoice(start: false) }
            previewController.onToggleAutoScroll = { [weak self] in self?.completeBrowserChoice(start: true) }
            previewController.show(near: target.selection.rect, on: target.selection.screen)
            previewController.showBrowserCapture()
        }
    }

    private func completeBrowserChoice(start: Bool) {
        guard let continuation = browserContinuation else { return }
        browserContinuation = nil
        previewController.close()
        continuation.resume(returning: start)
    }

    func capture(target: ScrollCaptureTarget) async throws -> NSImage? {
        guard continuation == nil, browserContinuation == nil else { throw PinboardShotError.captureBusy }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.target = target
            autoScroll = ScrollCaptureAutoScroll(viewportHeight: target.cropRect.height, now: hostTime)
            autoScroll?.pause(.user)
            previewController.onFinish = { [weak self] in
                Task { @MainActor in await self?.finishCapture() }
            }
            previewController.onCancel = { [weak self] in
                Task { @MainActor in await self?.cancelCapture() }
            }
            previewController.onToggleAutoScroll = { [weak self] in self?.toggleAutoScroll() }
            previewController.show(near: target.selection.rect, on: target.selection.screen)
            Task { @MainActor [weak self] in
                do {
                    try await self?.startStream(target: target)
                } catch {
                    self?.complete(throwing: error)
                }
            }
        }
    }

    private func startStream(target: ScrollCaptureTarget) async throws {
        let output = ScrollCaptureStreamOutput(
            target: target,
            onProgress: { [weak self] progress in
                Task { @MainActor in self?.handle(progress) }
            },
            onObservation: { [weak self] observation in
                Task { @MainActor in self?.autoScroll?.observe(observation) }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    guard let self, !self.isStopping else { return }
                    self.complete(throwing: error)
                }
            }
        )
        let filter = SCContentFilter(desktopIndependentWindow: target.window)
        let configuration = SCStreamConfiguration()
        let dimensions = CaptureResolution.pixelDimensions(
            for: target.window.frame.size,
            pointPixelScale: target.pointPixelScale
        )
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.captureQueue)
        self.output = output
        self.stream = stream
        try await stream.startCapture()

        guard continuation != nil, !isStopping else {
            try? await stream.stopCapture()
            return
        }

        if let processID = target.window.owningApplication?.processID,
           let application = NSRunningApplication(processIdentifier: processID) {
            application.activate()
        }
        targetActivationDeadline = hostTime + 0.8
        autoScrollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.continuation != nil, !self.isStopping else { return }
                if self.autoScroll?.isPaused == false {
                    let timestamp = self.hostTime
                    do {
                        // An unchanged window need not emit fresh stream buffers.
                        // Actively sample it so the matching barrier also works at rest.
                        let image = try await SCScreenshotManager.captureImage(
                            contentFilter: filter, configuration: configuration)
                        guard !Task.isCancelled, self.output === output, !self.isStopping else { return }
                        if self.autoScroll?.isPaused == false {
                            output.submitSnapshot(image, timestamp: timestamp)
                        }
                    } catch {
                        guard !Task.isCancelled, self.output === output else { return }
                        self.pauseAutoScroll(.stalled)
                    }
                }
                await self.advanceAutoScroll()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    private func advanceAutoScroll() async {
        guard autoScroll?.isPaused == false, let target else { return }
        guard let processID = target.window.owningApplication?.processID else {
            pauseAutoScroll(.targetChanged)
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else {
            if hostTime < targetActivationDeadline { return }
            pauseAutoScroll(.targetChanged)
            return
        }
        targetActivationDeadline = 0
        let captureRect = CGRect(x: target.window.frame.minX + target.cropRect.minX,
                                 y: target.window.frame.minY + target.cropRect.minY,
                                 width: target.cropRect.width, height: target.cropRect.height)
        guard let pointer = CGEvent(source: nil)?.location, captureRect.contains(pointer) else {
            waitingForPointer = true
            previewController.showAutoScroll(paused: false, waitingForPointer: true)
            return
        }
        if waitingForPointer {
            // Moving out suspends input without moving the cursor. Start a fresh
            // frame barrier on re-entry rather than timing out the suspended step.
            waitingForPointer = false
            autoScroll?.resume(now: hostTime)
            previewController.showAutoScroll(paused: false)
            return
        }
        switch autoScroll?.tick(now: hostTime) ?? .wait {
        case .wait: break
        case .scroll(let points):
            let point = pointer
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
            let hitWindow = windows?.first { info in
                guard (info[kCGWindowLayer as String] as? Int) == 0,
                      let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
                return rect.contains(point)
            }
            guard (hitWindow?[kCGWindowNumber as String] as? UInt32) == target.window.windowID else {
                pauseAutoScroll(.targetChanged)
                return
            }
            guard CGPreflightPostEventAccess(),
                  let event = ScrollCaptureAutoScroll.scrollEvent(points: points) else {
                pauseAutoScroll(.stalled)
                return
            }
            // A synthetic wheel location also repositions the real cursor. Keep
            // the event's current pointer location and only scroll inside the selection.
            guard captureRect.contains(event.location) else { return }
            event.post(tap: .cghidEventTap)
        case .finish: await finishCapture()
        case .pause(let reason): pauseAutoScroll(reason)
        }
    }

    private func pauseAutoScroll(_ reason: ScrollCaptureAutoScroll.PauseReason) {
        autoScroll?.pause(reason)
        output?.setCapturePaused(reason == .user)
        output?.setAutomaticSampling(false)
        previewController.showAutoScroll(paused: true, statusKey: "scrollCapture.auto.\(reason.rawValue)")
    }

    private func toggleAutoScroll() {
        guard continuation != nil, !isStopping else { return }
        if autoScroll?.isPaused == false {
            pauseAutoScroll(.user)
        } else {
            guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
                previewController.showAutoScroll(paused: true, statusKey: "scrollCapture.auto.permission")
                return
            }
            guard let processID = target?.window.owningApplication?.processID,
                  let application = NSRunningApplication(processIdentifier: processID),
                  application.activate() else { pauseAutoScroll(.targetChanged); return }
            autoScroll?.resume(now: hostTime)
            waitingForPointer = true
            output?.setCapturePaused(false)
            output?.setAutomaticSampling(true)
            targetActivationDeadline = hostTime + 0.8
            previewController.showAutoScroll(paused: false, waitingForPointer: true)
        }
    }

    private func handle(_ progress: ScrollCaptureProgress) {
        guard continuation != nil else { return }
        switch progress.result {
        case .unmatched: hasUnmatchedFrames = true
        case .initial, .appended, .duplicate, .revisited: hasUnmatchedFrames = false
        case .limitReached: break
        }
        previewController.update(progress)
        if autoScroll?.isPaused == false { previewController.showAutoScroll(paused: false, waitingForPointer: waitingForPointer) }
        if progress.result == .limitReached {
            autoScroll?.pause(.stalled)
            previewController.showAutoScroll(paused: true)
            previewController.showLimitReached()
        }
    }

    private func finishCapture() async {
        guard !isStopping, continuation != nil else { return }
        pauseAutoScroll(.user)
        if output?.hasUnmatchedFrames() ?? hasUnmatchedFrames {
            // Preserve the valid partial image while offering a way to regain overlap before finalizing.
            let alert = NSAlert()
            alert.messageText = L10n.text("scrollCapture.unmatchedFinish.title")
            alert.informativeText = L10n.text("scrollCapture.unmatchedFinish.help")
            alert.addButton(withTitle: L10n.text("scrollCapture.unmatchedFinish.continue"))
            alert.addButton(withTitle: L10n.text("scrollCapture.unmatchedFinish.savePartial"))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        isStopping = true
        autoScrollTask?.cancel()
        if let stream { try? await stream.stopCapture() }
        guard let output, output.hasAppendedContent() else {
            complete(throwing: PinboardShotError.scrollCaptureNoMovement)
            return
        }
        guard let image = output.finalImage() else {
            complete(throwing: PinboardShotError.imageEncodingFailed)
            return
        }
        let logicalWidth = target?.cropRect.width ?? CGFloat(image.width)
        let logicalSize = CGSize(
            width: logicalWidth,
            height: CGFloat(image.height) * logicalWidth / CGFloat(image.width)
        )
        complete(returning: NSImage(cgImage: image, size: logicalSize))
    }

    private func cancelCapture() async {
        guard !isStopping, continuation != nil else { return }
        isStopping = true
        autoScrollTask?.cancel()
        if let stream { try? await stream.stopCapture() }
        output?.cancel()
        complete(returning: nil)
    }

    private func complete(returning image: NSImage?) {
        guard let continuation else { return }
        previewController.close()
        reset()
        continuation.resume(returning: image)
    }

    private func complete(throwing error: Error) {
        guard let continuation else { return }
        previewController.close()
        reset()
        continuation.resume(throwing: error)
    }

    private func reset() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScroll = nil
        targetActivationDeadline = 0
        waitingForPointer = false
        output?.cancel()
        continuation = nil
        stream = nil
        output = nil
        target = nil
        isStopping = false
        hasUnmatchedFrames = false
    }
}

@MainActor
private final class ScrollCapturePreviewController: NSObject, NSWindowDelegate {
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var onToggleAutoScroll: (() -> Void)?

    private let panel: NSPanel
    private let imageView = ScrollCapturePreviewImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: L10n.text("scrollCapture.status.ready"))
    private let sizeLabel = NSTextField(labelWithString: "—")
    private let finishButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private let autoScrollButton = NSButton(title: "", target: nil, action: nil)
    private var autoPausedStatusKey: String?
    private var hasStartedAutoCapture = false
    private var isClosingProgrammatically = false

    override init() {
        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 620),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    func show(near selection: CGRect, on screen: NSScreen) {
        isClosingProgrammatically = false
        panel.title = L10n.text("scrollCapture.title")
        titleLabel.stringValue = L10n.text("scrollCapture.title")
        finishButton.title = L10n.text("scrollCapture.stop")
        finishButton.isEnabled = true
        cancelButton.title = L10n.text("common.cancel")
        statusLabel.stringValue = L10n.text("scrollCapture.status.ready")
        sizeLabel.stringValue = "—"
        imageView.image = nil
        imageView.resetDocumentSize()
        hasStartedAutoCapture = false
        showAutoScroll(paused: true, statusKey: "scrollCapture.auto.ready")

        let visible = screen.visibleFrame
        let size = panel.frame.size
        let preferredX = selection.maxX + 16
        let x = preferredX + size.width <= visible.maxX
            ? preferredX
            : max(visible.minX, selection.minX - size.width - 16)
        let y = min(max(selection.maxY - size.height, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    func update(_ progress: ScrollCaptureProgress) {
        statusLabel.textColor = .secondaryLabelColor
        if let preview = progress.previewImage {
            imageView.image = NSImage(
                cgImage: preview,
                size: CGSize(width: preview.width, height: preview.height)
            )
            imageView.updateDocumentSize()
        }
        sizeLabel.stringValue = "\(progress.pixelWidth) × \(progress.pixelHeight) px"
        switch progress.result {
        case .initial, .duplicate:
            statusLabel.stringValue = L10n.text("scrollCapture.status.ready")
        case .appended:
            statusLabel.stringValue = L10n.text("scrollCapture.status.capturing")
        case .revisited:
            statusLabel.stringValue = L10n.text("scrollCapture.status.revisited")
        case .unmatched:
            statusLabel.stringValue = L10n.text("scrollCapture.status.unmatched")
        case .limitReached:
            showLimitReached()
        }
        if let autoPausedStatusKey { statusLabel.stringValue = L10n.text(autoPausedStatusKey) }
    }

    func showAutoScroll(paused: Bool, statusKey: String = "scrollCapture.auto.user", waitingForPointer: Bool = false) {
        let key = paused ? statusKey : (waitingForPointer ? "scrollCapture.auto.pointer" : "scrollCapture.auto.running")
        autoPausedStatusKey = paused || waitingForPointer ? key : nil
        if !paused { hasStartedAutoCapture = true }
        autoScrollButton.title = L10n.text(paused
            ? (hasStartedAutoCapture ? "scrollCapture.auto.resume" : "scrollCapture.auto.start")
            : "scrollCapture.auto.pause")
        statusLabel.stringValue = L10n.text(key)
    }

    func showBrowserCapture() {
        autoPausedStatusKey = nil
        panel.title = L10n.text("browserExtension.title")
        titleLabel.stringValue = L10n.text("browserExtension.title")
        statusLabel.stringValue = L10n.text("browserExtension.detectedHelp")
        autoScrollButton.title = L10n.text("browserExtension.autoStart")
        finishButton.isEnabled = false
    }

    func showLimitReached() {
        statusLabel.stringValue = L10n.text("scrollCapture.status.limitReached")
        statusLabel.textColor = .systemOrange
    }

    func close() {
        isClosingProgrammatically = true
        panel.orderOut(nil)
        statusLabel.textColor = .secondaryLabelColor
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosingProgrammatically else { return }
        onCancel?()
    }

    private func configurePanel() {
        panel.title = L10n.text("scrollCapture.title")
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = NSView()
        titleLabel.stringValue = L10n.text("scrollCapture.title")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .secondaryLabelColor

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.documentView = imageView
        imageView.scrollView = scrollView

        finishButton.target = self
        finishButton.action = #selector(finishPressed)
        finishButton.title = L10n.text("common.done")
        finishButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.title = L10n.text("common.cancel")
        autoScrollButton.target = self
        autoScrollButton.action = #selector(toggleAutoPressed)
        let buttonStack = NSStackView(views: [autoScrollButton, cancelButton, finishButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillProportionally
        buttonStack.spacing = 8

        let stack = NSStackView(views: [titleLabel, statusLabel, scrollView, sizeLabel, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        panel.contentView = content

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),
            buttonStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func finishPressed() { onFinish?() }
    @objc private func cancelPressed() { onCancel?() }
    @objc private func toggleAutoPressed() { onToggleAutoScroll?() }
}

@MainActor
final class ScrollCapturePreviewImageView: NSView {
    weak var scrollView: NSScrollView?
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    func resetDocumentSize() {
        guard let scrollView else { return }
        frame = CGRect(origin: .zero, size: scrollView.contentSize)
        needsDisplay = true
    }

    func updateDocumentSize() {
        guard let scrollView, let image, image.size.width > 0 else { return }
        let width = max(1, scrollView.contentSize.width)
        let height = max(scrollView.contentSize.height, width * image.size.height / image.size.width)
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        needsDisplay = true
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func draw(_ dirtyRect: NSRect) {
        let documentVisibleRect = scrollView?.documentVisibleRect ?? dirtyRect
        let visibleDirtyRect = dirtyRect.intersection(documentVisibleRect)
        NSColor.windowBackgroundColor.setFill()
        visibleDirtyRect.fill()
        guard let image, let drawingRects = drawingRects(for: dirtyRect) else { return }
        image.draw(
            in: drawingRects.destination,
            from: drawingRects.source,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.medium]
        )
    }

    func drawingRects(for dirtyRect: NSRect) -> (destination: NSRect, source: NSRect)? {
        guard let image else { return nil }
        let imageRect = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.width * image.size.height / max(1, image.size.width)
        )
        let documentVisibleRect = scrollView?.documentVisibleRect ?? dirtyRect
        let destinationRect = dirtyRect
            .intersection(documentVisibleRect)
            .intersection(imageRect)
        guard !destinationRect.isNull, !destinationRect.isEmpty else { return nil }

        let scaleX = image.size.width / imageRect.width
        let scaleY = image.size.height / imageRect.height
        let sourceRect = CGRect(
            x: destinationRect.minX * scaleX,
            y: destinationRect.minY * scaleY,
            width: destinationRect.width * scaleX,
            height: destinationRect.height * scaleY
        )
        return (destinationRect, sourceRect)
    }
}
