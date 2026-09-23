import AppKit
import ImageIO

enum EditableDraftSettings {
    static let enabledKey = "historyEditableDraftsEnabled"
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }
}

enum CaptureFeatureError: LocalizedError {
    case invalidDocument
    case imageTooLarge
    case emptyDocument
    case recordingFailed
    case noVideoFrames

    var errorDescription: String? {
        switch self {
        case .invalidDocument: L10n.text("feature.error.invalidDocument")
        case .imageTooLarge: L10n.text("feature.error.imageTooLarge")
        case .emptyDocument: L10n.text("feature.error.emptyDocument")
        case .recordingFailed: L10n.text("feature.error.recordingFailed")
        case .noVideoFrames: L10n.text("feature.error.noVideoFrames")
        }
    }
}

struct AnnotationDraft: Codable, Sendable {
    static let maximumBytes = 128 * 1_024 * 1_024
    let version: Int
    let sourcePNG: Data
    let logicalSize: CGSize
    let strokes: [AnnotationStroke]
    let redactionWasFlattened: Bool

    init(source: CGImage, logicalSize: CGSize, strokes: [AnnotationStroke]) throws {
        let containsRedaction = strokes.contains { $0.tool == .mosaic || $0.tool == .redaction }
        // A redacted draft never keeps pixels or annotation text from before redaction.
        let storedImage = containsRedaction ? try AnnotationRenderer.render(image: source, strokes: strokes) : source
        guard let png = NSBitmapImageRep(cgImage: storedImage).representation(using: .png, properties: [:]) else {
            throw PinboardShotError.imageEncodingFailed
        }
        guard png.count <= Self.maximumBytes else { throw CaptureFeatureError.imageTooLarge }
        version = 1
        sourcePNG = png
        self.logicalSize = logicalSize
        self.strokes = containsRedaction ? [] : strokes
        redactionWasFlattened = containsRedaction
    }

    init(sourcePNG: Data, logicalSize: CGSize) throws {
        guard sourcePNG.count <= Self.maximumBytes else { throw CaptureFeatureError.imageTooLarge }
        version = 1
        self.sourcePNG = sourcePNG
        self.logicalSize = logicalSize
        strokes = []
        redactionWasFlattened = false
    }

    func sourceImage() throws -> CGImage {
        guard version == 1, sourcePNG.count <= Self.maximumBytes,
              logicalSize.width.isFinite, logicalSize.height.isFinite,
              logicalSize.width > 0, logicalSize.height > 0,
              strokes.count <= 10_000,
              strokes.allSatisfy({ stroke in
                  stroke.width.isFinite && stroke.width > 0 && stroke.points.count <= 100_000 &&
                  !stroke.points.isEmpty && stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) } &&
                  [stroke.color.red, stroke.color.green, stroke.color.blue, stroke.color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
              }),
              let source = CGImageSourceCreateWithData(sourcePNG as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 250_000_000 / height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureFeatureError.invalidDocument
        }
        return image
    }
}

enum RulerUnit: String, CaseIterable {
    case pixels, points
    var title: String { L10n.text("feature.ruler.unit.\(rawValue)") }
}

enum RulerMode: String, CaseIterable {
    case distance, horizontal, vertical
    var title: String { L10n.text("feature.ruler.mode.\(rawValue)") }
}

enum RulerMeasurement {
    static func label(from start: CGPoint, to end: CGPoint, size: CGSize, unit: RulerUnit) -> String {
        let dx = abs(end.x - start.x) * size.width
        let dy = abs(end.y - start.y) * size.height
        return String(format: "%.1f %@ · Δx %.1f · Δy %.1f", hypot(dx, dy), unit == .pixels ? "px" : "pt", dx, dy)
    }
}
