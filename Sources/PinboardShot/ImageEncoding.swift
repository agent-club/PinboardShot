import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ClipboardImagePolicy {
    static let maximumEagerTIFFPixelCount = 8_294_400

    static func shouldProvideTIFF(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        return !overflow && pixelCount <= maximumEagerTIFFPixelCount
    }
}

extension NSImage {
    var pixelDimensions: (width: Int, height: Int)? {
        guard let image = cgImageForEncoding else { return nil }
        return (image.width, image.height)
    }

    var pngData: Data? {
        guard let image = cgImageForEncoding else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private var cgImageForEncoding: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
