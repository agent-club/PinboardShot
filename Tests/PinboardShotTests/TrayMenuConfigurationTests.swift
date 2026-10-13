import AppKit
import Foundation
import SwiftUI
import Testing
@testable import PinboardShot

@Suite("Tray menu configuration")
struct TrayMenuConfigurationTests {
    @Test("Default preset is visible, while explicit hidden choices survive a new defaults instance")
    func persistedVisibility() throws {
        let suite = "PinboardShot.TrayMenuTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for item in TrayMenuConfigurationItem.allCases {
            #expect(item.isVisible(defaults: defaults))
        }
        defaults.set(false, forKey: TrayMenuConfigurationItem.includeCursor.visibilityKey)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(!TrayMenuConfigurationItem.includeCursor.isVisible(defaults: reopened))
        #expect(TrayMenuConfigurationItem.captureAnimation.isVisible(defaults: reopened))
    }

    @Test("Hiding magnetic configuration preserves the feature's enabled state and limit")
    func visibilityDoesNotChangeFeature() throws {
        let suite = "PinboardShot.TrayMenuTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(7, forKey: MagneticDesktopSettings.maximumVisibleKey)
        defaults.set(false, forKey: TrayMenuConfigurationItem.magneticDesktop.visibilityKey)
        #expect(!TrayMenuConfigurationItem.magneticDesktop.isVisible(defaults: defaults))
        let settings = MagneticDesktopSettings(defaults: defaults)
        #expect(settings.isEnabled)
        #expect(settings.maximumVisible == 7)
    }

    @Test("Hiding every quick setting removes its entry, while quality visibility remains independent")
    @MainActor
    func hiddenSectionsReduceHeight() throws {
        let suite = "PinboardShot.TrayMenuTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func height() -> CGFloat {
            let panel = TrayPanelView(
                permissionGranted: true, failedHotKeyCount: 0,
                canCheckForUpdates: true, lastUpdateCheckDate: nil, updateNotice: nil,
                pinCount: 0, pinsAreVisible: false, height: nil,
                onPinShadowChanged: { _ in }, onDismissUpdateNotice: {}, onCommand: { _ in }
            ).defaultAppStorage(defaults)
            return NSHostingController(rootView: panel).sizeThatFits(in: NSSize(
                width: TrayPanelMetrics.width, height: TrayPanelMetrics.measurementHeightLimit
            )).height
        }
        let defaultHeight = height()
        for item in TrayMenuConfigurationItem.allCases where item != .outputQuality {
            defaults.set(false, forKey: item.visibilityKey)
        }
        let withoutQuickSettingsHeight = height()
        #expect(withoutQuickSettingsHeight < defaultHeight)
        defaults.set(false, forKey: TrayMenuConfigurationItem.outputQuality.visibilityKey)
        let hiddenHeight = height()
        #expect(hiddenHeight < withoutQuickSettingsHeight)
        #expect(hiddenHeight > 0)
    }
}
