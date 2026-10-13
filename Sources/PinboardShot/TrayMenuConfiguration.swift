import Foundation
import SwiftUI

enum TrayMenuConfigurationItem: String, CaseIterable, Identifiable {
    case outputQuality
    case includeCursor
    case captureAnimation
    case pinShadow
    case magneticDesktop

    var id: String { rawValue }
    var visibilityKey: String { "trayMenu.show.\(rawValue)" }

    var title: String {
        switch self {
        case .outputQuality: L10n.text("preferences.outputQuality")
        case .includeCursor: L10n.text("tray.setting.includeCursor")
        case .captureAnimation: L10n.text("tray.setting.captureAnimation")
        case .pinShadow: L10n.text("tray.setting.pinShadow")
        case .magneticDesktop: L10n.text("tray.section.magneticDesktop")
        }
    }

    func isVisible(defaults: UserDefaults = .standard) -> Bool {
        // Absence uses the agreed menu preset; an explicit false must stay hidden after relaunch.
        defaults.object(forKey: visibilityKey) == nil || defaults.bool(forKey: visibilityKey)
    }
}

struct TrayMenuDisplayPreferences: View {
    var body: some View {
        ForEach(TrayMenuConfigurationItem.allCases) { item in
            TrayMenuVisibilityToggle(item: item)
        }
    }
}

private struct TrayMenuVisibilityToggle: View {
    let item: TrayMenuConfigurationItem
    @AppStorage private var isVisible: Bool

    init(item: TrayMenuConfigurationItem) {
        self.item = item
        _isVisible = AppStorage(wrappedValue: item.isVisible(), item.visibilityKey)
    }

    var body: some View {
        Toggle(item.title, isOn: $isVisible).clickCursor()
    }
}
