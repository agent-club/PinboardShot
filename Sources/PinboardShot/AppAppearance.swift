import AppKit

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let userDefaultsKey = "appAppearance"
    var id: String { rawValue }

    var title: String { L10n.text("appearance.\(rawValue)") }

    static func current(defaults: UserDefaults = .standard) -> AppAppearance {
        defaults.string(forKey: userDefaultsKey).flatMap(Self.init(rawValue:)) ?? .system
    }

    @MainActor
    func apply() {
        switch self {
        case .system:
            // Clearing the override lets existing and future windows follow macOS automatically.
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
