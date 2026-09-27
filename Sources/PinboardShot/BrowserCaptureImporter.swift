import AppKit
import BrowserCaptureBridge
import ImageIO

struct BrowserImportedCapture: @unchecked Sendable {
    let image: CGImage
    let logicalSize: CGSize
}

enum BrowserCaptureImportError: LocalizedError {
    case invalidGeometry, missingRows, tooLarge, invalidImage

    var errorDescription: String? { L10n.text("browserExtension.importFailed") }
}

enum BrowserCaptureImporter {
    static func load(id: UUID, inbox: BrowserCaptureInbox = BrowserCaptureInbox()) throws -> BrowserImportedCapture {
        let manifest = try inbox.readManifest(id: id)
        // A completed capture is consumed once. Failed imports cannot leave page
        // pixels behind indefinitely or be replayed by another URL invocation.
        defer { try? inbox.cleanup(id: id) }
        return try compose(manifest: manifest) { tile in
            try inbox.readTile(id: id, index: tile.index, validatedBy: manifest)
        }
    }

    static func compose(manifest: BrowserCaptureManifest,
                        readTile: (BrowserCaptureTile) throws -> Data) throws -> BrowserImportedCapture {
        let tiles = manifest.tiles.sorted { $0.index < $1.index }
        guard let first = tiles.first, first.viewportWidth.isFinite, first.viewportWidth > 0,
              manifest.capturedHeight.isFinite, manifest.capturedHeight > 0,
              first.pngPixelWidth > 0 else { throw BrowserCaptureImportError.invalidGeometry }
        let scale = Double(first.pngPixelWidth) / first.viewportWidth
        let heightValue = (manifest.capturedHeight * scale).rounded()
        guard heightValue > 0, heightValue <= Double(Int.max / 4),
              Double(first.pngPixelWidth) * heightValue <= Double(ScrollCaptureAccumulator.maximumPixelCount) else {
            throw BrowserCaptureImportError.tooLarge
        }
        let width = first.pngPixelWidth
        let height = Int(heightValue)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw BrowserCaptureImportError.tooLarge
        }
        context.interpolationQuality = .none
        var coveredHeight = 0
        var previousTop = 0
        for (index, tile) in tiles.enumerated() {
            guard tile.index == index, tile.scrollY.isFinite, tile.scrollY >= 0,
                  tile.viewportHeight.isFinite, tile.viewportHeight > 0,
                  abs(tile.viewportWidth - first.viewportWidth) < 0.01,
                  tile.pngPixelWidth == width,
                  abs(Double(tile.pngPixelHeight) - tile.viewportHeight * scale) <= 1.1 else {
                throw BrowserCaptureImportError.invalidGeometry
            }
            let topValue = (tile.scrollY * scale).rounded()
            guard topValue <= Double(height), topValue >= Double(previousTop) else {
                throw BrowserCaptureImportError.invalidGeometry
            }
            let top = Int(topValue)
            guard top <= coveredHeight else { throw BrowserCaptureImportError.missingRows }
            let data = try readTile(tile)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  (properties[kCGImagePropertyPixelWidth] as? Int) == width,
                  (properties[kCGImagePropertyPixelHeight] as? Int) == tile.pngPixelHeight,
                  let image = CGImageSourceCreateImageAtIndex(source, 0,
                      [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                throw BrowserCaptureImportError.invalidImage
            }
            // Paint the real overlap again. Later tiles reveal document pixels
            // previously covered by sticky footers, without duplicating any rows.
            context.draw(image, in: CGRect(x: 0, y: height - top - image.height,
                                          width: width, height: image.height))
            coveredHeight = max(coveredHeight, top + image.height)
            previousTop = top
        }
        guard coveredHeight >= height, let image = context.makeImage() else {
            throw BrowserCaptureImportError.missingRows
        }
        return BrowserImportedCapture(image: image,
            logicalSize: CGSize(width: first.viewportWidth, height: manifest.capturedHeight))
    }
}
