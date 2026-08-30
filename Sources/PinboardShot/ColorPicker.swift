import AppKit

enum ColorSampleFormat: String, CaseIterable, Identifiable, Sendable {
    case hex
    case hexa
    case rgb
    case rgba
    case hsl
    case swiftUI
    case nsColor

    static let userDefaultsKey = "colorPicker.format"

    var id: String { rawValue }
    var titleKey: String { "colorPicker.format.\(rawValue)" }

    var menuTag: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func format(for menuTag: Int) -> ColorSampleFormat? {
        guard allCases.indices.contains(menuTag) else { return nil }
        return allCases[menuTag]
    }

    static func current(defaults: UserDefaults = .standard) -> ColorSampleFormat {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let format = ColorSampleFormat(rawValue: rawValue) else {
            return .hex
        }
        return format
    }

    static func set(_ format: ColorSampleFormat, defaults: UserDefaults = .standard) {
        defaults.set(format.rawValue, forKey: userDefaultsKey)
    }

    func string(for color: NSColor) -> String {
        let rgba = RGBAComponents(color)
        switch self {
        case .hex:
            return String(format: "#%02X%02X%02X", rgba.redByte, rgba.greenByte, rgba.blueByte)
        case .hexa:
            return String(format: "#%02X%02X%02X%02X", rgba.redByte, rgba.greenByte, rgba.blueByte, rgba.alphaByte)
        case .rgb:
            return String(format: "rgb(%d, %d, %d)", rgba.redByte, rgba.greenByte, rgba.blueByte)
        case .rgba:
            return String(format: "rgba(%d, %d, %d, %@)", rgba.redByte, rgba.greenByte, rgba.blueByte, rgba.alphaText)
        case .hsl:
            let hsl = rgba.hsl
            return String(format: "hsl(%ddeg, %d%%, %d%%)", hsl.hue, hsl.saturation, hsl.lightness)
        case .swiftUI:
            return String(
                format: "Color(red: %@, green: %@, blue: %@, opacity: %@)",
                rgba.redText,
                rgba.greenText,
                rgba.blueText,
                rgba.alphaText
            )
        case .nsColor:
            return String(
                format: "NSColor(red: %@, green: %@, blue: %@, alpha: %@)",
                rgba.redText,
                rgba.greenText,
                rgba.blueText,
                rgba.alphaText
            )
        }
    }
}

private struct RGBAComponents {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? .black
        red = Self.clamped(converted.redComponent)
        green = Self.clamped(converted.greenComponent)
        blue = Self.clamped(converted.blueComponent)
        alpha = Self.clamped(converted.alphaComponent)
    }

    var redByte: Int { Self.byte(red) }
    var greenByte: Int { Self.byte(green) }
    var blueByte: Int { Self.byte(blue) }
    var alphaByte: Int { Self.byte(alpha) }
    var redText: String { Self.decimal(red) }
    var greenText: String { Self.decimal(green) }
    var blueText: String { Self.decimal(blue) }
    var alphaText: String { Self.decimal(alpha) }

    var hsl: (hue: Int, saturation: Int, lightness: Int) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation: CGFloat
        if delta == 0 {
            saturation = 0
        } else {
            saturation = delta / (1 - abs(2 * lightness - 1))
        }

        let hue: CGFloat
        if delta == 0 {
            hue = 0
        } else if maximum == red {
            hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
        } else if maximum == green {
            hue = 60 * (((blue - red) / delta) + 2)
        } else {
            hue = 60 * (((red - green) / delta) + 4)
        }

        return (
            hue: Int(round(hue < 0 ? hue + 360 : hue)),
            saturation: Int(round(saturation * 100)),
            lightness: Int(round(lightness * 100))
        )
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private static func byte(_ value: CGFloat) -> Int {
        Int(round(clamped(value) * 255))
    }

    private static func decimal(_ value: CGFloat) -> String {
        let formatted = String(format: "%.3f", clamped(value))
        return formatted
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

enum ScreenColorSampler {
    static func color(in image: CGImage, bounds: CGRect, at point: CGPoint) -> NSColor? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return nil }
        let x = min(
            max(Int(((point.x - bounds.minX) / bounds.width * CGFloat(image.width)).rounded(.down)), 0),
            image.width - 1
        )
        let y = min(
            max(Int(((bounds.maxY - point.y) / bounds.height * CGFloat(image.height)).rounded(.down)), 0),
            image.height - 1
        )
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        return NSBitmapImageRep(cgImage: cropped).colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB)
    }
}

@MainActor
struct ColorClipboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func write(_ string: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}
