import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing

@testable import PinboardShot

@Test("设置搜索可按功能查找并处理空白和无结果")
func preferencesSearchFindsFeatures() {
    #expect(PreferencesSection.capture.matches("光标"))
    #expect(PreferencesSection.general.matches(" 语言 "))
    #expect(PreferencesSection.updates.matches("检查 周期"))
    #expect(PreferencesSection.ocr.matches("api"))
    #expect(PreferencesSection.pins.matches("阴影"))
    #expect(!PreferencesSection.capture.matches("语言"))
    #expect(PreferencesSection.allCases.allSatisfy { $0.matches("  ") })
    #expect(!PreferencesSection.allCases.contains { $0.matches("不存在的设置xyz") })
}

private final class PreferencesFixtureFileManager: FileManager {
    let root: URL
    init(root: URL) {
        self.root = root
        super.init()
    }
    override func urls(
        for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        directory == .applicationSupportDirectory ? [root] : super.urls(for: directory, in: domainMask)
    }
}

/// Exercise the real SwiftUI pages using isolated stores; optional renders contain no user captures.
@Test("设置各分区在深浅色及最小和宽窗口下完成布局")
@MainActor
func preferencesPagesLayoutWithIsolatedStores() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "PinboardShot-settings-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let defaultsName = "PinboardShot-settings-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let fileManager = PreferencesFixtureFileManager(root: root)
    let history = HistoryStore(fileManager: fileManager, defaults: defaults)
    let workspaces = PinWorkspaceStore(rootDirectory: root.appendingPathComponent("workspaces"))
    let watermark = InvisibleWatermarkStore(
        directoryURL: root.appendingPathComponent("watermarks"),
        signingKeyData: Data(repeating: 1, count: 32))
    for index in 0..<3 {
        let image = NSImage(size: NSSize(width: 720, height: 400), flipped: false) { rect in
            (index == 0 ? NSColor(calibratedWhite: 0.19, alpha: 1) : index == 1 ? NSColor.systemIndigo : NSColor.systemGray).setFill()
            rect.fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            ("PINBOARDSHOT" as NSString).draw(at: NSPoint(x: 36, y: 330), withAttributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.7)
            ])
            (["An idea worth keeping.", "A space to think.", "Small details matter."][index] as NSString)
                .draw(at: NSPoint(x: 36, y: 200), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 38, weight: .semibold), .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraph
                ])
            return true
        }
        _ = try history.add(image)
    }
    let captures = history.items.prefix(2).enumerated().compactMap { index, item -> PinWorkspaceCapture? in
        guard let image = history.image(for: item) else { return nil }
        return PinWorkspaceCapture(image: image, state: PinWorkspaceWindowState(
            frame: CGRect(x: index * 240, y: index * 130, width: 400, height: 223),
            opacity: 1, ignoresMouseEvents: false, isPositionLocked: false, appearsOnAllSpaces: true,
            visibilityBundleIdentifier: nil, isAutoFadeOnHoverEnabled: false))
    }
    _ = try workspaces.save(name: "布局预览", captures: captures)
    let shortcuts = ShortcutStore(defaults: defaults)
    _ = shortcuts.add(action: .region, shortcut: Shortcut(keyCode: UInt32(kVK_F4), carbonModifiers: 0))
    _ = shortcuts.add(action: .clipboardPin, shortcut: Shortcut(keyCode: UInt32(kVK_F3), carbonModifiers: 0))
    let navigation = PreferencesNavigationModel()
    let health = AppHealthModel()
    health.screenCapturePermissionGranted = true
    let view = PreferencesView(
        shortcutStore: shortcuts, historyStore: history,
        pinWorkspaceStore: workspaces, watermarkStore: watermark,
        launchAtLoginManager: LaunchAtLoginManager(),
        localizationStore: LocalizationStore(defaults: defaults),
        updateManager: UpdateManager(startingUpdater: false), navigation: navigation, appHealth: health,
        onShortcutsChanged: {}, onPinShadowChanged: { _ in }, onTrayIconChanged: { _ in },
        onPinHistoryItem: { _ in }, onCopyHistoryItem: { _ in }, onSaveHistoryItem: { _ in },
        onCreateBoard: {},
        onSavePinWorkspace: { _ in throw PinWorkspaceStoreError.noPins },
        onRestorePinWorkspace: { _ in throw PinWorkspaceStoreError.noPins },
        onRenamePinWorkspace: { _, _ in throw PinWorkspaceStoreError.noPins },
        onDuplicatePinWorkspace: { _, _ in throw PinWorkspaceStoreError.noPins },
        onExportPinWorkspace: { _, _ in nil }, onDeletePinWorkspace: { _ in },
        onPinSessionRecoveryChanged: { _ in }, onReindexHistoryItem: { _ in },
        onRequestScreenCapturePermission: {}, onOpenScreenCaptureSettings: {}
    ).defaultAppStorage(defaults)

    for scheme in [ColorScheme.light, .dark] {
        for section in PreferencesSection.allCases {
            navigation.selectedSection = section
            for size in [
                NSSize(width: PreferencesWindowMetrics.width, height: PreferencesWindowMetrics.height),
                NSSize(width: 1080, height: 660),
            ] {
                let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).frame(width: size.width, height: size.height))
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(180))
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                #expect(bitmap.pixelsWide > 0)
                #expect(bitmap.pixelsHigh > 0)
                if let destination = ProcessInfo.processInfo.environment["PINBOARDSHOT_SETTINGS_SNAPSHOTS"] {
                    let directory = URL(fileURLWithPath: destination)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let data = try #require(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("\(section.rawValue)-\(scheme == .light ? "light" : "dark")-\(Int(size.width)).png"))
                }
                window.contentView = nil
            }
        }
    }
}
