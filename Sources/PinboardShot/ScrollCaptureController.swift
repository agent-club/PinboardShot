import AppKit
import CoreImage
import CoreMedia
import CoreVideo
@preconcurrency import ScreenCaptureKit

struct ScrollCaptureProgress: @unchecked Sendable {
    let previewImage: CGImage?
    let pixelWidth: Int
    let pixelHeight: Int
    let result: ScrollCaptureAppendResult
}

final class ScrollCaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "com.ryanwang.PinboardShot.scroll-capture", qos: .userInitiated)

    private let target: ScrollCaptureTarget
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let accumulator = ScrollCaptureAccumulator()
    private let onProgress: @Sendable (ScrollCaptureProgress) -> Void
    private let onError: @Sendable (Error) -> Void
    private var appendedFrameCount = 0
    private var consecutiveUnmatchedFrames = 0
    private var lastPreviewDate = Date.distantPast
    private var didReachLimit = false

    init(
        target: ScrollCaptureTarget,
        onProgress: @escaping @Sendable (ScrollCaptureProgress) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.target = target
        self.onProgress = onProgress
        self.onError = onError
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard !didReachLimit else { return }
        guard outputType == .screen,
              sampleBuffer.isValid,
              isUsableFrame(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer,
              let frame = croppedFrame(from: pixelBuffer) else { return }

        let result = accumulator.append(frame)
        switch result {
        case .initial:
            consecutiveUnmatchedFrames = 0
        case .appended:
            appendedFrameCount += 1
            consecutiveUnmatchedFrames = 0
        case .duplicate:
            consecutiveUnmatchedFrames = 0
            return
        case .revisited:
            consecutiveUnmatchedFrames = 0
        case .unmatched:
            consecutiveUnmatchedFrames += 1
            guard consecutiveUnmatchedFrames == 5 else { return }
        case .limitReached:
            didReachLimit = true
        }

        let shouldRenderPreview = result == .initial ||
            Date().timeIntervalSince(lastPreviewDate) >= 0.12 ||
            result == .limitReached
        let preview = shouldRenderPreview ? accumulator.makePreviewImage() : nil
        if shouldRenderPreview { lastPreviewDate = Date() }
        onProgress(ScrollCaptureProgress(
            previewImage: preview,
            pixelWidth: accumulator.pixelWidth,
            pixelHeight: accumulator.pixelHeight,
            result: result
        ))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(error)
    }

    func finalImage() -> CGImage? {
        sampleQueue.sync { accumulator.makeImage() }
    }

    func hasAppendedContent() -> Bool {
        sampleQueue.sync { accumulator.hasContent }
    }

    private func isUsableFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRawValue = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return false
        }
        return status == .complete || status == .started
    }

    private func croppedFrame(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let fullImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let full = context.createCGImage(fullImage, from: fullImage.extent) else { return nil }
        let scaleX = CGFloat(full.width) / target.window.frame.width
        let scaleY = CGFloat(full.height) / target.window.frame.height
        let cropRect = CGRect(
            x: target.cropRect.minX * scaleX,
            y: target.cropRect.minY * scaleY,
            width: target.cropRect.width * scaleX,
            height: target.cropRect.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard !cropRect.isNull, cropRect.width > 0, cropRect.height > 0 else { return nil }
        return full.cropping(to: cropRect)
    }
}

@MainActor
final class ScrollCaptureController {
    private let previewController = ScrollCapturePreviewController()
    private var continuation: CheckedContinuation<NSImage?, Error>?
    private var stream: SCStream?
    private var output: ScrollCaptureStreamOutput?
    private var target: ScrollCaptureTarget?
    private var isStopping = false

    func capture(target: ScrollCaptureTarget) async throws -> NSImage? {
        guard continuation == nil else { throw PinboardShotError.captureBusy }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.target = target
            previewController.onFinish = { [weak self] in
                Task { @MainActor in await self?.finishCapture() }
            }
            previewController.onCancel = { [weak self] in
                Task { @MainActor in await self?.cancelCapture() }
            }
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
            onError: { [weak self] error in
                Task { @MainActor in self?.complete(throwing: error) }
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
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 12)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.sampleQueue)
        self.output = output
        self.stream = stream
        try await stream.startCapture()

        if let processID = target.window.owningApplication?.processID,
           let application = NSRunningApplication(processIdentifier: processID) {
            application.activate()
        }
    }

    private func handle(_ progress: ScrollCaptureProgress) {
        guard continuation != nil else { return }
        previewController.update(progress)
        if progress.result == .limitReached {
            previewController.showLimitReached()
        }
    }

    private func finishCapture() async {
        guard !isStopping, continuation != nil else { return }
        isStopping = true
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
        if let stream { try? await stream.stopCapture() }
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
        continuation = nil
        stream = nil
        output = nil
        target = nil
        isStopping = false
    }
}

@MainActor
private final class ScrollCapturePreviewController: NSObject, NSWindowDelegate {
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?

    private let panel: NSPanel
    private let imageView = ScrollCapturePreviewImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: L10n.text("scrollCapture.status.ready"))
    private let sizeLabel = NSTextField(labelWithString: "—")
    private let finishButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
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
        finishButton.title = L10n.text("common.done")
        cancelButton.title = L10n.text("common.cancel")
        statusLabel.stringValue = L10n.text("scrollCapture.status.ready")
        sizeLabel.stringValue = "—"
        imageView.image = nil
        imageView.resetDocumentSize()

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
        let buttonStack = NSStackView(views: [cancelButton, finishButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
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
