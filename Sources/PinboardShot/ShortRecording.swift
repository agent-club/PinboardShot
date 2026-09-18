import AppKit
@preconcurrency import AVFoundation
import AVKit
@preconcurrency import ScreenCaptureKit
import SwiftUI
import QuartzCore

enum RecordingGeometry {
    static func dimensions(size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite,
              size.width > 0, size.height > 0, scale > 0 else { return (2, 2) }
        let factor = min(scale, 1920 / size.width, 1080 / size.height)
        return (max(2, Int(size.width * factor) / 2 * 2), max(2, Int(size.height * factor) / 2 * 2))
    }

    static func trimRange(start: Double, end: Double, duration: Double) throws -> CMTimeRange {
        guard start.isFinite, end.isFinite, duration.isFinite,
              start >= 0, end <= duration + 0.001, end > start, end - start >= 0.05 else {
            throw CaptureFeatureError.invalidDocument
        }
        return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                           end: CMTime(seconds: min(end, duration), preferredTimescale: 600))
    }
}

/// All mutable writer state is confined to queue, including finishing and cancellation.
final class ShortRecordingWriter: @unchecked Sendable {
    let queue = DispatchQueue(label: "PinboardShot.recording.writer")
    let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var firstTime: CMTime?
    private var lastSample: CMSampleBuffer?
    private var firstHostTime: CFTimeInterval?
    private var finished = false

    init(url: URL, width: Int, height: Int) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000, AVVideoExpectedSourceFrameRateKey: 30]
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CaptureFeatureError.recordingFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CaptureFeatureError.recordingFailed }
    }

    func appendOnQueue(_ sample: CMSampleBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished, sample.isValid, CMSampleBufferGetImageBuffer(sample) != nil,
              input.isReadyForMoreMediaData, writer.status == .writing else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        guard time.isNumeric else { return }
        if let lastSample, time <= CMSampleBufferGetPresentationTimeStamp(lastSample) { return }
        if firstTime == nil {
            firstTime = time
            firstHostTime = CACurrentMediaTime()
            writer.startSession(atSourceTime: time)
        }
        if input.append(sample) { lastSample = sample }
    }

    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.finished else { continuation.resume(throwing: CaptureFeatureError.recordingFailed); return }
                self.finished = true
                guard let firstTime = self.firstTime, let lastSample = self.lastSample else {
                    self.writer.cancelWriting()
                    try? FileManager.default.removeItem(at: self.url)
                    continuation.resume(throwing: CaptureFeatureError.noVideoFrames)
                    return
                }
                // Static screens may only emit one complete frame. Repeat it at stop time.
                let elapsed = max(1.0 / 30, CACurrentMediaTime() - (self.firstHostTime ?? CACurrentMediaTime()))
                let lastTime = CMSampleBufferGetPresentationTimeStamp(lastSample)
                let end = max(lastTime + CMTime(value: 1, timescale: 30), firstTime + CMTime(seconds: elapsed, preferredTimescale: 600))
                if self.input.isReadyForMoreMediaData {
                    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: end, decodeTimeStamp: .invalid)
                    var duplicate: CMSampleBuffer?
                    if CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: lastSample,
                        sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &duplicate) == noErr, let duplicate {
                        _ = self.input.append(duplicate)
                    }
                }
                self.writer.endSession(atSourceTime: end + CMTime(value: 1, timescale: 30))
                self.input.markAsFinished()
                self.lastSample = nil
                self.writer.finishWriting {
                    if self.writer.status == .completed {
                        continuation.resume(returning: self.url)
                    } else {
                        try? FileManager.default.removeItem(at: self.url)
                        continuation.resume(throwing: self.writer.error ?? CaptureFeatureError.recordingFailed)
                    }
                }
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if !self.finished {
                    self.finished = true
                    self.lastSample = nil
                    self.writer.cancelWriting()
                }
                try? FileManager.default.removeItem(at: self.url)
                continuation.resume()
            }
        }
    }
}

private final class RecordingOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let writer: ShortRecordingWriter
    init(writer: ShortRecordingWriter) { self.writer = writer }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue else { return }
        writer.appendOnQueue(sampleBuffer)
    }
}

enum RecordingExporter {
    static func trim(source: URL, destination: URL, start: Double, end: Double) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let range = try RecordingGeometry.trimRange(start: start, end: end, duration: duration)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw CaptureFeatureError.recordingFailed
        }
        // Stage beside the destination so replacing an existing user-approved file is atomic.
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".pinboardshot-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: staging) }
        session.outputURL = staging
        session.outputFileType = .mp4
        session.timeRange = range
        await session.export()
        guard session.status == .completed else { throw session.error ?? CaptureFeatureError.recordingFailed }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }
}

@MainActor
final class ShortRecordingController: NSObject, SCStreamDelegate, NSWindowDelegate, ObservableObject {
    @Published private(set) var elapsed = 0
    @Published private(set) var isFinishing = false
    private(set) var isBusy = false
    private var stream: SCStream?
    private var output: RecordingOutput?
    private var folder: URL?
    private var controls: NSWindow?
    private var preview: NSWindow?
    private var timer: Timer?
    private var startedAt: Date?
    private var isExporting = false
    private var previewHasUnsavedChanges = false
    var hasUnsavedVideo: Bool { previewHasUnsavedChanges && folder != nil }
    var isExportingVideo: Bool { isExporting }
    var onError: ((Error) -> Void)?

    func prepareNewRecording() -> Bool {
        guard !isBusy, !isExporting else { preview?.makeKeyAndOrderFront(nil); return false }
        if hasUnsavedVideo {
            let alert = NSAlert()
            alert.messageText = L10n.text("feature.record.discardTitle")
            alert.informativeText = L10n.text("feature.record.discardHelp")
            alert.addButton(withTitle: L10n.text("common.cancel"))
            alert.addButton(withTitle: L10n.text("feature.guide.discard"))
            guard alert.runModal() == .alertSecondButtonReturn else { preview?.makeKeyAndOrderFront(nil); return false }
        }
        discardPreview()
        return true
    }

    func start(displayID: CGDirectDisplayID, sourceRect: CGRect) async throws {
        guard !isBusy else { return }
        discardPreview()
        isBusy = true
        isFinishing = false
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw PinboardShotError.displayUnavailable }
            let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = sourceRect
            let dimensions = RecordingGeometry.dimensions(size: sourceRect.size, scale: CGFloat(filter.pointPixelScale))
            configuration.width = dimensions.width
            configuration.height = dimensions.height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 5
            configuration.showsCursor = true
            configuration.capturesAudio = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PinboardShot-recording-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            self.folder = folder
            let writer = try ShortRecordingWriter(url: folder.appendingPathComponent("recording.mp4"), width: dimensions.width, height: dimensions.height)
            let output = RecordingOutput(writer: writer)
            self.output = output
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            self.stream = stream
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: writer.queue)
            try await stream.startCapture()
            elapsed = 0
            startedAt = Date()
            showControls()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isFinishing else { return }
                    self.elapsed = Int(Date().timeIntervalSince(self.startedAt ?? Date()))
                    if self.elapsed >= 60 { await self.stop() }
                }
            }
        } catch {
            await cancel()
            throw error
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.isBusy, !self.isFinishing else { return }
            await self.cancel()
            self.onError?(error)
        }
    }

    func stop() async {
        guard isBusy, !isFinishing else { return }
        isFinishing = true
        timer?.invalidate()
        timer = nil
        do {
            try await stream?.stopCapture()
            guard let writer = output?.writer else { throw CaptureFeatureError.recordingFailed }
            let url = try await writer.finish()
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw CaptureFeatureError.noVideoFrames }
            stream = nil
            output = nil
            controls?.close()
            controls = nil
            isBusy = false
            isFinishing = false
            showPreview(url: url, duration: duration)
        } catch {
            await cancel()
            onError?(error)
        }
    }

    func cancel() async {
        isFinishing = true
        timer?.invalidate()
        timer = nil
        try? await stream?.stopCapture()
        await output?.writer.cancel()
        stream = nil
        output = nil
        controls?.close()
        controls = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        isBusy = false
        isFinishing = false
    }

    func discardPreview() {
        guard !isExporting else { return }
        preview?.close()
        preview = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        previewHasUnsavedChanges = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === preview, isExporting { NSSound.beep(); return false }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === preview else { return }
        preview?.contentViewController = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        previewHasUnsavedChanges = false
    }

    private func showControls() {
        let view = RecordingControls(model: self)
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 96),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L10n.text("feature.record.title")
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: view)
        panel.setContentSize(CGSize(width: 360, height: 96))
        panel.center()
        controls = panel
        panel.orderFrontRegardless()
    }

    private func showPreview(url: URL, duration: Double) {
        previewHasUnsavedChanges = true
        let view = RecordingPreview(url: url, duration: duration,
            onExportState: { [weak self] exporting in self?.isExporting = exporting },
            onSaved: { [weak self] in self?.previewHasUnsavedChanges = false })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = L10n.text("feature.record.preview")
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 820, height: 580))
        window.minSize = CGSize(width: 700, height: 480)
        window.delegate = self
        window.center()
        preview = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct RecordingControls: View {
    @ObservedObject var model: ShortRecordingController
    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.text("feature.record.status", model.elapsed)).monospacedDigit()
            HStack {
                Button(L10n.text("common.cancel")) { Task { await model.cancel() } }
                Button(L10n.text("feature.record.stop"), systemImage: "stop.fill") { Task { await model.stop() } }
                    .keyboardShortcut(.defaultAction)
            }.disabled(model.isFinishing)
        }.padding(12)
    }
}

private struct RecordingPreview: View {
    let url: URL
    let duration: Double
    @State private var player: AVPlayer
    @State private var start = 0.0
    @State private var end: Double
    @State private var saving = false
    @State private var message: String?
    let onExportState: (Bool) -> Void
    let onSaved: () -> Void

    init(url: URL, duration: Double, onExportState: @escaping (Bool) -> Void, onSaved: @escaping () -> Void) {
        self.url = url
        self.duration = duration
        _end = State(initialValue: duration)
        _player = State(initialValue: AVPlayer(url: url))
        self.onExportState = onExportState
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoPlayer(player: player)
            Text(L10n.text("feature.record.trimHelp")).foregroundStyle(.secondary)
            HStack {
                Text(L10n.text("feature.record.trimStart"))
                Slider(value: $start, in: 0...duration)
                TextField("s", value: $start, format: .number.precision(.fractionLength(2))).frame(width: 70)
            }
            HStack {
                Text(L10n.text("feature.record.trimEnd"))
                Slider(value: $end, in: 0...duration)
                TextField("s", value: $end, format: .number.precision(.fractionLength(2))).frame(width: 70)
            }
            HStack {
                Button(L10n.text("feature.record.playTrim")) {
                    player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
                    player.play()
                }.disabled(!validRange)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button(L10n.text("feature.record.save")) { save() }.disabled(saving || !validRange)
            }
            if let message { Text(message).foregroundStyle(.secondary) }
        }
        .padding(14)
        .textFieldStyle(.roundedBorder)
        .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
    }

    private var validRange: Bool { (try? RecordingGeometry.trimRange(start: start, end: end, duration: duration)) != nil }

    private func save() {
        player.pause()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "PinboardShot-recording.mp4"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        saving = true
        onExportState(true)
        let trimStart = start
        let trimEnd = end
        Task {
            do {
                try await RecordingExporter.trim(source: url, destination: target, start: trimStart, end: trimEnd)
                message = L10n.text("feature.record.saved")
                onSaved()
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } catch { message = error.localizedDescription }
            saving = false
            onExportState(false)
        }
    }
}
