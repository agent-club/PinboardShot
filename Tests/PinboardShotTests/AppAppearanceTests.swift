import AppKit
import Testing

@testable import PinboardShot

@Test("外观默认跟随系统，并能读取持久化的浅色和深色选择")
func appAppearancePersistsChoice() throws {
    let domain = "PinboardShot-Appearance-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    #expect(AppAppearance.current(defaults: defaults) == .system)
    for choice in [AppAppearance.light, .dark, .system] {
        defaults.set(choice.rawValue, forKey: AppAppearance.userDefaultsKey)
        let reopenedDefaults = try #require(UserDefaults(suiteName: domain))
        #expect(AppAppearance.current(defaults: reopenedDefaults) == choice)
    }
    defaults.set("unrecognized", forKey: AppAppearance.userDefaultsKey)
    #expect(AppAppearance.current(defaults: defaults) == .system)
}

@Test("强制外观立即应用，跟随系统会清除覆盖而不是固定当前颜色")
@MainActor
func appAppearanceClearsOverrideForSystem() {
    let application = NSApplication.shared
    let original = application.appearance
    defer { application.appearance = original }
    AppAppearance.light.apply()
    #expect(application.appearance?.name == .aqua)
    AppAppearance.dark.apply()
    #expect(application.appearance?.name == .darkAqua)
    AppAppearance.system.apply()
    #expect(application.appearance == nil)
}
