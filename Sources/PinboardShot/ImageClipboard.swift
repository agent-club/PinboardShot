import AppKit

@MainActor
/// 用显式 PNG/TIFF 契约桥接 NSImage，避免 NSPasteboard 的隐式对象转换因图片来源不同而失效。
struct ImageClipboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func write(_ image: NSImage, pngData suppliedPNG: Data? = nil) -> Bool {
        guard let png = suppliedPNG ?? image.pngData else { return false }

        pasteboard.clearContents()
        let wrotePNG = pasteboard.setData(png, forType: .png)
        var wroteTIFF = false
        // 小图保留 TIFF 兼容性；高分辨率只发布 PNG，避免 8K TIFF 造成数百 MB 峰值内存。
        if let dimensions = image.pixelDimensions,
           ClipboardImagePolicy.shouldProvideTIFF(width: dimensions.width, height: dimensions.height),
           let tiff = image.tiffRepresentation {
            wroteTIFF = pasteboard.setData(tiff, forType: .tiff)
        }
        return wrotePNG || wroteTIFF
    }

    func read() -> NSImage? {
        if let png = pasteboard.data(forType: .png), let image = NSImage(data: png) {
            return image
        }
        if let tiff = pasteboard.data(forType: .tiff), let image = NSImage(data: tiff) {
            return image
        }
        return pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage
    }
}
