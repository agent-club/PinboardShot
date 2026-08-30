import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var bindings: [ShortcutBinding] = []
    private let defaults: UserDefaults
    private let storageKey = "shortcutBindings.v3"
    private let previousStorageKey = "shortcutBindings.v2"
    private let legacyStorageKey = "shortcuts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func shortcut(for action: CaptureAction) -> Shortcut? {
        bindings.first(where: { $0.action == action })?.shortcut
    }

    @discardableResult
    func update(bindingID: UUID, shortcut: Shortcut) -> Bool {
        guard shortcut.isSafeGlobalShortcut else { return false }
        guard !bindings.contains(where: { $0.id != bindingID && $0.shortcut == shortcut }),
              let index = bindings.firstIndex(where: { $0.id == bindingID }) else { return false }
        bindings[index].shortcut = shortcut
        persist()
        return true
    }

    @discardableResult
    func add(action: CaptureAction, shortcut: Shortcut) -> UUID? {
        guard shortcut.isSafeGlobalShortcut,
              !bindings.contains(where: { $0.shortcut == shortcut }) else { return nil }
        let binding = ShortcutBinding(action: action, shortcut: shortcut)
        bindings.append(binding)
        persist()
        return binding.id
    }

    func remove(bindingID: UUID) {
        bindings.removeAll { $0.id == bindingID }
        persist()
    }

    func reset() {
        bindings = []
        persist()
    }

    private func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ShortcutBinding].self, from: data) {
            bindings = decoded
            return
        }

        if let data = defaults.data(forKey: previousStorageKey),
           let decoded = try? JSONDecoder().decode([ShortcutBinding].self, from: data) {
            // v2 把内置默认值和用户绑定存成同一种记录；升级时只移除可识别的内置默认值。
            bindings = decoded.filter {
                $0.shortcut != Self.versionTwoDefaultShortcut(for: $0.action)
            }
            persist()
            return
        }

        if let legacyData = defaults.data(forKey: legacyStorageKey),
           let legacy = try? JSONDecoder().decode([String: Shortcut].self, from: legacyData) {
            // v1 每个动作只有一个槽位，只有偏离两代内置默认值的组合才视为用户自定义。
            bindings = CaptureAction.allCases.compactMap { action in
                guard let shortcut = legacy[action.rawValue],
                      shortcut != Self.versionOneDefaultShortcut(for: action),
                      shortcut != Self.versionTwoDefaultShortcut(for: action) else { return nil }
                return ShortcutBinding(action: action, shortcut: shortcut)
            }
            persist()
            return
        }

        reset()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bindings) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func versionOneDefaultShortcut(for action: CaptureAction) -> Shortcut {
        switch action {
        case .region: Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: [.command, .shift])
        case .delayedRegion: Shortcut(keyCode: UInt32(kVK_F4), carbonModifiers: 0)
        case .repeatRegion: Shortcut(keyCode: UInt32(kVK_F5), carbonModifiers: 0)
        case .filePin: Shortcut(keyCode: UInt32(kVK_F6), carbonModifiers: 0)
        case .scrollingRegion: Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: [.command, .shift])
        case .display: Shortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: [.command, .shift])
        case .window: Shortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: [.command, .shift])
        case .regionAndPin: Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: [.command, .shift])
        case .clipboardPin: Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift])
        case .togglePins: Shortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: [.command, .shift])
        }
    }

    private static func versionTwoDefaultShortcut(for action: CaptureAction) -> Shortcut {
        switch action {
        case .region: Shortcut(keyCode: UInt32(kVK_F1), carbonModifiers: 0)
        case .delayedRegion: Shortcut(keyCode: UInt32(kVK_F4), carbonModifiers: 0)
        case .repeatRegion: Shortcut(keyCode: UInt32(kVK_F5), carbonModifiers: 0)
        case .filePin: Shortcut(keyCode: UInt32(kVK_F6), carbonModifiers: 0)
        case .scrollingRegion: Shortcut(keyCode: UInt32(kVK_F2), carbonModifiers: 0)
        case .display: Shortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: [.command, .shift])
        case .window: Shortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: [.command, .shift])
        case .regionAndPin: Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: [.command, .shift])
        case .clipboardPin: Shortcut(keyCode: UInt32(kVK_F3), carbonModifiers: 0)
        case .togglePins: Shortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: [.command, .shift])
        }
    }
}

@MainActor
final class HotKeyManager {
    var onAction: ((CaptureAction) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionByID: [UInt32: CaptureAction] = [:]
    private var handlerRef: EventHandlerRef?

    init() {
        // Carbon 回调没有 Swift 闭包上下文，通过 userData 找回应用生命周期内的管理器。
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    if let action = manager.actionByID[identifier.id] {
                        manager.onAction?(action)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    @discardableResult
    func register(bindings: [ShortcutBinding]) -> [ShortcutBinding] {
        hotKeyRefs.forEach { _ = UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actionByID.removeAll()
        var failedBindings: [ShortcutBinding] = []

        for (offset, binding) in bindings.enumerated() {
            let id = UInt32(offset + 1)
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            if RegisterEventHotKey(
                binding.shortcut.keyCode,
                binding.shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            ) == noErr, let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
                actionByID[id] = binding.action
            } else {
                failedBindings.append(binding)
            }
        }
        return failedBindings
    }

    func unregisterAll() {
        hotKeyRefs.forEach { _ = UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actionByID.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private static let signature: OSType = {
        let bytes = Array("PBSH".utf8)
        return bytes.reduce(0) { ($0 << 8) | OSType($1) }
    }()
}
