import AppKit
import Testing
@testable import PinboardShot

@Suite("Annotation gesture intent", .serialized)
@MainActor
struct AnnotationGestureIntentTests {
    @Test("Clicking a drawing tool neither previews nor commits a dot", arguments: [AnnotationTool.pen, .mosaic, .rectangle, .ellipse, .highlight, .arrow, .line, .ruler, .ocr, .redaction])
    func clicksAreNotStrokes(tool: AnnotationTool) throws {
        let canvas = try makeCanvas(tool: tool)
        let before = try renderedCanvas(canvas)
        canvas.mouseDown(with: event(.leftMouseDown, x: 50, y: 50, time: 1))
        #expect(try renderedCanvas(canvas) == before)
        canvas.mouseUp(with: event(.leftMouseUp, x: 50, y: 50, time: 1.1))
        #expect(canvas.strokes.isEmpty)
        #expect(try renderedCanvas(canvas) == before)
    }

    @Test("Small pointer jitter is a click at every display scale", arguments: [CGFloat(200), 400, 800])
    func jitterDoesNotDraw(width: CGFloat) throws {
        let canvas = try makeCanvas(tool: .pen, width: width)
        let before = try renderedCanvas(canvas)
        canvas.mouseDown(with: event(.leftMouseDown, x: 50, y: 50, time: 1))
        for index in 1...8 {
            canvas.mouseDragged(with: event(.leftMouseDragged, x: 50 + CGFloat(index) / 5, y: 50.5, time: 1 + Double(index) / 100))
        }
        #expect(try renderedCanvas(canvas) == before)
        canvas.mouseUp(with: event(.leftMouseUp, x: 52, y: 50.5, time: 1.1))
        #expect(canvas.strokes.isEmpty)
        canvas.mouseDown(with: event(.leftMouseDown, x: 50, y: 50, time: 3))
        canvas.mouseDragged(with: event(.leftMouseDragged, x: 54, y: 50, time: 3.1))
        canvas.mouseUp(with: event(.leftMouseUp, x: 56, y: 50, time: 3.2))
        let stroke = try #require(canvas.strokes.first)
        #expect(stroke.points.first == CGPoint(x: 50 / width, y: 50 / (width * 0.75)))
        #expect(stroke.points.last == CGPoint(x: 56 / width, y: 50 / (width * 0.75)))
    }

    @Test("A quick drag can commit from its release position without an intermediate event")
    func releaseCompletesDrag() throws {
        let canvas = try makeCanvas(tool: .line)
        canvas.mouseDown(with: event(.leftMouseDown, x: 40, y: 40, time: 1))
        canvas.mouseUp(with: event(.leftMouseUp, x: 80, y: 70, time: 1.1))
        #expect(canvas.strokes.count == 1)
        #expect(canvas.strokes.first?.points.last == CGPoint(x: 0.2, y: 70.0 / 300))
    }

    @Test("Clicks preserve redo and double-click completion cannot restore a stray dot")
    func clicksPreserveHistory() throws {
        let canvas = try makeCanvas(tool: .pen)
        canvas.mouseDown(with: event(.leftMouseDown, x: 20, y: 20, time: 1))
        canvas.mouseDragged(with: event(.leftMouseDragged, x: 40, y: 30, time: 1.1))
        canvas.mouseUp(with: event(.leftMouseUp, x: 60, y: 40, time: 1.2))
        let original = canvas.strokes
        canvas.undo()
        canvas.mouseDown(with: event(.leftMouseDown, x: 100, y: 100, time: 3))
        canvas.mouseUp(with: event(.leftMouseUp, x: 100, y: 100, time: 3.05))
        canvas.redo()
        #expect(canvas.strokes == original)

        var completed = false
        canvas.onDoubleClick = { completed = true }
        canvas.mouseDown(with: event(.leftMouseDown, x: 150, y: 150, time: 5))
        canvas.mouseUp(with: event(.leftMouseUp, x: 151, y: 150, time: 5.05))
        canvas.mouseDown(with: event(.leftMouseDown, x: 150, y: 150, time: 5.2, clicks: 2))
        #expect(completed)
        #expect(canvas.strokes == original)
        canvas.redo()
        #expect(canvas.strokes == original)
    }

    @Test("A jittery double-click completes even when AppKit reports two single clicks")
    func doubleClickWithJitter() throws {
        let canvas = try makeCanvas(tool: .pen)
        var completions = 0
        canvas.onDoubleClick = { completions += 1 }
        canvas.mouseDown(with: event(.leftMouseDown, x: 50, y: 50, time: 1))
        canvas.mouseDragged(with: event(.leftMouseDragged, x: 51, y: 50, time: 1.05))
        canvas.mouseUp(with: event(.leftMouseUp, x: 51, y: 50, time: 1.1))
        canvas.mouseDown(with: event(.leftMouseDown, x: 51, y: 50, time: 1.2))
        canvas.mouseUp(with: event(.leftMouseUp, x: 51, y: 50, time: 1.25))
        #expect(completions == 1)
        #expect(canvas.strokes.isEmpty)
    }

    @Test("Area tools reject collapsed shapes while an intentional freehand loop survives")
    func collapsedGeometry() throws {
        for tool in [AnnotationTool.rectangle, .ellipse, .highlight, .redaction, .ocr] {
            let canvas = try makeCanvas(tool: tool)
            canvas.mouseDown(with: event(.leftMouseDown, x: 40, y: 40, time: 1))
            canvas.mouseDragged(with: event(.leftMouseDragged, x: 90, y: 41, time: 1.1))
            canvas.mouseUp(with: event(.leftMouseUp, x: 90, y: 41, time: 1.2))
            #expect(canvas.strokes.isEmpty)
        }
        for tool in [AnnotationTool.line, .arrow, .pen] {
            let canvas = try makeCanvas(tool: tool)
            canvas.mouseDown(with: event(.leftMouseDown, x: 40, y: 40, time: 1))
            canvas.mouseDragged(with: event(.leftMouseDragged, x: 90, y: 80, time: 1.1))
            canvas.mouseUp(with: event(.leftMouseUp, x: 40, y: 40, time: 1.2))
            #expect(canvas.strokes.count == (tool == .pen ? 1 : 0))
        }
    }

    @Test("Text and numbered markers still use explicit click placement")
    func clickToolsRemainAvailable() throws {
        let numbers = try makeCanvas(tool: .number)
        for (index, point) in [CGPoint(x: 40, y: 40), CGPoint(x: 200, y: 180)].enumerated() {
            numbers.mouseDown(with: event(.leftMouseDown, x: point.x, y: point.y, time: Double(index * 2 + 1)))
            numbers.mouseUp(with: event(.leftMouseUp, x: point.x, y: point.y, time: Double(index * 2 + 1) + 0.1))
        }
        #expect(numbers.strokes.map(\.text) == ["1", "2"])
        let original = numbers.strokes
        numbers.mouseDown(with: event(.leftMouseDown, x: 40, y: 40, time: 5))
        numbers.mouseDragged(with: event(.leftMouseDragged, x: 80, y: 80, time: 5.1))
        numbers.mouseUp(with: event(.leftMouseUp, x: 80, y: 80, time: 5.2))
        #expect(numbers.strokes.count == 2)
        #expect(numbers.strokes[0].points.first == CGPoint(x: 0.2, y: 80.0 / 300))
        numbers.undo()
        #expect(numbers.strokes == original)
        let text = try makeCanvas(tool: .text)
        text.mouseDown(with: event(.leftMouseDown, x: 40, y: 40, time: 1))
        text.mouseUp(with: event(.leftMouseUp, x: 40, y: 40, time: 1.1))
        let field = try #require(text.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "Deliberate annotation"
        text.commitPendingText()
        #expect(text.strokes.first?.text == "Deliberate annotation")
    }

    @Test("Changing tools or undoing cancels a pending press")
    func pendingPressIsCancelled() throws {
        let canvas = try makeCanvas(tool: .pen)
        canvas.mouseDown(with: event(.leftMouseDown, x: 40, y: 40, time: 1))
        canvas.tool = .line
        canvas.mouseUp(with: event(.leftMouseUp, x: 80, y: 80, time: 1.1))
        #expect(canvas.strokes.isEmpty)
        canvas.mouseDown(with: event(.leftMouseDown, x: 40, y: 40, time: 3))
        canvas.undo()
        canvas.mouseUp(with: event(.leftMouseUp, x: 80, y: 80, time: 3.1))
        #expect(canvas.strokes.isEmpty)
    }

    private func makeCanvas(tool: AnnotationTool, width: CGFloat = 400) throws -> AnnotationCanvasView {
        _ = NSApplication.shared
        let context = try #require(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let source = try #require(context.makeImage())
        let canvas = AnnotationCanvasView(sourceImage: source, logicalSize: CGSize(width: 400, height: 300), contentInset: 0)
        canvas.frame = CGRect(x: 0, y: 0, width: width, height: width * 0.75)
        canvas.tool = tool
        canvas.annotationColor = .red
        return canvas
    }

    private func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat, time: Double, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: time,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    private func renderedCanvas(_ canvas: AnnotationCanvasView) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(canvas.bounds.width), pixelsHigh: Int(canvas.bounds.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        canvas.draw(canvas.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
