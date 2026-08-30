import AppKit
import Testing
@testable import PinboardShot

private func comparisonTestImage(color: NSColor, width: Int, height: Int) throws -> NSImage {
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    return NSImage(cgImage: image, size: CGSize(width: width, height: height))
}

private func comparisonTestColor(_ image: NSImage, x: Int, y: Int) throws -> NSColor {
    let data = try #require(image.pngData)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    return try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
}

@Test("视觉对比并排导出保持顺序并支持交换 A/B")
func pinComparisonSideBySideExportPreservesOrder() throws {
    let red = try comparisonTestImage(color: .red, width: 12, height: 8)
    let blue = try comparisonTestImage(color: .blue, width: 8, height: 12)

    let normal = try #require(PinComparisonRenderer.render(
        first: red,
        second: blue,
        mode: .sideBySide
    ))
    #expect(normal.pixelDimensions?.width == 20)
    #expect(normal.pixelDimensions?.height == 12)
    let normalLeft = try comparisonTestColor(normal, x: 4, y: 6)
    let normalRight = try comparisonTestColor(normal, x: 16, y: 6)
    #expect(normalLeft.redComponent > 0.9)
    #expect(normalRight.blueComponent > 0.9)

    let swapped = try #require(PinComparisonRenderer.render(
        first: red,
        second: blue,
        mode: .sideBySide,
        isSwapped: true
    ))
    let swappedLeft = try comparisonTestColor(swapped, x: 4, y: 6)
    let swappedRight = try comparisonTestColor(swapped, x: 16, y: 6)
    #expect(swappedLeft.blueComponent > 0.9)
    #expect(swappedRight.redComponent > 0.9)
}

@Test("视觉差异导出把相同像素渲染为黑色")
func pinComparisonDifferenceExportUsesDifferenceBlend() throws {
    let image = try comparisonTestImage(color: .red, width: 10, height: 10)
    let rendered = try #require(PinComparisonRenderer.render(
        first: image,
        second: image,
        mode: .overlay
    ))
    let center = try comparisonTestColor(rendered, x: 5, y: 5)
    #expect(center.redComponent < 0.05)
    #expect(center.greenComponent < 0.05)
    #expect(center.blueComponent < 0.05)
}

@Test("视觉混合导出应用当前 B 图不透明度")
func pinComparisonBlendExportUsesOpacity() throws {
    let red = try comparisonTestImage(color: .red, width: 10, height: 10)
    let blue = try comparisonTestImage(color: .blue, width: 10, height: 10)
    let transparentB = try #require(PinComparisonRenderer.render(
        first: red,
        second: blue,
        mode: .blend,
        blendOpacity: 0
    ))
    let transparentColor = try comparisonTestColor(transparentB, x: 5, y: 5)
    #expect(transparentColor.redComponent > 0.9)
    #expect(transparentColor.blueComponent < 0.05)

    let opaqueB = try #require(PinComparisonRenderer.render(
        first: red,
        second: blue,
        mode: .blend,
        blendOpacity: 1
    ))
    let opaqueColor = try comparisonTestColor(opaqueB, x: 5, y: 5)
    #expect(opaqueColor.redComponent < 0.05)
    #expect(opaqueColor.blueComponent > 0.9)

    let halfB = try #require(PinComparisonRenderer.render(
        first: red,
        second: blue,
        mode: .blend,
        blendOpacity: 0.5
    ))
    let halfColor = try comparisonTestColor(halfB, x: 5, y: 5)
    #expect(halfColor.redComponent > 0.45)
    #expect(halfColor.blueComponent > 0.45)
    #expect(abs(halfColor.redComponent - halfColor.blueComponent) < 0.05)
}

@Test("视觉对比导出限制超宽位图的内存边界")
func pinComparisonExportConstrainsOversizedCanvas() throws {
    let first = try comparisonTestImage(color: .red, width: 9_000, height: 1)
    let second = try comparisonTestImage(color: .blue, width: 9_000, height: 1)
    let rendered = try #require(PinComparisonRenderer.render(
        first: first,
        second: second,
        mode: .sideBySide
    ))
    let dimensions = try #require(rendered.pixelDimensions)
    #expect(dimensions.width <= PinComparisonRenderer.maximumDimension)
    #expect(dimensions.width * dimensions.height <= PinComparisonRenderer.maximumPixelCount)
}

@Test("第二张新贴图只触发一次视觉对比发现提示")
func pinComparisonDiscoveryHintIsShownOnce() {
    let suiteName = "PinComparisonDiscoveryPolicyTests-\(UUID())"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(!PinComparisonDiscoveryPolicy.shouldShow(pinCount: 1, defaults: defaults))
    #expect(PinComparisonDiscoveryPolicy.shouldShow(pinCount: 2, defaults: defaults))
    #expect(!PinComparisonDiscoveryPolicy.shouldShow(pinCount: 3, defaults: defaults))

    PinComparisonDiscoveryPolicy.markShown(defaults: defaults)
    #expect(!PinComparisonDiscoveryPolicy.shouldShow(pinCount: 2, defaults: defaults))
}
