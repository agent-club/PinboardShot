import AppKit
import CoreText

struct CaptureGuideStep: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var detail: String = ""
    let pngData: Data
}

struct CaptureGuide: Codable, Sendable {
    var version = 1
    var title = ""
    var steps: [CaptureGuideStep] = []

    func validate() throws {
        try validateStructure()
        for step in steps { _ = try CaptureDocumentExport.decodeImage(step.pngData) }
    }

    func validateStructure() throws {
        guard version == 1, steps.count <= 100, title.count <= 10_000,
              steps.allSatisfy({ $0.pngData.count <= 128 * 1_024 * 1_024 && $0.title.count <= 10_000 && $0.detail.count <= 100_000 }),
              steps.reduce(0, { $0 + $1.pngData.count }) <= 160 * 1_024 * 1_024,
              Set(steps.map(\.id)).count == steps.count else { throw CaptureFeatureError.invalidDocument }
    }

    mutating func move(id: UUID, by offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }), steps.indices.contains(index + offset) else { return }
        steps.swapAt(index, index + offset)
    }

    func markdown() -> String {
        var result = "# \(CaptureDocumentExport.escapeMarkdown(title))\n\n"
        for (index, step) in steps.enumerated() {
            result += "## \(index + 1). \(CaptureDocumentExport.escapeMarkdown(step.title))\n\n"
            result += CaptureDocumentExport.escapeMarkdown(step.detail) + "\n\n"
            result += "![\(index + 1)](images/step-\(String(format: "%03d", index + 1)).png)\n\n"
        }
        return result
    }
}

enum CaptureDocumentExport {
    static func decodeImage(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 150_000_000 / height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CaptureFeatureError.invalidDocument }
        return image
    }

    static func escapeMarkdown(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
        for token in ["\\", "`", "*", "_", "[", "]", "<", ">", "#", "|"] {
            result = result.replacingOccurrences(of: token, with: "\\" + token)
        }
        return result
    }

    /// Export into a new directory, staging all files before making the folder visible.
    static func directory(in parent: URL, name: String, write: (URL) throws -> Void) throws -> URL {
        let fm = FileManager.default
        let staging = parent.appendingPathComponent(".pinboardshot-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        try write(staging)
        var target = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = parent.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fm.moveItem(at: staging, to: target)
        return target
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw PinboardShotError.imageEncodingFailed }
        try data.write(to: url, options: .atomic)
    }

    static func imagePDF(_ pages: [CGImage]) throws -> Data {
        guard !pages.isEmpty else { throw CaptureFeatureError.emptyDocument }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw PinboardShotError.imageEncodingFailed }
        for image in pages {
            let scale = min(1, 595 / CGFloat(image.width))
            var rect = CGRect(x: 0, y: 0, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let box = Data(bytes: &rect, count: MemoryLayout<CGRect>.size) as CFData
            context.beginPDFPage([kCGPDFContextMediaBox as String: box] as CFDictionary)
            context.draw(image, in: rect)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    static func guidePDF(_ guide: CaptureGuide) throws -> Data {
        guard !guide.steps.isEmpty else { throw CaptureFeatureError.emptyDocument }
        try guide.validate()
        let data = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw PinboardShotError.imageEncodingFailed }
        for (index, step) in guide.steps.enumerated() {
            let image = try decodeImage(step.pngData)
            let text = "\(guide.title)\n\n\(index + 1). \(step.title)\n\n\(step.detail)"
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            var offset = 0
            repeat {
                context.beginPDFPage(nil)
                let textRect = CGRect(x: 36, y: 580, width: 523, height: 226)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), CGPath(rect: textRect, transform: nil), nil)
                context.textMatrix = .identity
                CTFrameDraw(frame, context)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { throw CaptureFeatureError.invalidDocument }
                offset += visible.length
                if offset >= attributed.length {
                    let scale = min(523 / CGFloat(image.width), 520 / CGFloat(image.height))
                    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                    context.draw(image, in: CGRect(x: 36 + (523 - size.width) / 2, y: 36 + (520 - size.height) / 2, width: size.width, height: size.height))
                }
                context.endPDFPage()
            } while offset < attributed.length
        }
        context.closePDF()
        return data as Data
    }
}
