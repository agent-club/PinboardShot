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
                NSColor(srgbRed: 0.84, green: 0.66, blue: 0.29, alpha: 1),
                NSColor(srgbRed: 1.00, green: 0.91, blue: 0.64, alpha: 1),
                NSColor(srgbRed: 0.84, green: 0.66, blue: 0.29, alpha: 1),
                NSColor(srgbRed: 0.67, green: 0.47, blue: 0.16, alpha: 1)
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
        let size = NSSize(width: 18, height: 18)
        let normalizedFrame = normalizedIndex(frameIndex, count: animationColors.count)
        let frameGold = animationColors[normalizedFrame]
        let image = NSImage(size: size, flipped: false) { rect in
            let background = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.75, dy: 0.75),
                xRadius: 4.2,
                yRadius: 4.2
            )
            NSColor(srgbRed: 0.035, green: 0.035, blue: 0.04, alpha: 1).setFill()
            background.fill()

            frameGold.setStroke()
            background.lineWidth = 1.15
            background.stroke()

            let cornerPath = NSBezierPath()
            cornerPath.lineWidth = 1.45
            cornerPath.lineCapStyle = .round
            let inset: CGFloat = 4.6
            let arm: CGFloat = 2.55
            let minX = rect.minX + inset
            let maxX = rect.maxX - inset
            let minY = rect.minY + inset
            let maxY = rect.maxY - inset

            cornerPath.move(to: NSPoint(x: minX, y: minY + arm))
            cornerPath.line(to: NSPoint(x: minX, y: minY))
            cornerPath.line(to: NSPoint(x: minX + arm, y: minY))
            cornerPath.move(to: NSPoint(x: maxX - arm, y: minY))
            cornerPath.line(to: NSPoint(x: maxX, y: minY))
            cornerPath.line(to: NSPoint(x: maxX, y: minY + arm))
            cornerPath.move(to: NSPoint(x: maxX, y: maxY - arm))
            cornerPath.line(to: NSPoint(x: maxX, y: maxY))
            cornerPath.line(to: NSPoint(x: maxX - arm, y: maxY))
            cornerPath.move(to: NSPoint(x: minX + arm, y: maxY))
            cornerPath.line(to: NSPoint(x: minX, y: maxY))
            cornerPath.line(to: NSPoint(x: minX, y: maxY - arm))
            cornerPath.stroke()

            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = normalizedFrame == 1 ? 3.0 : 2.45
            let star = NSBezierPath()
            star.move(to: NSPoint(x: center.x, y: center.y + radius))
            star.curve(
                to: NSPoint(x: center.x + radius, y: center.y),
                controlPoint1: NSPoint(x: center.x + 0.45, y: center.y + 0.45),
                controlPoint2: NSPoint(x: center.x + 0.45, y: center.y + 0.45)
            )
            star.curve(
                to: NSPoint(x: center.x, y: center.y - radius),
                controlPoint1: NSPoint(x: center.x + 0.45, y: center.y - 0.45),
                controlPoint2: NSPoint(x: center.x + 0.45, y: center.y - 0.45)
            )
            star.curve(
                to: NSPoint(x: center.x - radius, y: center.y),
                controlPoint1: NSPoint(x: center.x - 0.45, y: center.y - 0.45),
                controlPoint2: NSPoint(x: center.x - 0.45, y: center.y - 0.45)
            )
            star.curve(
                to: NSPoint(x: center.x, y: center.y + radius),
                controlPoint1: NSPoint(x: center.x - 0.45, y: center.y + 0.45),
                controlPoint2: NSPoint(x: center.x - 0.45, y: center.y + 0.45)
            )
            star.close()
            NSColor(srgbRed: 1.00, green: 0.91, blue: 0.64, alpha: 1).setFill()
            star.fill()
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
