import AppKit
import Carbon.HIToolbox
import Foundation

enum CaptureAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case region
    case delayedRegion
    case repeatRegion
    case filePin
    case scrollingRegion
    case display
    case window
    case regionAndPin
    case clipboardPin
    case togglePins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .region: L10n.text("action.region")
        case .delayedRegion: L10n.text("action.delayedRegion")
        case .repeatRegion: L10n.text("action.repeatRegion")
        case .filePin: L10n.text("action.filePin")
        case .scrollingRegion: L10n.text("action.scrollingRegion")
        case .display: L10n.text("action.display")
        case .window: L10n.text("action.window")
        case .regionAndPin: L10n.text("action.regionAndPin")
        case .clipboardPin: L10n.text("action.clipboardPin")
        case .togglePins: L10n.text("action.togglePins")
        }
    }
}

enum CaptureQuality: String, CaseIterable, Codable, Identifiable, Sendable {
    case native
    case hd720
    case fullHD1080
    case qhd2K
    case uhd4K
    case uhd8K

    static let userDefaultsKey = "captureQuality"
    static let defaultValue: CaptureQuality = .fullHD1080

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: L10n.text("quality.native")
        case .hd720: "720p"
        case .fullHD1080: "1080p"
        case .qhd2K: "2K"
        case .uhd4K: "4K"
        case .uhd8K: "8K"
        }
    }

    var landscapePixelBounds: CGSize? {
        switch self {
        case .native: nil
        case .hd720: CGSize(width: 1280, height: 720)
        case .fullHD1080: CGSize(width: 1920, height: 1080)
        case .qhd2K: CGSize(width: 2560, height: 1440)
        case .uhd4K: CGSize(width: 3840, height: 2160)
        case .uhd8K: CGSize(width: 7680, height: 4320)
        }
    }

    static func current(defaults: UserDefaults = .standard) -> CaptureQuality {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let quality = CaptureQuality(rawValue: rawValue) else {
            return defaultValue
        }
        return quality
    }
}

struct Shortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        carbonModifiers = value
    }

    var displayText: String {
        if carbonModifiers == 0, Self.isFunctionKey(keyCode) {
            return "fn \(Self.keyName(for: keyCode))"
        }
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    var isSafeGlobalShortcut: Bool {
        carbonModifiers & (UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)) != 0
            || Self.isFunctionKey(keyCode)
    }

    static func isFunctionKey(_ code: UInt32) -> Bool {
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
                            kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18,
                            kVK_F19, kVK_F20].map(UInt32.init)
        return functionKeys.contains(code)
    }

    static func keyName(for code: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
        ]
        return names[code] ?? "Key\(code)"
    }
}

struct ShortcutBinding: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var action: CaptureAction
    var shortcut: Shortcut

    init(id: UUID = UUID(), action: CaptureAction, shortcut: Shortcut) {
        self.id = id
        self.action = action
        self.shortcut = shortcut
    }
}

/// 协调异步捕获和全局贴图快捷键，保证捕获完成前的贴图意图不会丢失。
struct CapturePipelineState: Equatable, Sendable {
    private(set) var isCapturing = false
    private(set) var shouldPinWhenReady = false

    mutating func beginCapture() -> Bool {
        guard !isCapturing else { return false }
        isCapturing = true
        shouldPinWhenReady = false
        return true
    }

    mutating func queuePinIfCapturing() -> Bool {
        guard isCapturing else { return false }
        shouldPinWhenReady = true
        return true
    }

    mutating func completeCapture(explicitPin: Bool) -> Bool {
        let shouldPin = explicitPin || shouldPinWhenReady
        isCapturing = false
        shouldPinWhenReady = false
        return shouldPin
    }

    mutating func cancelCapture() {
        isCapturing = false
        shouldPinWhenReady = false
    }
}

struct CaptureGeometry: Equatable, Sendable {
    let screenFrame: CGRect
    let selection: CGRect

    /// 将 AppKit 的全局左下原点坐标转换为 ScreenCaptureKit 的屏幕内左上原点坐标。
    var sourceRect: CGRect {
        CGRect(
            x: selection.minX - screenFrame.minX,
            y: screenFrame.maxY - selection.maxY,
            width: selection.width,
            height: selection.height
        )
    }

    func pixelCropRect(for pixelSize: CGSize) -> CGRect {
        let points = sourceRect
        let scaleX = pixelSize.width / screenFrame.width
        let scaleY = pixelSize.height / screenFrame.height
        let proposed = CGRect(
            x: points.minX * scaleX,
            y: points.minY * scaleY,
            width: points.width * scaleX,
            height: points.height * scaleY
        ).integral
        return proposed.intersection(CGRect(origin: .zero, size: pixelSize))
    }
}

enum HistoryOCRStatus: String, Codable, CaseIterable, Sendable {
    case notIndexed
    case pending
    case indexed
    case empty
    case failed
}

enum HistoryOCRTextNormalizer {
    static func normalize(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalizedLineEndings = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let normalized = normalizedLineEndings.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct HistoryItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let filename: String
    let pixelWidth: Int
    let pixelHeight: Int
    let sourceApplicationBundleIdentifier: String?
    var recognizedText: String?
    var ocrStatus: HistoryOCRStatus
    var ocrIndexedAt: Date?

    init(
        id: UUID,
        createdAt: Date,
        filename: String,
        pixelWidth: Int,
        pixelHeight: Int,
        sourceApplicationBundleIdentifier: String? = nil,
        recognizedText: String? = nil,
        ocrStatus: HistoryOCRStatus = .notIndexed,
        ocrIndexedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.filename = filename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.recognizedText = recognizedText
        self.ocrStatus = ocrStatus
        self.ocrIndexedAt = ocrIndexedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case filename
        case pixelWidth
        case pixelHeight
        case sourceApplicationBundleIdentifier
        case recognizedText
        case ocrStatus
        case ocrIndexedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        filename = try container.decode(String.self, forKey: .filename)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        sourceApplicationBundleIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .sourceApplicationBundleIdentifier
        )
        recognizedText = HistoryOCRTextNormalizer.normalize(
            try container.decodeIfPresent(String.self, forKey: .recognizedText)
        )
        ocrIndexedAt = try container.decodeIfPresent(Date.self, forKey: .ocrIndexedAt)
        if let decodedStatus = try container.decodeIfPresent(HistoryOCRStatus.self, forKey: .ocrStatus) {
            ocrStatus = decodedStatus
        } else {
            ocrStatus = recognizedText == nil ? .notIndexed : .indexed
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(filename, forKey: .filename)
        try container.encode(pixelWidth, forKey: .pixelWidth)
        try container.encode(pixelHeight, forKey: .pixelHeight)
        try container.encodeIfPresent(sourceApplicationBundleIdentifier, forKey: .sourceApplicationBundleIdentifier)
        try container.encodeIfPresent(recognizedText, forKey: .recognizedText)
        try container.encode(ocrStatus, forKey: .ocrStatus)
        try container.encodeIfPresent(ocrIndexedAt, forKey: .ocrIndexedAt)
    }
}

enum PinboardShotError: LocalizedError {
    case captureBusy
    case captureTimedOut
    case permissionDenied
    case displayUnavailable
    case windowUnavailable
    case clipboardHasNoImage
    case lastRegionUnavailable
    case imageEncodingFailed
    case imageScalingFailed
    case invalidSelection
    case emptyCaptureFrame
    case scrollTargetUnavailable
    case scrollCaptureNoMovement
    case ocrNoText

    var errorDescription: String? {
        switch self {
        case .captureBusy: L10n.text("error.captureBusy")
        case .captureTimedOut: L10n.text("error.captureTimedOut")
        case .permissionDenied: L10n.text("error.permissionDenied")
        case .displayUnavailable: L10n.text("error.displayUnavailable")
        case .windowUnavailable: L10n.text("error.windowUnavailable")
        case .clipboardHasNoImage: L10n.text("error.clipboardHasNoImage")
        case .lastRegionUnavailable: L10n.text("error.lastRegionUnavailable")
        case .imageEncodingFailed: L10n.text("error.imageEncodingFailed")
        case .imageScalingFailed: L10n.text("error.imageScalingFailed")
        case .invalidSelection: L10n.text("error.invalidSelection")
        case .emptyCaptureFrame: L10n.text("error.emptyCaptureFrame")
        case .scrollTargetUnavailable: L10n.text("error.scrollTargetUnavailable")
        case .scrollCaptureNoMovement: L10n.text("error.scrollCaptureNoMovement")
        case .ocrNoText: L10n.text("error.ocrNoText")
        }
    }
}
