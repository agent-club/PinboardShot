import AppKit
import Testing
@testable import PinboardShot

@Suite("Capture selection stacking", .serialized)
@MainActor
struct CaptureSelectionLevelTests {
    @Test("置顶默认开启，关闭后恢复浮动层级，再次开启立即生效")
    func preference() throws {
        let suite = "CaptureSelectionLevelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let defaultLevel = OverlaySafetyPolicy.configuredWindowLevel(defaults: defaults)
        #expect(defaultLevel.rawValue > NSWindow.Level.popUpMenu.rawValue)
        #expect(defaultLevel.rawValue > NSWindow.Level.modalPanel.rawValue)
        #expect(defaultLevel.rawValue < NSWindow.Level.screenSaver.rawValue)

        defaults.set(false, forKey: OverlaySafetyPolicy.alwaysOnTopDefaultsKey)
        #expect(OverlaySafetyPolicy.configuredWindowLevel(defaults: defaults) == .floating)
        defaults.set(true, forKey: OverlaySafetyPolicy.alwaysOnTopDefaultsKey)
        #expect(OverlaySafetyPolicy.configuredWindowLevel(defaults: defaults) == defaultLevel)
    }

    @Test("尺寸编辑窗口位于置顶选区之上，普通模式仍使用模态层级")
    func sizeEditor() throws {
        _ = NSApplication.shared
        let suite = "CaptureSelectionPanelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let parent = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: .borderless, backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let editor = SelectionSizeEditorCoordinator(size: CGSize(width: 100, height: 100),
            currentRatio: 1, lockedRatio: nil, maximumSize: CGSize(width: 640, height: 480))

        parent.level = OverlaySafetyPolicy.configuredWindowLevel(defaults: defaults)
        let topPanel = editor.makePanel(relativeTo: parent)
        #expect(topPanel.level.rawValue > parent.level.rawValue)
        #expect(topPanel.level.rawValue < NSWindow.Level.screenSaver.rawValue)
        topPanel.close()

        parent.level = .floating
        let normalPanel = editor.makePanel(relativeTo: parent)
        #expect(normalPanel.level == .modalPanel)
        normalPanel.close()
        parent.close()
    }
}
