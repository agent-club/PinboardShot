import AppKit
import Testing
@testable import PinboardShot

@Suite("Annotation canvas zoom", .serialized)
@MainActor
struct AnnotationZoomTests {
    @Test("Zooming at the pointer preserves the original image coordinate")
    func pointerAnchor() throws {
        let canvas = try makeCanvas()
        canvas.setZoomScale(2, anchoredAt: CGPoint(x: 100, y: 75))
        drawLine(canvas, from: CGPoint(x: 100, y: 75), to: CGPoint(x: 140, y: 95))
        let stroke = try #require(canvas.strokes.first)
        expectPoint(stroke.points[0], CGPoint(x: 0.25, y: 0.25))
        expectPoint(stroke.points[1], CGPoint(x: 0.3, y: 170.0 / 600))
    }

    @Test("Space drag pans without drawing and later strokes use the moved viewport")
    func panThenDraw() throws {
        let canvas = try makeCanvas()
        canvas.setZoomScale(2)
        pan(canvas, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 250, y: 180))
        #expect(canvas.strokes.isEmpty)
        drawLine(canvas, from: CGPoint(x: 90, y: 60), to: CGPoint(x: 170, y: 120))
        let stroke = try #require(canvas.strokes.first)
        expectPoint(stroke.points[0], CGPoint(x: 0.3, y: 0.3))
        expectPoint(stroke.points[1], CGPoint(x: 0.4, y: 0.4))
        canvas.undo()
        canvas.setZoomScale(3)
        canvas.redo()
        #expect(canvas.strokes == [stroke])
    }

    @Test("Pan is bounded so the image edge stays reachable without scrolling into blank space")
    func boundedPan() throws {
        let canvas = try makeCanvas()
        canvas.setZoomScale(2)
        pan(canvas, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 2_000, y: 2_000))
        drawLine(canvas, from: CGPoint(x: 40, y: 30), to: CGPoint(x: 80, y: 60))
        let stroke = try #require(canvas.strokes.first)
        expectPoint(stroke.points[0], CGPoint(x: 0.05, y: 0.05))
        expectPoint(stroke.points[1], CGPoint(x: 0.1, y: 0.1))
    }

    @Test("Zoom and pan preserve export pixels, dimensions and draft coordinates")
    func exportRemainsAtSourceResolution() throws {
        let canvas = try makeCanvas()
        drawLine(canvas, from: CGPoint(x: 40, y: 30), to: CGPoint(x: 120, y: 90))
        let before = try #require(canvas.renderedImage()?.cgImageValue)
        let original = canvas.strokes
        canvas.setZoomScale(4)
        pan(canvas, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 150, y: 100))
        let after = try #require(canvas.renderedImage()?.cgImageValue)
        #expect(after.width == 800)
        #expect(after.height == 600)
        #expect(after.dataProvider?.data == before.dataProvider?.data)
        let draft = try canvas.editableDraft()
        #expect(draft.logicalSize == CGSize(width: 400, height: 300))
        #expect(draft.strokes == original)
        canvas.zoomToFit()
        #expect(canvas.strokes == original)
    }

    @Test("Fit follows window resizing while 100 percent remains fixed and supports long images")
    func fitAndActualSize() throws {
        let canvas = try makeCanvas(logicalSize: CGSize(width: 800, height: 600))
        #expect(canvas.zoomScale == 0.5)
        #expect(canvas.performKeyEquivalent(with: key("=", code: 24, modifiers: .command)))
        #expect(canvas.zoomScale == 0.625)
        #expect(canvas.performKeyEquivalent(with: key("1", code: 18, modifiers: .command)))
        canvas.frame.size = CGSize(width: 200, height: 150)
        canvas.layoutSubtreeIfNeeded()
        #expect(canvas.zoomScale == 1)
        #expect(canvas.performKeyEquivalent(with: key("0", code: 29, modifiers: .command)))
        #expect(canvas.zoomScale == 0.25)
        canvas.frame.size = CGSize(width: 400, height: 300)
        canvas.layoutSubtreeIfNeeded()
        #expect(canvas.zoomScale == 0.5)
        let longImage = try makeCanvas(logicalSize: CGSize(width: 400, height: 30_000))
        #expect(longImage.zoomScale == 0.01)
        longImage.setZoomScale(1)
        #expect(longImage.zoomScale == 1)
    }

    @Test("Zoom limits and viewport changes cancel pending drawing")
    func limitsAndGestureCancellation() throws {
        let canvas = try makeCanvas()
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 75), time: 1))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 120, y: 95), time: 1.1))
        canvas.setZoomScale(100)
        #expect(canvas.zoomScale == 8)
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 140, y: 110), time: 1.2))
        #expect(canvas.strokes.isEmpty)
        canvas.setZoomScale(0.001)
        #expect(canvas.zoomScale == 0.1)
        canvas.setZoomScale(.infinity)
        #expect(canvas.zoomScale == 0.1)
    }

    @Test("Text entry and reediting scale visually while storing the original font width")
    func textAtZoom() throws {
        let canvas = try makeCanvas()
        canvas.tool = .text
        canvas.brushPixelWidth = 12
        canvas.setZoomScale(2)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 120, y: 120), time: 1))
        let field = try #require(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(field.font?.pointSize == 48)
        field.stringValue = "Zoom text"
        canvas.zoomToFit()
        let stroke = try #require(canvas.strokes.first)
        #expect(abs(stroke.width - 0.08) < 0.000001)
        expectPoint(stroke.points[0], CGPoint(x: 0.4, y: 0.45))
        canvas.setZoomScale(2)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 180, y: 140), time: 3, clicks: 2))
        let editor = try #require(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(editor.stringValue == "Zoom text")
        #expect(editor.font?.pointSize == 48)
        canvas.commitPendingText()
        #expect(canvas.strokes.count == 1)
        #expect(canvas.strokes[0] == stroke)
        // Hit the far end of the enlarged text to exercise scaled selection bounds.
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 260, y: 140), time: 5))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 300, y: 170), time: 5.1))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 300, y: 170), time: 5.2))
        #expect(canvas.strokes.count == 1)
        expectPoint(canvas.strokes[0].points[0], CGPoint(x: 0.45, y: 0.5))
    }

    @Test("The selection overlay keeps its existing unzoomed coordinates")
    func sharedCanvasIsOptIn() throws {
        let canvas = try makeCanvas()
        canvas.allowsViewportNavigation = false
        canvas.setZoomScale(2)
        drawLine(canvas, from: CGPoint(x: 40, y: 30), to: CGPoint(x: 80, y: 60))
        let stroke = try #require(canvas.strokes.first)
        expectPoint(stroke.points[0], CGPoint(x: 0.1, y: 0.1))
        expectPoint(stroke.points[1], CGPoint(x: 0.2, y: 0.2))
    }

    @Test("Cropping and rotating reset the viewport for the new image")
    func sourceChangesResetZoom() throws {
        let canvas = try makeCanvas()
        canvas.tool = .rectangle
        canvas.setZoomScale(2)
        drawLine(canvas, from: CGPoint(x: 40, y: 30), to: CGPoint(x: 360, y: 270))
        #expect(canvas.cropToSelectedRectangle())
        #expect(abs(canvas.zoomScale - 2.5) < 0.000001)
        canvas.setZoomScale(4)
        canvas.rotateClockwise()
        #expect(abs(canvas.zoomScale - 1.875) < 0.000001)
    }

    @Test("Editor zoom controls fit the minimum window and return keyboard focus to the canvas")
    func editorControls() async throws {
        let fixture = try makeCanvas()
        let editor = AnnotationEditorController()
        let image = NSImage(cgImage: fixture.sourceImageForAnalysis, size: CGSize(width: 800, height: 600))
        let task = Task { await editor.edit(image: image, initialTool: .line, keepDraft: false) }
        try await Task.sleep(for: .milliseconds(100))
        let window = try #require(NSApp.windows.first { $0.title == L10n.text("annotation.title") && $0.isVisible })
        defer { window.performClose(nil) }
        window.setContentSize(CGSize(width: 840, height: 480))
        let root = try #require(window.contentView)
        root.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
        let views = descendants(root)
        let canvas = try #require(views.compactMap { $0 as? AnnotationCanvasView }.first)
        let buttons = views.compactMap { $0 as? NSButton }
        let zoomIn = try #require(buttons.first { $0.toolTip == L10n.text("annotation.zoom.in") })
        let zoomOut = try #require(buttons.first { $0.toolTip == L10n.text("annotation.zoom.out") })
        let fit = try #require(buttons.first { $0.title == L10n.text("annotation.zoom.fit") })
        let actual = try #require(buttons.first { $0.title == "100%" })
        for button in [zoomIn, zoomOut, fit, actual] {
            #expect(root.bounds.contains(button.convert(button.bounds, to: root)))
        }
        let fitScale = canvas.zoomScale
        zoomIn.performClick(nil)
        #expect(abs(canvas.zoomScale - fitScale * 1.25) < 0.000001)
        zoomOut.performClick(nil)
        #expect(abs(canvas.zoomScale - fitScale) < 0.000001)
        actual.performClick(nil)
        #expect(canvas.zoomScale == 1)
        #expect(window.firstResponder === canvas)
        fit.performClick(nil)
        #expect(abs(canvas.zoomScale - fitScale) < 0.000001)
        #expect(window.performKeyEquivalent(with: key("1", code: 18, modifiers: .command)))
        #expect(canvas.zoomScale == 1)
        canvas.setZoomScale(2)
        canvas.keyDown(with: key(" ", code: 49))
        editor.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        drawLine(canvas,
                 from: canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil),
                 to: canvas.convert(CGPoint(x: canvas.bounds.midX + 20, y: canvas.bounds.midY + 10), to: nil))
        #expect(canvas.strokes.count == 1)
        window.performClose(nil)
        #expect(await task.value == nil)
    }

    @Test("Scroll gestures pan the canvas and command-scroll zooms without committing strokes")
    func scrollNavigation() throws {
        let canvas = try makeCanvas()
        canvas.setZoomScale(2)
        let panEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: 30, wheel2: 40, wheel3: 0))
        canvas.scrollWheel(with: try #require(NSEvent(cgEvent: panEvent)))
        #expect(canvas.strokes.isEmpty)
        drawLine(canvas, from: CGPoint(x: 80, y: 60), to: CGPoint(x: 160, y: 120))
        let stroke = try #require(canvas.strokes.first)
        expectPoint(stroke.points[0], CGPoint(x: 0.3, y: 0.3))
        let zoomEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
            wheel1: 20, wheel2: 0, wheel3: 0))
        zoomEvent.flags = .maskCommand
        canvas.scrollWheel(with: try #require(NSEvent(cgEvent: zoomEvent)))
        #expect(canvas.zoomScale > 2)
        #expect(canvas.strokes == [stroke])
    }

    private func makeCanvas(logicalSize: CGSize = CGSize(width: 400, height: 300)) throws -> AnnotationCanvasView {
        _ = NSApplication.shared
        let context = try #require(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let canvas = AnnotationCanvasView(sourceImage: try #require(context.makeImage()), logicalSize: logicalSize, contentInset: 0)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        canvas.tool = .line
        canvas.annotationColor = .red
        canvas.allowsViewportNavigation = true
        return canvas
    }

    private func drawLine(_ canvas: AnnotationCanvasView, from start: CGPoint, to end: CGPoint) {
        canvas.mouseDown(with: mouse(.leftMouseDown, start, time: 10))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, end, time: 10.1))
        canvas.mouseUp(with: mouse(.leftMouseUp, end, time: 10.2))
    }

    private func pan(_ canvas: AnnotationCanvasView, from start: CGPoint, to end: CGPoint) {
        canvas.keyDown(with: key(" ", code: 49))
        canvas.mouseDown(with: mouse(.leftMouseDown, start, time: 5))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, end, time: 5.1))
        canvas.mouseUp(with: mouse(.leftMouseUp, end, time: 5.2))
        canvas.keyUp(with: key(" ", code: 49, type: .keyUp))
    }

    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint, time: Double, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    private func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 1,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code)!
    }

    private func expectPoint(_ point: CGPoint, _ expected: CGPoint) {
        #expect(abs(point.x - expected.x) < 0.000001)
        #expect(abs(point.y - expected.y) < 0.000001)
    }
}
