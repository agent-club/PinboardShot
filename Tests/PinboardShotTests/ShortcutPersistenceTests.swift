import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import PinboardShot

@Suite("Shortcut persistence validation")
@MainActor
struct ShortcutPersistenceTests {
    @Test("重启过滤不安全按键、重复按键和重复 ID，并保留有效绑定")
    func validatesStoredBindings() throws {
        let name = "PinboardShotShortcutValidation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = ShortcutBinding(action: .region, shortcut: Shortcut(keyCode: UInt32(kVK_F7), carbonModifiers: 0))
        let second = ShortcutBinding(action: .display, shortcut: Shortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: [.command, .shift]))
        let invalid = [
            ShortcutBinding(action: .display, shortcut: Shortcut(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: 0)),
            ShortcutBinding(action: .window, shortcut: first.shortcut),
            ShortcutBinding(id: first.id, action: .repeatRegion, shortcut: Shortcut(keyCode: UInt32(kVK_F8), carbonModifiers: 0)),
            ShortcutBinding(action: .region, shortcut: Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: [.shift]))
        ]
        defaults.set(try JSONEncoder().encode([first] + invalid + [second]), forKey: "shortcutBindings.v3")

        let store = ShortcutStore(defaults: defaults)

        #expect(store.bindings == [first, second])
        #expect(ShortcutStore(defaults: defaults).bindings == [first, second])
        let persisted = try JSONDecoder().decode(
            [ShortcutBinding].self, from: #require(defaults.data(forKey: "shortcutBindings.v3"))
        )
        #expect(persisted == [first, second])
    }

    @Test("旧配置迁移也执行相同校验")
    func validatesMigratedBindings() throws {
        let name = "PinboardShotShortcutMigrationValidation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let valid = ShortcutBinding(action: .region, shortcut: Shortcut(keyCode: UInt32(kVK_F9), carbonModifiers: 0))
        let invalid = ShortcutBinding(action: .display, shortcut: Shortcut(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: 0))
        defaults.set(try JSONEncoder().encode([valid, invalid]), forKey: "shortcutBindings.v2")
        #expect(ShortcutStore(defaults: defaults).bindings == [valid])
    }
}
