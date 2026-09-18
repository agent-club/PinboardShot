import AppKit
@preconcurrency import AVFoundation
import PDFKit
import Testing
@testable import PinboardShot

private func featureImage(width: Int = 96, height: Int = 120) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for row in 0..<height {
        for column in 0..<width {
            let index = (row * width + column) * 4
            bytes[index] = UInt8(row % 256)
            bytes[index + 1] = 76
            bytes[index + 2] = 178
            bytes[index + 3] = 255
        }
    }
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
}

private func redRows(_ image: CGImage) throws -> [Int] {
    let bitmap = NSBitmapImageRep(cgImage: image)
    return (0..<image.height).map { row in
        var components = [UInt](repeating: 0, count: 4)
        bitmap.getPixel(&components, atX: 0, y: row)
        return Int(components[0])
    }
}

private final class DraftFileManager: FileManager {
    let root: URL
    var failDraftStaging = false
    init(root: URL) { self.root = root; super.init() }
    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        directory == .applicationSupportDirectory ? [root] : super.urls(for: directory, in: domainMask)
    }
    override func moveItem(at source: URL, to destination: URL) throws {
        if failDraftStaging && source.lastPathComponent.hasSuffix(".draft.json") { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: source, to: destination)
    }
}

@Suite("Capture feature documents", .serialized)
@MainActor
struct CaptureFeatureDocumentTests {
    @Test("Editable drafts round trip independent strokes and logical dimensions")
    func draftRoundTrip() throws {
        let source = try featureImage()
        let stroke = AnnotationStroke(tool: .text, points: [CGPoint(x: 0.2, y: 0.4)], color: AnnotationColor(.red), width: 0.05, text: "Editable label")
        let draft = try AnnotationDraft(source: source, logicalSize: CGSize(width: 48, height: 60), strokes: [stroke])
        let restored = try JSONDecoder().decode(AnnotationDraft.self, from: JSONEncoder().encode(draft))
        #expect(restored.strokes == [stroke])
        #expect(restored.logicalSize == CGSize(width: 48, height: 60))
        #expect(try redRows(restored.sourceImage()) == redRows(source))
        let canvas = AnnotationCanvasView(sourceImage: try restored.sourceImage(), logicalSize: restored.logicalSize, initialStrokes: restored.strokes)
        #expect(canvas.strokes == [stroke])
        canvas.clear()
        canvas.undo()
        #expect(canvas.strokes == [stroke])
    }

    @Test("Mosaic and redaction drafts never store source pixels or hidden annotation text", arguments: [AnnotationTool.mosaic, .redaction])
    func redactionIsFlattened(tool: AnnotationTool) throws {
        let source = try featureImage()
        let text = AnnotationStroke(tool: .text, points: [CGPoint(x: 0.3, y: 0.4)], color: AnnotationColor(.red), width: 0.03, text: "synthetic-secret")
        let mask = AnnotationStroke(tool: tool, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.8, y: 0.8)], color: AnnotationColor(.black), width: 0.5)
        let draft = try AnnotationDraft(source: source, logicalSize: CGSize(width: 96, height: 120), strokes: [text, mask])
        #expect(draft.redactionWasFlattened)
        #expect(draft.strokes.isEmpty)
        let expected = try AnnotationRenderer.render(image: source, strokes: [text, mask])
        #expect(draft.sourcePNG == NSBitmapImageRep(cgImage: expected).representation(using: .png, properties: [:]))
        #expect(draft.sourcePNG != NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:]))
        #expect(!String(decoding: try JSONEncoder().encode(draft), as: UTF8.self).contains("synthetic-secret"))
    }

    @Test("Corrupt drafts reject unbounded and non-finite geometry")
    func rejectsDraftGeometry() throws {
        let source = try featureImage()
        let stroke = AnnotationStroke(tool: .pen, points: [CGPoint(x: 3, y: 0.5)], color: AnnotationColor(.red), width: 0.05)
        let draft = try AnnotationDraft(source: source, logicalSize: CGSize(width: 96, height: 120), strokes: [stroke])
        #expect(throws: CaptureFeatureError.self) { try draft.sourceImage() }
    }

    @Test("Deleting history removes its draft and rolls both back on staging failure")
    func draftLifecycle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("draft-test-\(UUID().uuidString)")
        let suite = "DraftTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let fm = DraftFileManager(root: root)
        let store = HistoryStore(fileManager: fm, defaults: defaults)
        let source = try featureImage()
        let image = NSImage(cgImage: source, size: CGSize(width: 96, height: 120))
        let item = try #require(try store.add(image))
        let draft = try AnnotationDraft(source: source, logicalSize: image.size, strokes: [])
        try store.saveDraft(draft, for: item)
        let bytes = try store.cleanupPreview(olderThan: Date().addingTimeInterval(1)).reclaimableBytes
        #expect(bytes > (image.pngData?.count ?? 0))
        #expect(try store.draft(for: item)?.sourcePNG == draft.sourcePNG)
        fm.failDraftStaging = true
        #expect(throws: (any Error).self) { try store.delete(item) }
        #expect(store.items == [item])
        #expect(store.image(for: item) != nil)
        #expect(try store.draft(for: item) != nil)
        fm.failDraftStaging = false
        try store.delete(item)
        #expect(store.items.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("PinboardShot/History"), includingPropertiesForKeys: nil)
        #expect(!files.contains { $0.lastPathComponent.hasSuffix(".draft.json") || $0.pathExtension == "png" })
    }

    @Test("Long image removal preserves top-to-bottom pixels across multiple cuts, undo and redo")
    func longImageRows() throws {
        let source = try featureImage(width: 8, height: 100)
        var document = LongImageDocument(image: source)
        let removalCheck0 = document.removeRows(from: 20, to: 40)
        #expect(removalCheck0)
        let removalCheck1 = document.removeRows(from: 10, to: 30)
        #expect(removalCheck1)
        let expected = Array(0..<10) + Array(50..<100)
        #expect(try redRows(document.render()) == expected)
        document.undo()
        #expect(try redRows(document.render()) == Array(0..<20) + Array(40..<100))
        document.redo()
        #expect(try redRows(document.render()) == expected)
        document.undo()
        let removalCheck2 = document.removeRows(from: 0, to: 5)
        #expect(removalCheck2)
        #expect(!document.canRedo)
        let removalCheck3 = !document.removeRows(from: Int.min, to: Int.max)
        #expect(removalCheck3)
        let removalCheck4 = !document.removeRows(from: 200, to: 300)
        #expect(removalCheck4)
    }

    @Test("PNG and PDF pages preserve every row exactly once, including partial final page")
    func pagesAreContinuous() throws {
        var document = LongImageDocument(image: try featureImage(width: 8, height: 100))
        document.removeRows(from: 30, to: 45)
        let pages = try document.pages(pageHeight: 32)
        #expect(pages.map(\.height) == [32, 32, 21])
        #expect(try pages.flatMap(redRows) == Array(0..<30) + Array(45..<100))
        let pdf = try #require(PDFDocument(data: CaptureDocumentExport.imagePDF(pages)))
        #expect(pdf.pageCount == 3)
        #expect(throws: CaptureFeatureError.self) { try document.pages(pageHeight: 0) }
        #expect(throws: CaptureFeatureError.self) { try LongImageDocument.pageRanges(height: 10000, pageHeight: 1) }
    }

    @Test("OCR handles row order, blank table cells and Markdown escaping")
    func structuredOCRFormatting() {
        let boxes = [
            OCRTextBox(text: "Name", bounds: CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.05)),
            OCRTextBox(text: "Count", bounds: CGRect(x: 0.6, y: 0.8, width: 0.2, height: 0.05)),
            OCRTextBox(text: "a|b", bounds: CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.05)),
            OCRTextBox(text: "7", bounds: CGRect(x: 0.6, y: 0.4, width: 0.2, height: 0.05))
        ].reversed()
        #expect(StructuredOCR.format(Array(boxes), as: .plain) == "Name Count\na|b\n7")
        #expect(StructuredOCR.format(Array(boxes), as: .tsv) == "Name\tCount\na|b\t\n\t7")
        let markdown = StructuredOCR.format(Array(boxes), as: .markdown)
        #expect(markdown.contains("| Name | Count |\n| --- | --- |"))
        #expect(markdown.contains("a\\|b"))
        #expect(markdown.hasSuffix("|  | 7 |"))
        #expect(StructuredOCR.format(Array(boxes), as: .layout).hasSuffix("       7") || StructuredOCR.format(Array(boxes), as: .layout).contains("  7"))
        #expect(StructuredOCR.format([], as: .tsv).isEmpty)
    }

    @Test("Guides preserve editable order and export full text with image links")
    func guideExport() throws {
        let source = try featureImage()
        let png = try #require(NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:]))
        var guide = CaptureGuide(title: "Synthetic guide", steps: [
            CaptureGuideStep(title: "First", detail: "Click [button]", pngData: png),
            CaptureGuideStep(title: "Second", detail: String(repeating: "Long description. ", count: 200), pngData: png)
        ])
        guide.move(id: guide.steps[1].id, by: -1)
        let restored = try JSONDecoder().decode(CaptureGuide.self, from: JSONEncoder().encode(guide))
        #expect(restored.steps.map(\.title) == ["Second", "First"])
        try restored.validate()
        #expect(restored.markdown().contains("## 1. Second"))
        #expect(restored.markdown().contains("Click \\[button\\]"))
        #expect(restored.markdown().contains("images/step-002.png"))
        let pdf = try #require(PDFDocument(data: CaptureDocumentExport.guidePDF(restored)))
        #expect(pdf.pageCount >= 3)
        #expect(pdf.string?.contains("2. First") == true)
        #expect(pdf.string?.contains("Click [button]") == true)
    }

    @Test("Vision recognizes synthetic text and produces editable output")
    func visionRecognition() async throws {
        let image = NSImage(size: CGSize(width: 800, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 800, height: 180).fill()
        ("PinboardShot 2026" as NSString).draw(at: CGPoint(x: 32, y: 70), withAttributes: [
            .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black
        ])
        image.unlockFocus()
        let source = try #require(image.cgImageValue)
        let boxes = try await Task.detached { try StructuredOCR.recognize(image: source) }.value
        #expect(!boxes.isEmpty)
        #expect(StructuredOCR.format(boxes, as: .plain).contains("2026"))
        #expect(boxes.allSatisfy { !$0.bounds.isEmpty })
    }

    @Test("Export staging does not overwrite existing directories and removes failed output")
    func exportIsTransactional() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try CaptureDocumentExport.directory(in: root, name: "guide") { try Data([1]).write(to: $0.appendingPathComponent("one")) }
        let second = try CaptureDocumentExport.directory(in: root, name: "guide") { try Data([2]).write(to: $0.appendingPathComponent("two")) }
        #expect(first != second)
        #expect(try Data(contentsOf: first.appendingPathComponent("one")) == Data([1]))
        #expect(throws: CaptureFeatureError.self) {
            try CaptureDocumentExport.directory(in: root, name: "guide") { _ in throw CaptureFeatureError.invalidDocument }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 2)
    }

    @Test("Ruler measures pixels and points using the respective image dimensions")
    func rulerUnits() throws {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 0.3, y: 0.4)
        #expect(RulerMeasurement.label(from: start, to: end, size: CGSize(width: 100, height: 100), unit: .pixels) == "50.0 px · Δx 30.0 · Δy 40.0")
        #expect(RulerMeasurement.label(from: start, to: end, size: CGSize(width: 50, height: 50), unit: .points) == "25.0 pt · Δx 15.0 · Δy 20.0")
        let source = try featureImage()
        let stroke = AnnotationStroke(tool: .ruler, points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)], color: AnnotationColor(.red), width: 0.02, text: "76.8 px")
        let rendered = try AnnotationRenderer.render(image: source, strokes: [stroke])
        #expect(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) != NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:]))
    }

    @Test("Rotating an annotated original bakes the annotation instead of losing it")
    func rotationKeepsAnnotations() throws {
        let source = try featureImage()
        let stroke = AnnotationStroke(tool: .rectangle, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)], color: AnnotationColor(.red), width: 0.1)
        let canvas = AnnotationCanvasView(sourceImage: source, logicalSize: CGSize(width: 48, height: 60), initialStrokes: [stroke])
        canvas.rotateClockwise()
        let draft = try canvas.editableDraft()
        #expect(draft.strokes.isEmpty)
        #expect(draft.logicalSize == CGSize(width: 60, height: 48))
        let rotated = try draft.sourceImage()
        #expect(rotated.width == 120 && rotated.height == 96)
        let bitmap = NSBitmapImageRep(cgImage: rotated)
        let colors = (0..<rotated.width).compactMap { bitmap.colorAt(x: $0, y: rotated.height / 2)?.usingColorSpace(.deviceRGB) }
        #expect(colors.contains { $0.redComponent > 0.8 && $0.greenComponent < 0.3 })
    }

    @Test("Guide changes mark drafts dirty while explicit save state stays clean")
    func guideDirtyState() throws {
        let model = CaptureGuideModel()
        #expect(!model.hasUnsavedChanges)
        try model.append(NSImage(cgImage: featureImage(), size: CGSize(width: 96, height: 120)))
        #expect(model.hasUnsavedChanges)
        model.hasUnsavedChanges = false
        model.guide.steps[0].detail = "Reproduce issue"
        #expect(model.hasUnsavedChanges)
        model.guide = CaptureGuide(title: "Restored")
        model.hasUnsavedChanges = false
        #expect(!model.hasUnsavedChanges)
    }

    @Test("Crop uses top-down source rows and rotation is clockwise")
    func cropAndRotationCoordinates() throws {
        _ = NSApplication.shared
        let source = try featureImage(width: 100, height: 100)
        let canvas = AnnotationCanvasView(sourceImage: source, logicalSize: CGSize(width: 50, height: 50), contentInset: 0)
        canvas.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        canvas.tool = .rectangle
        func event(_ type: NSEvent.EventType, _ point: CGPoint, _ time: Double) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 0, y: 50), 1))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 100, y: 80), 1.1))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 100, y: 80), 1.2))
        #expect(canvas.cropToSelectedRectangle())
        let cropped = try canvas.editableDraft()
        #expect(try redRows(cropped.sourceImage()) == Array(20..<50))
        #expect(cropped.logicalSize == CGSize(width: 50, height: 15))
        let rotated = AnnotationCanvasView(sourceImage: source, logicalSize: CGSize(width: 100, height: 100))
        rotated.rotateClockwise()
        let bitmap = NSBitmapImageRep(cgImage: try rotated.editableDraft().sourceImage())
        var left = [UInt](repeating: 0, count: 4)
        var right = left
        bitmap.getPixel(&left, atX: 0, y: 0)
        bitmap.getPixel(&right, atX: 99, y: 0)
        #expect(left[0] == 99 && right[0] == 0)
        let ruler = AnnotationCanvasView(sourceImage: source, logicalSize: CGSize(width: 50, height: 50), contentInset: 0)
        ruler.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        ruler.tool = .ruler
        ruler.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 10, y: 10), 2))
        ruler.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 90, y: 10), 2.1))
        ruler.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 90, y: 10), 2.2))
        #expect(ruler.strokes.first?.text?.hasPrefix("80.0 px") == true)
        ruler.rulerUnit = .points
        #expect(ruler.strokes.first?.text?.hasPrefix("40.0 pt") == true)
        ruler.undo()
        #expect(ruler.strokes.first?.text?.hasPrefix("80.0 px") == true)
    }

    @Test("Editor exposes ruler settings and keeps actions within the minimum window size")
    func editorLayoutAndDraftDefault() async throws {
        _ = NSApplication.shared
        let source = try featureImage()
        let image = NSImage(cgImage: source, size: CGSize(width: 48, height: 60))
        let draft = try AnnotationDraft(source: source, logicalSize: image.size, strokes: [])
        let editor = AnnotationEditorController()
        let task = Task { await editor.edit(image: image, draft: draft, initialTool: .ruler, keepDraft: false) }
        try await Task.sleep(for: .milliseconds(100))
        let window = try #require(NSApp.windows.first { $0.title == L10n.text("annotation.title") && $0.isVisible })
        window.setContentSize(CGSize(width: 840, height: 480))
        window.contentView?.layoutSubtreeIfNeeded()
        let root = try #require(window.contentView)
        func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
        let views = descendants(root)
        let checkbox = try #require(views.compactMap { $0 as? NSButton }.first { $0.title == L10n.text("feature.draft.keep") })
        #expect(checkbox.state == .off)
        #expect(views.compactMap { $0 as? NSPopUpButton }.count == 2)
        let canvas = try #require(views.compactMap { $0 as? AnnotationCanvasView }.first)
        #expect(canvas.tool == .ruler)
        #expect(canvas.frame.height > 200)
        for button in views.compactMap({ $0 as? NSButton }).filter({ [L10n.text("annotation.copy"), L10n.text("annotation.pin"), L10n.text("common.cancel"), L10n.text("feature.draft.keep")].contains($0.title) }) {
            #expect(root.bounds.contains(button.convert(button.bounds, to: root)))
        }
        window.performClose(nil)
        let result = await task.value
        #expect(result == nil)
    }

    @Test("Tools window hosts synthetic image and guide without exceeding its minimum size")
    func toolsWindow() async throws {
        _ = NSApplication.shared
        let controller = CaptureToolsController()
        let image = NSImage(cgImage: try featureImage(width: 640, height: 1100), size: CGSize(width: 640, height: 1100))
        controller.show(image: image)
        let window = try #require(NSApp.windows.first { $0.title == L10n.text("feature.tools.title") && $0.isVisible })
        defer { window.close() }
        window.setContentSize(CGSize(width: 840, height: 580))
        try await Task.sleep(for: .milliseconds(200))
        #expect(window.contentView?.frame.width == 840)
        #expect(window.contentView?.frame.height == 580)
        if let folder = ProcessInfo.processInfo.environment["PINBOARDSHOT_FEATURE_SNAPSHOT_DIR"], let view = window.contentView {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("tools.png"))
        }
        controller.suspendForCapture()
        #expect(!window.isVisible)
        controller.resumeAfterCapture()
        #expect(window.isVisible)
    }
}

@Suite("Short recording", .serialized)
struct ShortRecordingTests {
    @Test("Recording sizes are even, bounded, and preserve region aspect")
    func dimensionsAndRange() throws {
        let size = RecordingGeometry.dimensions(size: CGSize(width: 1511, height: 983), scale: 2)
        #expect(size.width % 2 == 0 && size.height % 2 == 0)
        #expect(size.width <= 1920 && size.height <= 1080)
        #expect(abs(Double(size.width) / Double(size.height) - 1511.0 / 983) < 0.004)
        #expect(throws: CaptureFeatureError.self) { try RecordingGeometry.trimRange(start: 1, end: 0.5, duration: 2) }
        #expect(throws: CaptureFeatureError.self) { try RecordingGeometry.trimRange(start: .nan, end: 1, duration: 2) }
        #expect(throws: CaptureFeatureError.self) { try RecordingGeometry.trimRange(start: 0, end: 3, duration: 2) }
        #expect(try RecordingGeometry.trimRange(start: 0.25, end: 1.5, duration: 2).duration.seconds == 1.25)
    }

    @Test("Synthetic frames produce a playable silent MP4 and trimming changes duration")
    func encodeAndTrim() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try ShortRecordingWriter(url: root.appendingPathComponent("source.mp4"), width: 64, height: 48)
        for index in 0..<30 {
            let sample = SendableSample(value: try syntheticSample(frame: index))
            await withCheckedContinuation { continuation in
                writer.queue.async { writer.appendOnQueue(sample.value); continuation.resume() }
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        let url = try await writer.finish()
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(duration > 0.9 && duration < 1.2)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        let target = root.appendingPathComponent("trim.mp4")
        try Data("previous file".utf8).write(to: target)
        try await RecordingExporter.trim(source: url, destination: target, start: 0.2, end: 0.7)
        let trimmed = AVURLAsset(url: target)
        #expect(abs(try await trimmed.load(.duration).seconds - 0.5) < 0.07)
        let generator = AVAssetImageGenerator(asset: trimmed)
        let frame = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
        #expect(frame.width == 64 && frame.height == 48)
    }

    @Test("An empty or cancelled recording leaves no partial video")
    func emptyAndCancel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try ShortRecordingWriter(url: root.appendingPathComponent("empty.mp4"), width: 64, height: 48)
        await #expect(throws: CaptureFeatureError.self) { try await writer.finish() }
        #expect(!FileManager.default.fileExists(atPath: writer.url.path))
        let cancelled = try ShortRecordingWriter(url: root.appendingPathComponent("cancel.mp4"), width: 64, height: 48)
        await cancelled.cancel()
        #expect(!FileManager.default.fileExists(atPath: cancelled.url.path))
    }

    @Test("One static frame remains visible through the stop time")
    func staticScreenDuration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-static-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try ShortRecordingWriter(url: root.appendingPathComponent("static.mp4"), width: 64, height: 48)
        let sample = SendableSample(value: try syntheticSample(frame: 0))
        await withCheckedContinuation { continuation in
            writer.queue.async { writer.appendOnQueue(sample.value); continuation.resume() }
        }
        try await Task.sleep(for: .milliseconds(180))
        let url = try await writer.finish()
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(duration >= 0.18 && duration < 0.5)
    }

    private struct SendableSample: @unchecked Sendable { let value: CMSampleBuffer }

    private func syntheticSample(frame: Int) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer) == kCVReturnSuccess)
        let buffer = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(40 + frame), CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var description: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: Int64(frame + 300), timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: try #require(description), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
