import AppKit
import BrowserCaptureBridge
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PinboardShot

@Suite("Browser coordinate capture import")
struct BrowserCaptureImportTests {
    private func document() throws -> CGImage {
        let width = 64, height = 420
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                bytes[index] = UInt8((x * 17 + y * 13) % 256)
                bytes[index + 1] = UInt8((x * 11 + y * 7) % 256)
                bytes[index + 2] = UInt8((x * 3 + y * 19) % 256)
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let data = NSMutableData(length: image.width * image.height * 4)!
        let context = try #require(CGContext(data: data.mutableBytes, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data as Data
    }

    private func tile(index: Int, row: Double) -> BrowserCaptureTile {
        BrowserCaptureTile(index: index, scrollY: row, viewportWidth: 32, viewportHeight: 60,
            documentHeight: 210, pngPixelWidth: 64, pngPixelHeight: 120,
            fileName: String(format: "tile-%06d.png", index))
    }

    @Test("Fractional CSS offsets and a clamped bottom produce every source row once")
    func fractionalOffsets() throws {
        let source = try document()
        let rows: [Double] = [0, 45.5, 91, 136.5, 150]
        let tiles = rows.enumerated().map { tile(index: $0.offset, row: $0.element) }
        let manifest = BrowserCaptureManifest(id: UUID(), capturedHeight: 210, tiles: tiles)
        let result = try BrowserCaptureImporter.compose(manifest: manifest) { tile in
            try png(try #require(source.cropping(to: CGRect(x: 0, y: tile.scrollY * 2, width: 64, height: 120))))
        }
        #expect(result.logicalSize == CGSize(width: 32, height: 210))
        #expect(try pixels(result.image) == pixels(source))
    }

    @Test("Later overlap replaces the document formerly obscured by a fixed footer")
    func footerOverlap() throws {
        let source = try document()
        let rows: [Double] = [0, 45.5, 91, 136.5, 150]
        let manifest = BrowserCaptureManifest(id: UUID(), capturedHeight: 210,
            tiles: rows.enumerated().map { tile(index: $0.offset, row: $0.element) })
        let result = try BrowserCaptureImporter.compose(manifest: manifest) { tile in
            let image = try #require(source.cropping(to: CGRect(x: 0, y: tile.scrollY * 2, width: 64, height: 120)))
            if tile.index != 0 { return try png(image) }
            let context = try #require(CGContext(data: nil, width: 64, height: 120, bitsPerComponent: 8,
                bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 120))
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 20))
            return try png(try #require(context.makeImage()))
        }
        #expect(try pixels(result.image) == pixels(source))
    }

    @Test("A coordinate gap is rejected instead of silently exporting missing content")
    func missingRows() throws {
        let source = try document()
        let manifest = BrowserCaptureManifest(id: UUID(), capturedHeight: 210,
            tiles: [tile(index: 0, row: 0), tile(index: 1, row: 100)])
        #expect(throws: BrowserCaptureImportError.self) {
            try BrowserCaptureImporter.compose(manifest: manifest) { tile in
                try png(try #require(source.cropping(to: CGRect(x: 0, y: tile.scrollY * 2, width: 64, height: 120))))
            }
        }
    }
}
