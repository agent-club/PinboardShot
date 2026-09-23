import AppKit
import Darwin
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

    var mappedPNGData: Data? {
        guard let image = cgImageForEncoding else { return nil }
        var template = Array((NSTemporaryDirectory() + "PinboardShot-scroll-png.XXXXXX").utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { buffer in
            mkstemp(buffer.baseAddress!)
        }
        guard descriptor >= 0 else { return nil }
        close(descriptor)
        let path = String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
        defer { _ = unlink(path) }
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        // Mapping keeps the encoded document out of the heap after the temporary
        // path is unlinked; the returned Data retains the mapping until released.
        return try? Data(contentsOf: url, options: .alwaysMapped)
    }

    private var cgImageForEncoding: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
