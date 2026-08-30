import AppIntents
import AppKit

enum AutomationCaptureMode: String, AppEnum {
    case region
    case delayed
    case repeatRegion
    case scrolling
    case display
    case window

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Capture Mode")
    static let caseDisplayRepresentations: [AutomationCaptureMode: DisplayRepresentation] = [
        .region: "Region",
        .delayed: "3-Second Delay",
        .repeatRegion: "Repeat Last Region",
        .scrolling: "Scrolling Capture",
        .display: "Current Display",
        .window: "Window Under Pointer"
    ]

    var urlValue: String {
        switch self {
        case .repeatRegion: "repeat"
        case .scrolling: "scroll"
        default: rawValue
        }
    }
}

struct CaptureWithPinboardShotIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture with PinboardShot"
    static let description = IntentDescription("Start a local screenshot and optionally pin the result.")
    static let openAppWhenRun = true

    @Parameter(title: "Mode", default: .region)
    var mode: AutomationCaptureMode

    @Parameter(title: "Pin Result", default: false)
    var pinResult: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        var components = URLComponents()
        components.scheme = "pinboardshot"
        components.host = "capture"
        var items = [URLQueryItem(name: "mode", value: mode.urlValue)]
        if pinResult { items.append(URLQueryItem(name: "after", value: "pin")) }
        components.queryItems = items
        if let url = components.url { NSWorkspace.shared.open(url) }
        return .result()
    }
}

struct PinClipboardWithPinboardShotIntent: AppIntent {
    static let title: LocalizedStringResource = "Pin Clipboard Image"
    static let description = IntentDescription("Pin the current clipboard image without uploading it.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "pinboardshot://pin-clipboard") {
            NSWorkspace.shared.open(url)
        }
        return .result()
    }
}

struct TogglePinsWithPinboardShotIntent: AppIntent {
    static let title: LocalizedStringResource = "Show or Hide PinboardShot Pins"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "pinboardshot://toggle-pins") {
            NSWorkspace.shared.open(url)
        }
        return .result()
    }
}

struct PinboardShotAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureWithPinboardShotIntent(),
            phrases: ["Capture with \(.applicationName)"],
            shortTitle: "Capture",
            systemImageName: "viewfinder"
        )
        AppShortcut(
            intent: PinClipboardWithPinboardShotIntent(),
            phrases: ["Pin the clipboard with \(.applicationName)"],
            shortTitle: "Pin Clipboard",
            systemImageName: "pin"
        )
        AppShortcut(
            intent: TogglePinsWithPinboardShotIntent(),
            phrases: ["Toggle pins in \(.applicationName)"],
            shortTitle: "Toggle Pins",
            systemImageName: "eye"
        )
    }
}
