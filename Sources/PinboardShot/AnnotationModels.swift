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
        .rectangle, .arrow, .pen, .mosaic, .highlight, .text, .ocr
    ]

    static let editorTools: [AnnotationTool] = [
        .mosaic, .pen, .rectangle, .highlight, .ocr, .arrow, .text, .ellipse, .line, .number
    ]

    var id: String { rawValue }

    var titleKey: String { "annotation.tool.\(rawValue)" }
    var symbolName: String {
        switch self {
        case .mosaic: "square.grid.3x3"
        case .pen: "pencil"
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

enum AnnotationArrowMode: Int, CaseIterable, Sendable {
    case straight
    case freehand

    var titleKey: String {
        switch self {
        case .straight: "annotation.arrow.mode.straight"
        case .freehand: "annotation.arrow.mode.freehand"
        }
    }

    var symbolName: String {
        switch self {
        case .straight: "arrow.up.right"
        case .freehand: "scribble.variable"
        }
    }

    static func mode(for stroke: AnnotationStroke) -> AnnotationArrowMode {
        stroke.tool == .arrow && stroke.points.count > 2 ? .freehand : .straight
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
    static func smoothedGesturePoints(
        _ rawPoints: [CGPoint],
        minimumDistance: CGFloat = 0.0015
    ) -> [CGPoint] {
        guard rawPoints.count > 2 else { return rawPoints }
        var filtered: [CGPoint] = []
        filtered.reserveCapacity(rawPoints.count)
        for point in rawPoints {
            guard let last = filtered.last else {
                filtered.append(point)
                continue
            }
            if hypot(point.x - last.x, point.y - last.y) >= minimumDistance {
                filtered.append(point)
            }
        }
        if let last = rawPoints.last, filtered.last != last {
            filtered.append(last)
        }
        guard filtered.count > 2 else { return filtered }

        var smoothed = filtered
        for _ in 0..<2 {
            var next = smoothed
            for index in 1..<(smoothed.count - 1) {
                let previous = smoothed[index - 1]
                let current = smoothed[index]
                let following = smoothed[index + 1]
                next[index] = CGPoint(
                    x: previous.x * 0.2 + current.x * 0.6 + following.x * 0.2,
                    y: previous.y * 0.2 + current.y * 0.6 + following.y * 0.2
                )
            }
            smoothed = next
        }
        smoothed[0] = filtered[0]
        smoothed[smoothed.count - 1] = filtered[filtered.count - 1]
        return smoothed
    }

    static func arrowHeadLength(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth: CGFloat
    ) -> CGFloat {
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > 0 else { return 0 }
        let preferredLength = min(max(lineWidth * 3.8, 14), 28)
        let readableLength = max(lineWidth * 1.8, distance * 0.34)
        return min(min(preferredLength, readableLength), distance * 0.8)
    }

    static func arrowHead(from start: CGPoint, to end: CGPoint, length: CGFloat) -> (
        CGPoint, CGPoint
    ) {
        let head = curvedArrowHead(from: start, to: end, length: length)
        return (head.first, head.second)
    }

    static func curvedArrowHead(from start: CGPoint, to end: CGPoint, length: CGFloat) -> (
        first: CGPoint,
        firstControl1: CGPoint,
        firstControl2: CGPoint,
        secondControl1: CGPoint,
        secondControl2: CGPoint,
        second: CGPoint
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let spread = CGFloat.pi / 7.2
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let first = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let second = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )
        let firstControl1 = CGPoint(
            x: first.x + (end.x - first.x) * 0.42 + normal.x * length * 0.12,
            y: first.y + (end.y - first.y) * 0.42 + normal.y * length * 0.12
        )
        let firstControl2 = CGPoint(
            x: end.x - direction.x * length * 0.18 + normal.x * length * 0.05,
            y: end.y - direction.y * length * 0.18 + normal.y * length * 0.05
        )
        let secondControl1 = CGPoint(
            x: second.x + (end.x - second.x) * 0.42 - normal.x * length * 0.12,
            y: second.y + (end.y - second.y) * 0.42 - normal.y * length * 0.12
        )
        let secondControl2 = CGPoint(
            x: end.x - direction.x * length * 0.18 - normal.x * length * 0.05,
            y: end.y - direction.y * length * 0.18 - normal.y * length * 0.05
        )
        return (
            first,
            firstControl1,
            firstControl2,
            secondControl1,
            secondControl2,
            second
        )
    }

    static func taperedArrowPath(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth rawLineWidth: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        let lineWidth = max(1, rawLineWidth)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > max(2, lineWidth * 3) else {
            let diameter = max(2, lineWidth)
            path.addEllipse(in: CGRect(
                x: end.x - diameter / 2,
                y: end.y - diameter / 2,
                width: diameter,
                height: diameter
            ))
            return path
        }

        let direction = CGPoint(x: dx / distance, y: dy / distance)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let headLength = arrowHeadLength(from: start, to: end, lineWidth: lineWidth)
        let tailHalfWidth = max(1.2, lineWidth * 0.38)
        let shaftHeadHalfWidth = max(tailHalfWidth * 1.4, lineWidth * 0.72)
        let headHalfWidth = max(lineWidth * 1.35, headLength * 0.52)
        let neckCenter = offset(end, along: direction, by: -headLength * 0.58)
        let wingCenter = offset(end, along: direction, by: -headLength)
        let tailTop = offset(start, along: normal, by: tailHalfWidth)
        let tailBottom = offset(start, along: normal, by: -tailHalfWidth)
        let neckTop = offset(neckCenter, along: normal, by: shaftHeadHalfWidth)
        let neckBottom = offset(neckCenter, along: normal, by: -shaftHeadHalfWidth)
        let wingTop = offset(wingCenter, along: normal, by: headHalfWidth)
        let wingBottom = offset(wingCenter, along: normal, by: -headHalfWidth)

        path.move(to: tailTop)
        path.addCurve(
            to: neckTop,
            control1: offset(
                offset(start, along: direction, by: distance * 0.32),
                along: normal,
                by: tailHalfWidth * 1.08
            ),
            control2: offset(
                offset(neckCenter, along: direction, by: -distance * 0.18),
                along: normal,
                by: shaftHeadHalfWidth * 0.92
            )
        )
        path.addCurve(
            to: wingTop,
            control1: offset(
                offset(neckTop, along: direction, by: -headLength * 0.10),
                along: normal,
                by: headHalfWidth * 0.18
            ),
            control2: offset(
                offset(wingTop, along: direction, by: headLength * 0.12),
                along: normal,
                by: -headHalfWidth * 0.08
            )
        )
        path.addCurve(
            to: end,
            control1: offset(
                offset(wingTop, along: direction, by: headLength * 0.42),
                along: normal,
                by: headHalfWidth * 0.04
            ),
            control2: offset(
                offset(end, along: direction, by: -headLength * 0.18),
                along: normal,
                by: headHalfWidth * 0.22
            )
        )
        path.addCurve(
            to: wingBottom,
            control1: offset(
                offset(end, along: direction, by: -headLength * 0.18),
                along: normal,
                by: -headHalfWidth * 0.22
            ),
            control2: offset(
                offset(wingBottom, along: direction, by: headLength * 0.42),
                along: normal,
                by: -headHalfWidth * 0.04
            )
        )
        path.addCurve(
            to: neckBottom,
            control1: offset(
                offset(wingBottom, along: direction, by: headLength * 0.12),
                along: normal,
                by: headHalfWidth * 0.08
            ),
            control2: offset(
                offset(neckBottom, along: direction, by: -headLength * 0.10),
                along: normal,
                by: -headHalfWidth * 0.18
            )
        )
        path.addCurve(
            to: tailBottom,
            control1: offset(
                offset(neckCenter, along: direction, by: -distance * 0.18),
                along: normal,
                by: -shaftHeadHalfWidth * 0.92
            ),
            control2: offset(
                offset(start, along: direction, by: distance * 0.32),
                along: normal,
                by: -tailHalfWidth * 1.08
            )
        )
        path.addCurve(
            to: tailTop,
            control1: offset(tailBottom, along: direction, by: -tailHalfWidth * 1.2),
            control2: offset(tailTop, along: direction, by: -tailHalfWidth * 1.2)
        )
        path.closeSubpath()
        return path
    }

    static func gestureArrowPath(
        points rawPoints: [CGPoint],
        lineWidth rawLineWidth: CGFloat
    ) -> CGPath {
        let points = compactDisplayPoints(rawPoints)
        guard let first = points.first, let last = points.last else {
            return CGMutablePath()
        }
        guard points.count > 2 else {
            return taperedArrowPath(from: first, to: last, lineWidth: rawLineWidth)
        }

        let lineWidth = max(1, rawLineWidth)
        let lengths = cumulativeLengths(for: points)
        guard let totalLength = lengths.last,
              totalLength > max(2, lineWidth * 3) else {
            return taperedArrowPath(from: first, to: last, lineWidth: lineWidth)
        }

        let preferredHeadLength = min(max(lineWidth * 4.4, 20), 42)
        let headLength = min(preferredHeadLength, totalLength * 0.38)
        let wingDistance = min(headLength * 0.92, totalLength * 0.34)
        let neckDistance = min(headLength * 0.72, wingDistance * 0.80)
        let wingCenter = point(along: points, lengths: lengths, distanceFromEnd: wingDistance)
        let neckCenter = point(along: points, lengths: lengths, distanceFromEnd: neckDistance)
        let tangentPoint = point(
            along: points,
            lengths: lengths,
            distanceFromEnd: min(max(6, lineWidth * 1.5), max(6, neckDistance))
        )
        let shaftPoints = clippedPolyline(
            points,
            lengths: lengths,
            endingAtDistance: max(totalLength - wingDistance, 0),
            endPoint: neckCenter
        )
        guard shaftPoints.count >= 2 else {
            return taperedArrowPath(from: first, to: last, lineWidth: lineWidth)
        }

        let finalDirection = unitVector(from: tangentPoint, to: last)
        let finalNormal = CGPoint(x: -finalDirection.y, y: finalDirection.x)
        let smoothStep: (CGFloat) -> CGFloat = { value in
            let clamped = max(0, min(1, value))
            return clamped * clamped * (3 - 2 * clamped)
        }

        let tailHalfWidth = max(1.5, lineWidth * 0.48)
        let shaftHeadHalfWidth = max(tailHalfWidth * 1.35, lineWidth * 0.72)
        let headHalfWidth = max(
            shaftHeadHalfWidth * 2.65,
            lineWidth * 1.95,
            headLength * 0.50
        )
        let asymmetry = min(lineWidth * 0.12, 2.5)

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        left.reserveCapacity(shaftPoints.count)
        right.reserveCapacity(shaftPoints.count)
        let shaftLengths = cumulativeLengths(for: shaftPoints)
        let shaftLength = max(0.001, shaftLengths.last ?? 0)
        for index in shaftPoints.indices {
            let progress = shaftLengths[index] / shaftLength
            let easedProgress = smoothStep(progress)
            let halfWidth = tailHalfWidth
                + (shaftHeadHalfWidth - tailHalfWidth) * easedProgress
            let normal = averagedNormal(at: index, points: shaftPoints)
            left.append(offset(shaftPoints[index], along: normal, by: halfWidth))
            right.append(offset(shaftPoints[index], along: normal, by: -halfWidth))
        }

        let wingTop = offset(wingCenter, along: finalNormal, by: headHalfWidth + asymmetry)
        let wingBottom = offset(wingCenter, along: finalNormal, by: -(headHalfWidth - asymmetry * 0.45))
        let neckTop = left.last ?? offset(neckCenter, along: finalNormal, by: shaftHeadHalfWidth + 0.3)
        let neckBottom = right.last ?? offset(neckCenter, along: finalNormal, by: -(shaftHeadHalfWidth - 0.3))
        let path = CGMutablePath()
        path.move(to: left[0])
        addSmoothRibbonEdge(left, to: path)
        path.addCurve(
            to: wingTop,
            control1: offset(
                offset(neckTop, along: finalDirection, by: -headLength * 0.10),
                along: finalNormal,
                by: headLength * 0.03
            ),
            control2: offset(
                offset(wingTop, along: finalDirection, by: headLength * 0.12),
                along: finalNormal,
                by: -headLength * 0.03
            )
        )
        path.addCurve(
            to: last,
            control1: offset(wingTop, along: finalDirection, by: headLength * 0.50),
            control2: offset(
                offset(last, along: finalDirection, by: -headLength * 0.20),
                along: finalNormal,
                by: headLength * 0.15
            )
        )
        path.addCurve(
            to: wingBottom,
            control1: offset(
                offset(last, along: finalDirection, by: -headLength * 0.22),
                along: finalNormal,
                by: -headLength * 0.10
            ),
            control2: offset(wingBottom, along: finalDirection, by: headLength * 0.48)
        )
        path.addCurve(
            to: right[right.count - 1],
            control1: offset(wingBottom, along: finalDirection, by: headLength * 0.12),
            control2: offset(neckBottom, along: finalDirection, by: -headLength * 0.10)
        )
        addSmoothRibbonEdge(Array(right.reversed()), to: path)
        let startDirection = unitVector(from: shaftPoints[0], to: shaftPoints[1])
        path.addQuadCurve(
            to: left[0],
            control: offset(shaftPoints[0], along: startDirection, by: -tailHalfWidth * 1.25)
        )
        path.closeSubpath()
        return path
    }

    private static func addSmoothRibbonEdge(
        _ points: [CGPoint],
        to path: CGMutablePath
    ) {
        guard points.count > 1 else { return }
        for index in 1..<points.count {
            let previous = points[max(0, index - 2)]
            let start = points[index - 1]
            let end = points[index]
            let following = points[min(points.count - 1, index + 1)]
            let control1 = CGPoint(
                x: start.x + (end.x - previous.x) / 6,
                y: start.y + (end.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: end.x - (following.x - start.x) / 6,
                y: end.y - (following.y - start.y) / 6
            )
            path.addCurve(to: end, control1: control1, control2: control2)
        }
    }

    private static func compactDisplayPoints(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            guard let last = result.last else {
                result.append(point)
                continue
            }
            if hypot(point.x - last.x, point.y - last.y) >= 0.6 {
                result.append(point)
            }
        }
        if let last = points.last, result.last != last { result.append(last) }
        return result
    }

    private static func cumulativeLengths(for points: [CGPoint]) -> [CGFloat] {
        var result: [CGFloat] = [0]
        result.reserveCapacity(points.count)
        for index in 1..<points.count {
            result.append(result[index - 1] + hypot(
                points[index].x - points[index - 1].x,
                points[index].y - points[index - 1].y
            ))
        }
        return result
    }

    private static func point(
        along points: [CGPoint],
        lengths: [CGFloat],
        distanceFromEnd: CGFloat
    ) -> CGPoint {
        let target = max(0, (lengths.last ?? 0) - distanceFromEnd)
        for index in 1..<lengths.count where lengths[index] >= target {
            let segmentLength = max(0.0001, lengths[index] - lengths[index - 1])
            let progress = (target - lengths[index - 1]) / segmentLength
            return CGPoint(
                x: points[index - 1].x + (points[index].x - points[index - 1].x) * progress,
                y: points[index - 1].y + (points[index].y - points[index - 1].y) * progress
            )
        }
        return points.last ?? .zero
    }

    private static func clippedPolyline(
        _ points: [CGPoint],
        lengths: [CGFloat],
        endingAtDistance target: CGFloat,
        endPoint: CGPoint
    ) -> [CGPoint] {
        var result: [CGPoint] = []
        for (index, point) in points.enumerated() where lengths[index] < target {
            result.append(point)
        }
        if result.isEmpty { result.append(points[0]) }
        if result.last != endPoint { result.append(endPoint) }
        return result
    }

    private static func averagedNormal(at index: Int, points: [CGPoint]) -> CGPoint {
        let incoming = index > 0
            ? unitVector(from: points[index - 1], to: points[index])
            : unitVector(from: points[index], to: points[min(index + 1, points.count - 1)])
        let outgoing = index + 1 < points.count
            ? unitVector(from: points[index], to: points[index + 1])
            : incoming
        let combined = CGPoint(x: incoming.x + outgoing.x, y: incoming.y + outgoing.y)
        let length = hypot(combined.x, combined.y)
        let tangent = length > 0.001
            ? CGPoint(x: combined.x / length, y: combined.y / length)
            : outgoing
        return CGPoint(x: -tangent.y, y: tangent.x)
    }

    private static func unitVector(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: dx / length, y: dy / length)
    }

    private static func offset(_ point: CGPoint, along vector: CGPoint, by distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + vector.x * distance, y: point.y + vector.y * distance)
    }
}
