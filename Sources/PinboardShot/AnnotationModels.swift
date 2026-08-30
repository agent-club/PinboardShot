import AppKit

enum AnnotationTool: String, CaseIterable, Identifiable, Sendable {
    case mosaic
    case pen
    case rectangle
    case highlight
    case ocr
    case arrow
    case text
    case ellipse
    case line
    case number
    case redaction

    static let selectionTools: [AnnotationTool] = [
        .mosaic, .pen, .rectangle, .highlight, .ocr, .arrow, .text
    ]

    static let editorTools: [AnnotationTool] = [
        .mosaic, .pen, .rectangle, .highlight, .ocr, .arrow, .text, .ellipse, .line, .number
    ]

    var id: String { rawValue }

    var titleKey: String { "annotation.tool.\(rawValue)" }
    var symbolName: String {
        switch self {
        case .mosaic: "square.grid.3x3.fill"
        case .pen: "pencil.tip"
        case .rectangle: "rectangle"
        case .highlight: "highlighter"
        case .ocr: "text.viewfinder"
        case .arrow: "arrow.up.right"
        case .text: "character.cursor.ibeam"
        case .ellipse: "oval"
        case .line: "line.diagonal"
        case .number: "1.circle"
        case .redaction: "eye.slash.fill"
        }
    }
}

enum AnnotationStyleSettings {
    static let brushPixelWidthDefaultsKey = "annotation.brushPixelWidth"
    static let defaultBrushPixelWidth: CGFloat = 2
    static let minimumBrushPixelWidth: CGFloat = 2
    static let maximumBrushPixelWidth: CGFloat = 36

    static func brushPixelWidthKey(for tool: AnnotationTool) -> String {
        "\(brushPixelWidthDefaultsKey).\(tool.rawValue)"
    }

    static func defaultBrushPixelWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .mosaic: 14
        case .pen: 4
        case .rectangle: 3
        case .highlight: 12
        case .ocr: 2
        case .arrow: 4
        case .text: 8
        case .ellipse, .line: 3
        case .number: 16
        case .redaction: 2
        }
    }

    static func brushPixelWidth(defaults: UserDefaults = .standard) -> CGFloat {
        guard defaults.object(forKey: brushPixelWidthDefaultsKey) != nil else {
            return defaultBrushPixelWidth
        }
        let value = CGFloat(defaults.double(forKey: brushPixelWidthDefaultsKey))
        guard value.isFinite else { return defaultBrushPixelWidth }
        return clampedBrushPixelWidth(value)
    }

    static func brushPixelWidth(for tool: AnnotationTool, defaults: UserDefaults = .standard) -> CGFloat {
        let key = brushPixelWidthKey(for: tool)
        guard defaults.object(forKey: key) != nil else {
            if tool == .pen, defaults.object(forKey: brushPixelWidthDefaultsKey) != nil {
                return brushPixelWidth(defaults: defaults)
            }
            return defaultBrushPixelWidth(for: tool)
        }
        let value = CGFloat(defaults.double(forKey: key))
        guard value.isFinite else { return defaultBrushPixelWidth(for: tool) }
        return clampedBrushPixelWidth(value)
    }

    static func setBrushPixelWidth(_ width: CGFloat, defaults: UserDefaults = .standard) {
        defaults.set(Double(clampedBrushPixelWidth(width)), forKey: brushPixelWidthDefaultsKey)
    }

    static func setBrushPixelWidth(
        _ width: CGFloat,
        for tool: AnnotationTool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(Double(clampedBrushPixelWidth(width)), forKey: brushPixelWidthKey(for: tool))
    }

    static func clampedBrushPixelWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumBrushPixelWidth), maximumBrushPixelWidth)
    }
}

struct AnnotationColor: Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ color: NSColor) {
        let value = color.usingColorSpace(.deviceRGB) ?? .systemRed
        red = value.redComponent
        green = value.greenComponent
        blue = value.blueComponent
        alpha = value.alphaComponent
    }

    var nsColor: NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
    var cgColor: CGColor { nsColor.cgColor }
}

struct AnnotationStroke: Equatable, Sendable {
    let tool: AnnotationTool
    var points: [CGPoint]
    var color: AnnotationColor
    var width: CGFloat
    var text: String?

    init(
        tool: AnnotationTool,
        points: [CGPoint],
        color: AnnotationColor,
        width: CGFloat,
        text: String? = nil
    ) {
        self.tool = tool
        self.points = points
        self.color = color
        self.width = width
        self.text = text
    }
}

struct AnnotationHistory: Sendable {
    private(set) var strokes: [AnnotationStroke] = []
    // 保存完整快照，让文字替换、改色和改字号与新增笔迹使用同一套可撤销语义。
    private var undoStack: [[AnnotationStroke]] = []
    private var redoStack: [[AnnotationStroke]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func append(_ stroke: AnnotationStroke) {
        recordCurrentState()
        strokes.append(stroke)
    }

    mutating func replace(at index: Int, with stroke: AnnotationStroke) {
        guard strokes.indices.contains(index), strokes[index] != stroke else { return }
        recordCurrentState()
        strokes[index] = stroke
    }

    mutating func remove(at index: Int) {
        guard strokes.indices.contains(index) else { return }
        recordCurrentState()
        strokes.remove(at: index)
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }

    mutating func clear() {
        guard !strokes.isEmpty else { return }
        recordCurrentState()
        strokes.removeAll()
    }

    private mutating func recordCurrentState() {
        undoStack.append(strokes)
        redoStack.removeAll()
    }
}

enum AnnotationGeometry {
    static func arrowHead(from start: CGPoint, to end: CGPoint, length: CGFloat) -> (
        CGPoint, CGPoint
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let spread = CGFloat.pi / 6
        return (
            CGPoint(
                x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread)),
            CGPoint(
                x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        )
    }
}
