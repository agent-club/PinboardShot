import AppKit

/// Row ranges use the same top-down coordinates as CGImage.cropping(to:).
struct LongImageDocument {
    let source: CGImage
    private(set) var rows: [Range<Int>]
    private var undoStack: [[Range<Int>]] = []
    private var redoStack: [[Range<Int>]] = []

    init(image: CGImage) {
        source = image
        rows = [0..<image.height]
    }

    var height: Int { rows.reduce(0) { $0 + $1.count } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    @discardableResult
    mutating func removeRows(from start: Int, to end: Int) -> Bool {
        let lower = max(0, min(start, end))
        let upper = min(height, max(start, end))
        guard upper > lower, upper - lower < height else { return false }
        var offset = 0
        var kept: [Range<Int>] = []
        for range in rows {
            let localLower = max(0, min(range.count, lower - offset))
            let localUpper = max(0, min(range.count, upper - offset))
            if localUpper > localLower {
                if localLower > 0 { kept.append(range.lowerBound..<(range.lowerBound + localLower)) }
                if localUpper < range.count { kept.append((range.lowerBound + localUpper)..<range.upperBound) }
            } else {
                kept.append(range)
            }
            offset += range.count
        }
        undoStack.append(rows)
        rows = kept
        redoStack.removeAll()
        return true
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(rows)
        rows = previous
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(rows)
        rows = next
    }

    func render() throws -> CGImage {
        guard height > 0, source.width <= 150_000_000 / height,
              let context = CGContext(data: nil, width: source.width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: source.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureFeatureError.imageTooLarge
        }
        context.interpolationQuality = .none
        var top = 0
        for range in rows {
            guard let strip = source.cropping(to: CGRect(x: 0, y: range.lowerBound, width: source.width, height: range.count)) else {
                throw CaptureFeatureError.invalidDocument
            }
            context.draw(strip, in: CGRect(x: 0, y: height - top - range.count, width: source.width, height: range.count))
            top += range.count
        }
        guard let result = context.makeImage() else { throw PinboardShotError.imageEncodingFailed }
        return result
    }

    static func pageRanges(height: Int, pageHeight: Int) throws -> [Range<Int>] {
        guard height > 0, pageHeight > 0 else { throw CaptureFeatureError.invalidDocument }
        let count = (height - 1) / pageHeight + 1
        guard count <= 500 else { throw CaptureFeatureError.imageTooLarge }
        return stride(from: 0, to: height, by: pageHeight).map { $0..<($0 + min(pageHeight, height - $0)) }
    }

    func pages(pageHeight: Int) throws -> [CGImage] {
        let image = try render()
        return try Self.pageRanges(height: height, pageHeight: pageHeight).map { range in
            guard let page = image.cropping(to: CGRect(x: 0, y: range.lowerBound, width: image.width, height: range.count)) else {
                throw CaptureFeatureError.invalidDocument
            }
            return page
        }
    }
}
