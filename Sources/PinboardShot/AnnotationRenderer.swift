import AppKit
import CoreText
import CoreImage
import CoreImage.CIFilterBuiltins

enum AnnotationRenderer {
    static func render(image: CGImage, strokes: [AnnotationStroke]) throws -> CGImage {
        guard !strokes.isEmpty else { return image }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw PinboardShotError.imageEncodingFailed }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        let pixelated = makePixelated(image)
        for stroke in strokes {
            draw(stroke, in: context, bounds: bounds, pixelated: pixelated)
        }
        guard let output = context.makeImage() else { throw PinboardShotError.imageEncodingFailed }
        return output
    }

    private static func draw(_ stroke: AnnotationStroke, in context: CGContext, bounds: CGRect, pixelated: CGImage?) {
        let points = stroke.points.map {
            CGPoint(x: $0.x * bounds.width, y: $0.y * bounds.height)
        }
        guard let first = points.first else { return }
        let width = max(1, stroke.width * min(bounds.width, bounds.height))
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(width)

        switch stroke.tool {
        case .mosaic:
            guard let pixelated else { break }
            context.beginPath()
            context.move(to: first)
            points.dropFirst().forEach { context.addLine(to: $0) }
            context.replacePathWithStrokedPath()
            context.clip()
            context.draw(pixelated, in: bounds)
        case .pen:
            context.setStrokeColor(stroke.color.cgColor)
            context.beginPath()
            context.move(to: first)
            points.dropFirst().forEach { context.addLine(to: $0) }
            context.strokePath()
        case .rectangle, .highlight, .ocr, .ellipse, .redaction:
            guard let last = points.last else { break }
            let rect = CGRect(
                x: min(first.x, last.x), y: min(first.y, last.y),
                width: abs(last.x - first.x), height: abs(last.y - first.y)
            )
            if stroke.tool == .highlight {
                context.setFillColor(stroke.color.nsColor.withAlphaComponent(0.28).cgColor)
                context.fill(rect)
            } else if stroke.tool == .ocr {
                drawTooltip(stroke, in: context, rect: rect, width: width)
            } else if stroke.tool == .ellipse {
                context.setStrokeColor(stroke.color.cgColor)
                context.strokeEllipse(in: rect)
            } else if stroke.tool == .redaction {
                guard let pixelated else { break }
                context.clip(to: rect)
                context.draw(pixelated, in: bounds)
            } else {
                context.setStrokeColor(stroke.color.cgColor)
                context.stroke(rect)
            }
        case .arrow:
            guard let last = points.last else { break }
            let path = points.count > 2
                ? AnnotationGeometry.gestureArrowPath(points: points, lineWidth: width)
                : AnnotationGeometry.taperedArrowPath(from: first, to: last, lineWidth: width)
            context.setFillColor(stroke.color.cgColor)
            context.addPath(path)
            context.fillPath()
        case .line:
            guard let last = points.last else { break }
            context.setStrokeColor(stroke.color.cgColor)
            context.move(to: first)
            context.addLine(to: last)
            context.strokePath()
        case .number:
            let radius = max(12, width)
            let circle = CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(stroke.color.cgColor)
            context.fillEllipse(in: circle)
            let label = stroke.text ?? "1"
            let font = CTFontCreateWithName(
                NSFont.systemFont(ofSize: radius, weight: .bold).fontName as CFString,
                radius,
                nil
            )
            let attributes = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: NSColor.white.cgColor
            ] as CFDictionary
            let attributed = CFAttributedStringCreate(nil, label as CFString, attributes)!
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetBoundsWithOptions(line, [])
            context.textPosition = CGPoint(x: first.x - bounds.width / 2, y: first.y - bounds.height / 2)
            CTLineDraw(line, context)
        case .text:
            guard let text = stroke.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { break }
            let font = CTFontCreateWithName(
                NSFont.systemFont(ofSize: max(8, width), weight: .medium).fontName as CFString,
                max(8, width),
                nil
            )
            let attributes = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: stroke.color.cgColor
            ] as CFDictionary
            let attributed = CFAttributedStringCreate(nil, text as CFString, attributes)!
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = first
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }

    private static func drawTooltip(_ stroke: AnnotationStroke, in context: CGContext, rect: CGRect, width: CGFloat) {
        guard rect.width >= 4, rect.height >= 4,
              let text = stroke.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        let radius = min(max(width, 5), 10)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.setFillColor(NSColor.textBackgroundColor.withAlphaComponent(0.90).cgColor)
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(stroke.color.nsColor.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(max(1, min(width / 3, 2)))
        context.addPath(path)
        context.strokePath()

        let padding = max(5, min(rect.width, rect.height) * 0.06)
        let textRect = rect.insetBy(dx: padding, dy: padding)
        guard textRect.width > 4, textRect.height > 4 else { return }
        let fontSize = max(9, min(16, textRect.height * 0.28))
        let font = CTFontCreateWithName(
            NSFont.systemFont(ofSize: fontSize, weight: .medium).fontName as CFString,
            fontSize,
            nil
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: NSColor.labelColor.cgColor,
            kCTParagraphStyleAttributeName: paragraph
        ] as CFDictionary
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes)!
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let textPath = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), textPath, nil)
        CTFrameDraw(frame, context)
    }

    static func makePixelated(_ image: CGImage) -> CGImage? {
        let filter = CIFilter.pixellate()
        filter.inputImage = CIImage(cgImage: image)
        filter.scale = 14
        return filter.outputImage.flatMap {
            CIContext(options: [.cacheIntermediates: false]).createCGImage(
                $0, from: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        }
    }
}
