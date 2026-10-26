import AppKit
import Foundation

private let canvasSize = NSSize(width: 720, height: 480)
private let pixelScale: CGFloat = 2

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

private func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, width: CGFloat = 1) {
    let converted = NSRect(x: rect.minX, y: canvasSize.height - rect.maxY, width: rect.width, height: rect.height)
    let path = NSBezierPath(roundedRect: converted, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = width
        path.stroke()
    }
}

private func drawText(_ value: String, at point: NSPoint, font: NSFont, color textColor: NSColor) {
    let drawingPoint = NSPoint(x: point.x, y: canvasSize.height - point.y - font.pointSize)
    (value as NSString).draw(at: drawingPoint, withAttributes: [
        .font: font,
        .foregroundColor: textColor,
        .kern: 0
    ])
}

private func drawArrow() {
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = 2.5
    path.move(to: NSPoint(x: 322, y: canvasSize.height - 248))
    path.line(to: NSPoint(x: 398, y: canvasSize.height - 248))
    path.move(to: NSPoint(x: 388, y: canvasSize.height - 240))
    path.line(to: NSPoint(x: 398, y: canvasSize.height - 248))
    path.line(to: NSPoint(x: 388, y: canvasSize.height - 256))
    color(0.38, 0.27, 0.73).setStroke()
    path.stroke()
}

private func drawBackground() {
    color(0.976, 0.969, 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

    let wash = NSBezierPath()
    wash.move(to: NSPoint(x: 0, y: 0))
    wash.line(to: NSPoint(x: 720, y: 0))
    wash.line(to: NSPoint(x: 720, y: 130))
    wash.curve(to: NSPoint(x: 450, y: 54), controlPoint1: NSPoint(x: 627, y: 106), controlPoint2: NSPoint(x: 544, y: 42))
    wash.curve(to: NSPoint(x: 0, y: 95), controlPoint1: NSPoint(x: 310, y: 79), controlPoint2: NSPoint(x: 141, y: 119))
    wash.close()
    color(0.925, 0.9, 0.99, 0.5).setFill()
    wash.fill()

    let glow = NSBezierPath(ovalIn: NSRect(x: 105, y: canvasSize.height - 311, width: 170, height: 112))
    color(0.86, 0.8, 0.98, 0.22).setFill()
    glow.fill()
    let secondGlow = NSBezierPath(ovalIn: NSRect(x: 445, y: canvasSize.height - 311, width: 170, height: 112))
    color(0.86, 0.8, 0.98, 0.22).setFill()
    secondGlow.fill()

    // Faint layered lines echo stacked captures while staying outside the Finder icon labels.
    for index in 0..<4 {
        let offset = CGFloat(index) * 5
        let card = NSBezierPath(roundedRect: NSRect(x: 90 + offset, y: 205 + offset, width: 128, height: 72), xRadius: 12, yRadius: 12)
        color(0.61, 0.51, 0.82, 0.035 + CGFloat(index) * 0.012).setStroke()
        card.lineWidth = 1
        card.stroke()
    }
    for index in 0..<4 {
        let offset = CGFloat(index) * 5
        let card = NSBezierPath(roundedRect: NSRect(x: 502 + offset, y: 205 + offset, width: 128, height: 72), xRadius: 12, yRadius: 12)
        color(0.61, 0.51, 0.82, 0.035 + CGFloat(index) * 0.012).setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}

private func makeImage() -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width * pixelScale),
        pixelsHigh: Int(canvasSize.height * pixelScale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = canvasSize
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    drawBackground()

    let ink = color(0.18, 0.13, 0.31)
    let muted = color(0.39, 0.34, 0.48)
    let violet = color(0.38, 0.27, 0.73)

    drawText("PINBOARDSHOT", at: NSPoint(x: 48, y: 28), font: .systemFont(ofSize: 10, weight: .bold), color: violet)
    drawText("拖一下，就装好了", at: NSPoint(x: 48, y: 53), font: .systemFont(ofSize: 28, weight: .semibold), color: ink)
    drawText("Drag PinboardShot into Applications to install.", at: NSPoint(x: 49, y: 91), font: .systemFont(ofSize: 14, weight: .regular), color: muted)

    roundedRect(NSRect(x: 128, y: 143, width: 124, height: 25), radius: 12.5, fill: color(0.93, 0.91, 0.98))
    roundedRect(NSRect(x: 468, y: 143, width: 124, height: 25), radius: 12.5, fill: color(0.93, 0.91, 0.98))
    drawText("01   拖动应用", at: NSPoint(x: 149, y: 149), font: .systemFont(ofSize: 11, weight: .semibold), color: violet)
    drawText("02   放入应用程序", at: NSPoint(x: 474, y: 149), font: .systemFont(ofSize: 10.5, weight: .semibold), color: violet)

    drawArrow()

    let separator = NSBezierPath()
    separator.move(to: NSPoint(x: 48, y: canvasSize.height - 360))
    separator.line(to: NSPoint(x: 672, y: canvasSize.height - 360))
    separator.lineWidth = 1
    color(0.78, 0.73, 0.86, 0.7).setStroke()
    separator.stroke()

    drawText("安装完成后，从「应用程序」打开，在顶部菜单栏找到 PinboardShot。", at: NSPoint(x: 48, y: 381), font: .systemFont(ofSize: 13, weight: .medium), color: ink)
    drawText("Open from Applications, then find PinboardShot in the menu bar.", at: NSPoint(x: 48, y: 406), font: .systemFont(ofSize: 11.5, weight: .regular), color: muted)

    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/dmg-background.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = makeImage().representation(using: .png, properties: [:]) else {
        fputs("Could not encode the DMG background PNG.\n", stderr)
        exit(1)
    }
    try data.write(to: outputURL)
    print("Wrote \(outputURL.path)")
} catch {
    fputs("Could not write the DMG background: \(error.localizedDescription)\n", stderr)
    exit(1)
}
