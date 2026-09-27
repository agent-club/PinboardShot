import AppKit
import Foundation

enum TrayIconChoice: String, CaseIterable, Identifiable, Sendable {
    static let userDefaultsKey = "trayIconChoice"
    static let defaultChoice: TrayIconChoice = .rectangularViewfinder
    static let animationInterval: TimeInterval = 0.8

    case viewfinder
    case rectangularViewfinder
    case focus
    case camera
    case cameraFilled
    case photo
    case pin
    case pinFilled
    case crop
    case dashedRectangle
    case scope
    case screenshot
    case animatedViewfinder
    case animatedCamera
    case colorfulViewfinder
    case colorfulCamera
    // Preserve the stored choice identifier so existing selections keep working.
    case solCrafted

    var id: String { rawValue }

    var systemSymbolName: String {
        switch self {
        case .viewfinder: "viewfinder"
        case .rectangularViewfinder: "viewfinder.rectangular"
        case .focus: "plus.viewfinder"
        case .camera: "camera"
        case .cameraFilled: "camera.fill"
        case .photo: "photo.on.rectangle"
        case .pin: "pin"
        case .pinFilled: "pin.fill"
        case .crop: "crop"
        case .dashedRectangle: "rectangle.dashed"
        case .scope: "scope"
        case .screenshot: "macwindow.on.rectangle"
        case .animatedViewfinder, .colorfulViewfinder: "viewfinder"
        case .animatedCamera, .colorfulCamera: "camera"
        case .solCrafted: "viewfinder"
        }
    }

    static var monochromeChoices: [TrayIconChoice] {
        allCases.filter { !$0.usesColor }
    }

    static var colorChoices: [TrayIconChoice] {
        allCases.filter(\.usesColor)
    }

    var usesColor: Bool {
        switch self {
        case .colorfulViewfinder, .colorfulCamera, .solCrafted: true
        default: false
        }
    }

    var animationSymbolNames: [String] {
        switch self {
        case .animatedViewfinder, .colorfulViewfinder:
            ["viewfinder", "plus.viewfinder", "viewfinder.rectangular", "plus.viewfinder"]
        case .animatedCamera, .colorfulCamera:
            ["camera", "camera.fill", "camera", "camera.fill"]
        case .solCrafted:
            ["viewfinder", "viewfinder", "viewfinder", "viewfinder"]
        default:
            [systemSymbolName]
        }
    }

    var animationColors: [NSColor] {
        switch self {
        case .colorfulViewfinder:
            [.systemBlue, .systemPurple, .systemPink, .systemOrange]
        case .colorfulCamera:
            [.systemOrange, .systemPink, .systemPurple, .systemBlue]
        case .solCrafted:
            [
                NSColor(srgbRed: 1.00, green: 0.73, blue: 0.31, alpha: 1),
                NSColor(srgbRed: 1.00, green: 0.56, blue: 0.42, alpha: 1),
                NSColor(srgbRed: 1.00, green: 0.37, blue: 0.47, alpha: 1),
                NSColor(srgbRed: 1.00, green: 0.56, blue: 0.42, alpha: 1)
            ]
        default:
            []
        }
    }

    var isAnimated: Bool {
        animationSymbolNames.count > 1 || animationColors.count > 1
    }

    var title: String {
        L10n.text("preferences.trayIcon.\(rawValue)")
    }

    static func current(defaults: UserDefaults = .standard) -> TrayIconChoice {
        guard let rawValue = defaults.string(forKey: userDefaultsKey) else { return defaultChoice }
        return TrayIconChoice(rawValue: rawValue) ?? defaultChoice
    }

    func frameIndex(at date: Date) -> Int {
        guard isAnimated else { return 0 }
        return Int(date.timeIntervalSinceReferenceDate / Self.animationInterval)
    }

    func symbolName(frameIndex: Int) -> String {
        animationSymbolNames[normalizedIndex(frameIndex, count: animationSymbolNames.count)]
    }

    func color(frameIndex: Int) -> NSColor? {
        guard !animationColors.isEmpty else { return nil }
        return animationColors[normalizedIndex(frameIndex, count: animationColors.count)]
    }

    func statusBarImage(frameIndex: Int = 0) -> NSImage? {
        if self == .solCrafted {
            return solCraftedStatusBarImage(frameIndex: frameIndex)
        }

        guard let image = NSImage(
            systemSymbolName: symbolName(frameIndex: frameIndex),
            accessibilityDescription: title
        ) else { return nil }
        guard let color = color(frameIndex: frameIndex) else {
            image.isTemplate = true
            return image
        }

        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        let configuredImage = image.withSymbolConfiguration(configuration) ?? image
        configuredImage.isTemplate = false
        return configuredImage
    }

    var usesCustomArtwork: Bool {
        self == .solCrafted
    }

    private func solCraftedStatusBarImage(frameIndex: Int) -> NSImage {
        let size = NSSize(width: 21, height: 21)
        let pinColor = animationColors[normalizedIndex(frameIndex, count: animationColors.count)]
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let scale = NSAffineTransform()
            scale.scale(by: size.width / 18)
            scale.concat()
            let rect = NSRect(x: 0, y: 0, width: 18, height: 18)
            let background = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.75, dy: 0.75),
                xRadius: 4.2,
                yRadius: 4.2
            )
            NSColor(srgbRed: 0.10, green: 0.09, blue: 0.27, alpha: 1).setFill()
            background.fill()

            let backSheet = NSBezierPath()
            backSheet.move(to: NSPoint(x: 3.7, y: 4.0))
            backSheet.line(to: NSPoint(x: 12.7, y: 3.3))
            backSheet.line(to: NSPoint(x: 14.3, y: 12.5))
            backSheet.line(to: NSPoint(x: 5.2, y: 13.8))
            backSheet.close()
            NSColor(srgbRed: 0.54, green: 0.36, blue: 0.96, alpha: 1).setFill()
            backSheet.fill()

            let frontSheet = NSBezierPath()
            frontSheet.move(to: NSPoint(x: 4.3, y: 4.0))
            frontSheet.line(to: NSPoint(x: 13.1, y: 5.1))
            frontSheet.line(to: NSPoint(x: 12.9, y: 13.8))
            frontSheet.line(to: NSPoint(x: 3.6, y: 12.8))
            frontSheet.close()
            NSColor(srgbRed: 0.91, green: 0.94, blue: 1.00, alpha: 1).setFill()
            frontSheet.fill()

            let photoScene = NSBezierPath()
            photoScene.move(to: NSPoint(x: 4.8, y: 5.8))
            photoScene.line(to: NSPoint(x: 7.0, y: 9.1))
            photoScene.line(to: NSPoint(x: 8.5, y: 7.7))
            photoScene.line(to: NSPoint(x: 10.0, y: 9.2))
            photoScene.line(to: NSPoint(x: 12.1, y: 6.7))
            photoScene.close()
            NSColor(srgbRed: 0.29, green: 0.28, blue: 0.65, alpha: 1).setFill()
            photoScene.fill()

            let pinHead = NSBezierPath(ovalIn: NSRect(x: 9.6, y: 10.4, width: 5.2, height: 5.2))
            pinColor.setFill()
            pinHead.fill()
            NSColor(srgbRed: 1.00, green: 0.82, blue: 0.50, alpha: 1).setStroke()
            pinHead.lineWidth = 0.55
            pinHead.stroke()

            let pinCenter = NSBezierPath(ovalIn: NSRect(x: 11.55, y: 12.35, width: 1.3, height: 1.3))
            NSColor(srgbRed: 0.29, green: 0.11, blue: 0.40, alpha: 1).setFill()
            pinCenter.fill()

            let pinStem = NSBezierPath()
            pinStem.move(to: NSPoint(x: 12.3, y: 10.7))
            pinStem.line(to: NSPoint(x: 12.6, y: 8.9))
            pinStem.lineWidth = 0.9
            pinStem.lineCapStyle = .round
            NSColor(srgbRed: 0.29, green: 0.11, blue: 0.40, alpha: 1).setStroke()
            pinStem.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = title
        return image
    }

    private func normalizedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }
}
