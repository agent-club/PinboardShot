import AppKit
import Foundation
import SwiftUI
import Testing
@testable import PinboardShot

private final class MagneticFileManager: FileManager {
    let root: URL
    init(root: URL) { self.root = root; super.init() }
    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        directory == .applicationSupportDirectory ? [root] : super.urls(for: directory, in: domainMask)
    }
}

private final class MagneticClickProbeWindow: NSWindow {
    var receivedClick: NSEvent?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { receivedClick = event }
        super.sendEvent(event)
    }
}

private final class MagneticScrollSink: NSResponder {
    var received = 0
    override func scrollWheel(with event: NSEvent) { received += 1 }
}

@MainActor
private final class MagneticContextMenuProbe: NSObject {
    weak var panel: PinPanel?
    private var activeMenu: NSMenu?
    var openedCount = 0
    var selectedCount = 0
    var zoomSucceeded = false
    var selectionTitle = L10n.text("pin.zoomIn")

    @objc func menuBeganTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu, let panel,
              menu.items.contains(where: { $0.title == L10n.text("magnetic.return") }),
              let actionIndex = menu.items.firstIndex(where: { $0.title == selectionTitle }) else { return }
        openedCount += 1
        activeMenu = menu
        let width = panel.frame.width
        // Exercise the real AppKit tracking loop and end it without relying on physical mouse input.
        let timer = Timer(timeInterval: 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let menu = self.activeMenu, let panel = self.panel else { return }
                if let entered = NSEvent.enterExitEvent(with: .mouseEntered,
                    location: CGPoint(x: 40, y: 40), modifierFlags: [], timestamp: 1,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 1,
                    trackingNumber: 0, userData: nil) {
                    panel.sendEvent(entered)
                }
                menu.performActionForItem(at: actionIndex)
                self.zoomSucceeded = panel.frame.width > width
                self.selectedCount += 1
                menu.cancelTracking()
                self.activeMenu = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }
}

@Suite("Magnetic Desktop", .serialized)
@MainActor
struct MagneticDesktopTests {
    @Test("Animation preferences persist without changing the default style")
    func animationSettingsPersist() throws {
        let suite = "MagneticAnimationSettings.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MagneticDesktopSettings(defaults: defaults).animationStyle == .full)
        #expect(!MagneticDesktopSettings(defaults: defaults).reduceMotion)
        defaults.set(MagneticAnimationStyle.simple.rawValue, forKey: MagneticDesktopSettings.animationStyleKey)
        defaults.set(true, forKey: MagneticDesktopSettings.reduceMotionKey)
        let reloaded = try #require(UserDefaults(suiteName: suite))
        #expect(MagneticDesktopSettings(defaults: reloaded).animationStyle == .simple)
        #expect(MagneticDesktopSettings(defaults: reloaded).reduceMotion)
        for style in MagneticAnimationStyle.allCases {
            defaults.set(style.rawValue, forKey: MagneticDesktopSettings.animationStyleKey)
            #expect(MagneticDesktopSettings(defaults: reloaded).animationStyle == style)
        }
    }

    @Test("Every motion suite reaches exact endpoints, with curved travel distinct from straight travel")
    func animationTrajectories() {
        let start = CGPoint(x: -700, y: 100), end = CGPoint(x: -200, y: 400)
        for style in MagneticAnimationStyle.allCases {
            #expect(style.progress(0) == 0 && style.progress(1) == 1)
            #expect(style.point(from: start, to: end, progress: 0) == start)
            #expect(style.point(from: start, to: end, progress: 1) == end)
            #expect(style.point(from: start, to: start, progress: 0.5) == start)
            for step in 0...100 {
                let progress = style.progress(CGFloat(step) / 100)
                #expect(progress.isFinite && (0...1).contains(progress))
            }
        }
        let straight = MagneticAnimationStyle.full.point(from: start, to: end, progress: 0.5)
        let curved = MagneticAnimationStyle.arc.point(from: start, to: end, progress: 0.5)
        #expect(hypot(curved.x - straight.x, curved.y - straight.y) > 40)
        #expect(MagneticAnimationStyle.elastic.progress(0.3) != MagneticAnimationStyle.full.progress(0.3))
    }

    @Test("New motion suites preserve fan, extraction, centering, returns and reduced motion",
          arguments: [MagneticAnimationStyle.elastic, .arc])
    func animationSuiteLifecycle(style: MagneticAnimationStyle) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticSuite-\(UUID())")
        let suite = "MagneticSuite.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        defaults.set(style.rawValue, forKey: MagneticDesktopSettings.animationStyleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { false }, pointerLocation: { CGPoint(x: -10000, y: -10000) })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        let keyWindow = NSApp.keyWindow
        controller.setCollapsed(false)
        try await waitUntil { controller.fanAnimationPanel?.isVisible == true }
        let fan = try #require(controller.fanAnimationPanel?.contentView as? MagneticPassiveHostingView<MagneticFanMotionView>)
        #expect(fan.rootView.style == style && !fan.rootView.simple)
        try await Task.sleep(for: .milliseconds(180))
        try snapshot(controller.fanAnimationPanel, to: "/private/tmp/PinboardShot-\(style.rawValue)-fan.png")
        try await waitUntil { controller.boxPanel?.isVisible == true }
        let id = try #require(store.items.first?.id)
        let rail = try #require(controller.cardPanels[id]?.frame)
        controller.extract(id)
        try await waitUntil { controller.activeFlightCount > 0 }
        let card = try #require(controller.cardPanels[id]?.contentView as? MagneticCardHostingView)
        #expect(card.rootView.motion.style == style)
        try await Task.sleep(for: .milliseconds(180))
        try snapshot(controller.cardPanels[id], to: "/private/tmp/PinboardShot-\(style.rawValue)-flight.png")
        try await waitUntil { controller.desktopPins[id] != nil && controller.activeFlightCount == 0 }
        // A real user arrangement can still be explicitly centered under either motion suite.
        try await Task.sleep(for: .milliseconds(300))
        let pin = try #require(controller.desktopPins[id])
        pin.nudge(by: CGPoint(x: -65, y: 0))
        let moved = try #require(pin.window?.frame)
        controller.centerDesktopGroup()
        try await waitUntil { pin.window?.frame != moved }
        try await Task.sleep(for: .milliseconds(300))
        #expect(pin.window?.frame.size == moved.size)
        #expect(NSApp.keyWindow === keyWindow)
        controller.returnToEdge(id)
        try await waitUntil { controller.desktopPins[id] == nil && controller.cardPanels[id]?.frame == rail
            && controller.activeFlightCount == 0 }
        controller.setCollapsed(true)
        try await waitUntil { controller.foldedPanel?.isVisible == true && controller.boxPanel?.isVisible == false }
        defaults.set(true, forKey: MagneticDesktopSettings.reduceMotionKey)
        controller.refresh()
        controller.setCollapsed(false)
        try await waitUntil { controller.boxPanel?.isVisible == true }
        #expect(controller.fanAnimationPanel?.isVisible != true)
        controller.extract(id)
        try await waitUntil { controller.desktopPins[id] != nil }
        #expect(controller.activeFlightCount == 0)
    }

    @Test("Custom motion modes preserve extraction and returns without decorative effects",
          arguments: ["simple", "reduced", "system"])
    func customMotionModes(mode: String) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticAnimation-\(UUID())")
        let suite = "MagneticAnimation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        defaults.set(1, forKey: MagneticDesktopSettings.maximumVisibleKey)
        defaults.set(mode == "simple" ? "simple" : "full", forKey: MagneticDesktopSettings.animationStyleKey)
        defaults.set(mode == "reduced", forKey: MagneticDesktopSettings.reduceMotionKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        _ = try store.add(syntheticImage(1))
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { mode == "system" }, pointerLocation: { CGPoint(x: -10000, y: -10000) })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        controller.setCollapsed(false)
        if mode == "simple" {
            try await waitUntil { controller.fanAnimationPanel?.isVisible == true }
            let fan = try #require(controller.fanAnimationPanel?.contentView as? MagneticPassiveHostingView<MagneticFanMotionView>)
            #expect(fan.rootView.simple)
        }
        try await waitUntil { controller.boxPanel?.isVisible == true && controller.cardPanels.count == 1 }
        #expect(controller.fanAnimationPanel?.isVisible != true)
        let id = try #require(store.items.first?.id)
        let railFrame = try #require(controller.cardPanels[id]?.frame)
        controller.extract(id)
        try await Task.sleep(for: .milliseconds(40))
        #expect(controller.activeFlightCount == 0 && controller.trailPanel?.isVisible != true)
        if mode == "simple" {
            let card = try #require(controller.cardPanels[id]?.contentView as? MagneticCardHostingView)
            #expect(card.rootView.motion.progress == 1)
            #expect(controller.cardPanels[id]?.frame != railFrame)
            #expect(controller.desktopPins[id] == nil)
        } else {
            #expect(controller.desktopPins[id] != nil)
        }
        try await waitUntil { controller.desktopPins[id] != nil }
        controller.returnToEdge(id)
        try await waitUntil { controller.desktopPins[id] == nil && controller.cardPanels[id]?.frame == railFrame }
        _ = try store.add(syntheticImage(2))
        try await waitUntil { controller.overflowCount == 2 && controller.cardPanels[id] == nil }
        #expect(controller.boxArrivalProgress == 1)
        let box = try #require(controller.boxPanel?.contentView as? MagneticBoxHostingView)
        #expect(!box.rootView.decorativeEffects)
        #expect(box.rootView.motionReduced == (mode != "simple"))

        // Changing a preference while running must replace the current view policy immediately.
        defaults.set("simple", forKey: MagneticDesktopSettings.animationStyleKey)
        defaults.set(true, forKey: MagneticDesktopSettings.reduceMotionKey)
        controller.refresh()
        try await waitUntil { box.rootView.motionReduced }
        controller.setCollapsed(true)
        try await waitUntil { controller.foldedPanel?.isVisible == true && controller.boxPanel?.isVisible == false }
        #expect(controller.fanAnimationPanel?.isVisible != true)
    }

    @Test("Default display cap and opt-in setting persist independently of history retention")
    func settingsPersist() throws {
        let suite = "MagneticSettingsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!MagneticDesktopSettings(defaults: defaults).isEnabled)
        #expect(MagneticDesktopSettings(defaults: defaults).maximumVisible == 10)
        #expect(!MagneticDesktopSettings(defaults: defaults).isCollapsed)
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(6, forKey: MagneticDesktopSettings.maximumVisibleKey)
        defaults.set(100, forKey: HistorySettings.maximumItemsDefaultsKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        let reloaded = try #require(UserDefaults(suiteName: suite))
        #expect(MagneticDesktopSettings(defaults: reloaded).isEnabled)
        #expect(MagneticDesktopSettings(defaults: reloaded).maximumVisible == 6)
        #expect(MagneticDesktopSettings(defaults: reloaded).isCollapsed)
        #expect(HistorySettings.maximumItems(defaults: reloaded) == 100)
    }


    @Test("One hundred screenshots remain reachable by ten-card groups, with safe location, deletion and new captures")
    func progressiveQueue() {
        var queue = MagneticDesktopQueue()
        let ids = (0..<100).map { _ in UUID() }
        queue.synchronize(ids)
        var visited: [UUID] = []
        for page in 0..<10 {
            queue.setPage(page, limit: 100)
            let partition = queue.partition(limit: 100)
            #expect(partition.visible == Array(ids[(page * 10)..<(page * 10 + 10)]))
            #expect(partition.boxed.isEmpty)
            #expect(Set(queue.fanIDs(limit: 100) + partition.boxed) == Set(ids))
            visited += partition.visible
        }
        #expect(visited == ids)
        queue.locate(ids[96], limit: 100)
        #expect(queue.pageIndex == 9 && queue.partition(limit: 100).visible.contains(ids[96]))
        queue.returnToBox(ids[96])
        queue.locate(ids[96], limit: 100)
        #expect(queue.partition(limit: 100).visible.contains(ids[96]))
        let desktop = Set(ids.prefix(3))
        queue.setPage(999, limit: 100, excluding: desktop)
        let last = queue.partition(limit: 100, excluding: desktop)
        #expect(last.visible.count == 7 && Set(last.visible + last.boxed).isDisjoint(with: desktop))
        queue.synchronize(Array(ids.prefix(35)))
        queue.setPage(queue.pageIndex, limit: 100)
        #expect(queue.pageIndex == 3 && queue.partition(limit: 100).visible.count == 5)
        let newest = UUID()
        queue.synchronize([newest] + ids)
        #expect(queue.pageIndex == 0 && queue.partition(limit: 100).visible.first == newest)
    }


    @Test("Fan capacity excludes boxed history: ten or fewer never show a pager, twenty pages only twenty")
    func fanCapacityLifecycle() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticCapacity-\(UUID())")
        let suite = "MagneticCapacityTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(10, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<25 { _ = try store.add(syntheticImage(index)) }
        let ids = store.items.map(\.id)
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, pointerLocation: { CGPoint(x: -10000, y: -10000) }, idleTimeout: 600)
        defer { controller.stop() }
        controller.start()
        try await waitUntil { Set(controller.cardPanels.keys) == Set(ids.prefix(10)) && controller.boxPanel?.isVisible == true }
        try #require(controller.railPageCount == 1 && controller.pagerPanel?.isVisible != true)
        controller.turnFanPage(1)
        try #require(controller.railPageIndex == 0 && controller.overflowCount == 15)
        defaults.set(3, forKey: MagneticDesktopSettings.maximumVisibleKey)
        controller.refresh()
        try await waitUntil { controller.cardPanels.count == 3 }
        try #require(controller.railPageCount == 1 && controller.pagerPanel?.isVisible != true)
        defaults.set(20, forKey: MagneticDesktopSettings.maximumVisibleKey)
        controller.refresh()
        try await waitUntil { controller.cardPanels.count == 10 && controller.pagerPanel?.isVisible == true }
        let pager = try #require(controller.pagerPanel)
        let hosting = try #require(pager.contentView as? NSHostingView<MagneticFanPagerView>)
        try #require(hosting.rootView.total == 20 && hosting.rootView.pageCount == 2)
        try #require(controller.overflowCount == 5)
        controller.turnFanPage(1)
        try await waitUntil { Set(controller.cardPanels.keys) == Set(ids.dropFirst(10).prefix(10))
            && controller.cardPanels.values.allSatisfy(\.isVisible) }
        let next = try #require(pager.contentView as? NSHostingView<MagneticFanPagerView>)
        try #require(next.rootView.first == 11 && next.rootView.last == 20 && next.rootView.total == 20)
        try #require(controller.overflowCount == 5)
        controller.turnFanPage(1)
        try #require(controller.railPageIndex == 1)
        // A box selection replaces one slot in the fan; it does not add another group.
        controller.toggleBox()
        let contents = try #require(controller.contentsPanel?.contentView as? MagneticBoxContentsHostingView)
        try #require(contents.rootView.items.count == 25)
        contents.rootView.onRetrieve(store.items[24])
        try await waitUntil { controller.cardPanels[ids[24]]?.isVisible == true && controller.hoverPanel?.isVisible == true }
        try #require(controller.railPageCount == 2 && controller.railPageIndex == 0 && controller.desktopPins.isEmpty)
        defaults.set(10, forKey: MagneticDesktopSettings.maximumVisibleKey)
        controller.refresh()
        try await waitUntil { !pager.isVisible && controller.cardPanels.count == 10 }
        try #require(controller.railPageCount == 1 && controller.cardPanels[ids[24]]?.isVisible == true)
        // A capacity above ten still needs enough eligible images before a switcher can appear.
        defaults.set(100, forKey: MagneticDesktopSettings.maximumVisibleKey)
        for item in Array(store.items.suffix(15)) { try store.delete(item) }
        controller.refresh(force: true)
        try await waitUntil { Set(controller.cardPanels.keys) == Set(store.items.map(\.id)) && !pager.isVisible }
        try #require(controller.railPageCount == 1 && controller.railPageIndex == 0)
    }

    @Test("Native progressive fan browses one hundred images, locates without extraction and preserves desktop pins")
    func progressiveLifecycle() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticProgressive-\(UUID())")
        let suite = "MagneticProgressiveTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(100, forKey: MagneticDesktopSettings.maximumVisibleKey)
        defaults.set(250, forKey: HistorySettings.maximumItemsDefaultsKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<100 { _ = try store.add(syntheticImage(index)) }
        let ids = store.items.map(\.id)
        try #require(ids.count == 100)
        var reducedMotion = true
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { reducedMotion }, pointerLocation: { CGPoint(x: -10000, y: -10000) }, idleTimeout: 600)
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 10 && controller.pagerPanel?.isVisible == true }
        try #require(defaults.integer(forKey: MagneticDesktopSettings.maximumVisibleKey) == 100)
        let pager = try #require(controller.pagerPanel)
        try #require(!pager.canBecomeKey && !pager.canBecomeMain)
        var visited: [UUID] = []
        for page in 0..<10 {
            if page > 0 { controller.turnFanPage(1) }
            let group = Array(ids.dropFirst(page * 10).prefix(10))
            try await waitUntil { Set(controller.cardPanels.keys) == Set(group) && controller.cardPanels.values.allSatisfy(\.isVisible) }
            try #require(controller.railPageIndex == page && controller.railPageCount == 10)
            visited += group
        }
        try #require(visited == ids)
        try await snapshotRail(controller)
        controller.toggleBox()
        let contents = try #require(controller.contentsPanel)
        let hosting = try #require(contents.contentView as? MagneticBoxContentsHostingView)
        try #require(hosting.rootView.items.count == 100 && hosting.rootView.page == 0)
        try snapshot(contents, to: "/private/tmp/PinboardShot-progressive-collection-first.png")
        hosting.rootView.onPageChange(4)
        try #require(controller.collectionPageIndex == 4 && hosting.rootView.page == 4)
        let selected = store.items[96]
        hosting.rootView.onHover(selected, true)
        try await waitUntil { controller.boxPreviewPanel?.isVisible == true }
        let preview = try #require(controller.boxPreviewPanel)
        try #require(!preview.frame.intersects(contents.frame) && preview.ignoresMouseEvents)
        try snapshot(contents, to: "/private/tmp/PinboardShot-progressive-collection-last.png")
        hosting.rootView.onRetrieve(selected)
        try await waitUntil { controller.hoverPanel?.isVisible == true && controller.railPageIndex == 9 }
        try #require(controller.desktopPins.isEmpty && !contents.isVisible && !preview.isVisible)
        let selectedView = try #require(controller.cardPanels[selected.id]?.contentView as? MagneticCardHostingView)
        try #require(selectedView.rootView.isFocused)
        controller.extract(selected.id, from: .rail)
        try await waitUntil { controller.desktopPins[selected.id] != nil && controller.activeFlightCount == 0 }
        let pin = try #require(controller.desktopPins[selected.id])
        let pose = try #require(pin.window?.frame)
        reducedMotion = false
        controller.turnFanPage(-1)
        controller.turnFanPage(-1)
        let seventhGroup = Set(ids.dropFirst(70).prefix(10) + [selected.id])
        try await waitUntil { controller.railPageIndex == 7 && Set(controller.cardPanels.keys) == seventhGroup
            && controller.cardPanels.values.allSatisfy { $0.isVisible && $0.alphaValue == 1 } }
        reducedMotion = true
        try #require(pin.window?.frame == pose && pin.window?.isVisible == true)
        try #require(controller.cardPanels.keys.filter { controller.desktopPins[$0] == nil }.count == 10)
        controller.toggleBox()
        try #require(!hosting.rootView.items.contains { $0.id == selected.id })
        controller.suspendForCapture()
        try #require(!pager.isVisible && !contents.isVisible)
        controller.resumeAfterCapture()
        try await waitUntil { pager.isVisible && contents.isVisible }
        controller.closeBox()
        let added = try store.add(syntheticImage(101))
        let newest = try #require(added)
        try await waitUntil { controller.railPageIndex == 0 && controller.cardPanels[newest.id]?.isVisible == true }
        try #require(pin.window?.frame == pose)
        controller.setCollapsed(true)
        try await waitUntil { controller.foldedPanel?.isVisible == true && !pager.isVisible }
        try #require(controller.desktopPins.isEmpty)
        controller.setCollapsed(false)
        try await waitUntil { pager.isVisible && controller.boxPanel?.isVisible == true }
        controller.turnFanPage(99)
        try await waitUntil { controller.railPageIndex == 9 && Set(controller.cardPanels.keys) == Set(store.items.dropFirst(90).prefix(10).map(\.id))
            && controller.cardPanels.values.allSatisfy(\.isVisible) }
        for item in Array(store.items.suffix(25)) { try store.delete(item) }
        try await waitUntil { controller.railPageIndex == 7 && Set(controller.cardPanels.keys) == Set(store.items.dropFirst(70).map(\.id))
            && controller.cardPanels.values.allSatisfy(\.isVisible) }
        try #require(controller.railPageCount == 8)
        try #require(controller.cardPanels.values.allSatisfy { $0.alphaValue == 1 })
    }

    @Test("Queue conserves every screenshot across cap changes, retrieval and new captures")
    func queueConservesImages() {
        var queue = MagneticDesktopQueue()
        var ids = (0..<37).map { _ in UUID() }
        queue.synchronize(ids)
        for limit in [10, 3, 30, 1, 10] {
            let result = queue.partition(limit: limit)
            #expect(result.visible == Array(ids.prefix(min(limit, 10))))
            #expect(Set(result.visible).isDisjoint(with: result.boxed))
            #expect(queue.fanIDs(limit: limit) + result.boxed == ids)
            let retrieved = ids.last!
            queue.retrieve(retrieved)
            let changed = queue.partition(limit: limit)
            #expect(changed.visible.first == retrieved)
            #expect(changed.visible.count == min(limit, 10))
            #expect(Set(queue.fanIDs(limit: limit) + changed.boxed) == Set(ids))
            queue.returnToEdge()
        }
        queue.retrieve(ids.last!)
        // OCR-only publication must not reset manual retrieval; a new screenshot must.
        queue.synchronize(ids)
        #expect(queue.partition(limit: 10).visible.first == ids.last)
        ids.insert(UUID(), at: 0)
        queue.synchronize(ids)
        #expect(queue.partition(limit: 10).visible == Array(ids.prefix(10)))
        queue.retrieve(ids.last!)
        ids.removeLast()
        queue.synchronize(ids)
        #expect(Set(queue.partition(limit: 10).visible + queue.partition(limit: 10).boxed) == Set(ids))
        queue.synchronize([])
        #expect(queue.partition(limit: 10).visible.isEmpty)
        #expect(queue.partition(limit: 10).boxed.isEmpty)
    }

    @Test("Returned screenshots keep their source across refreshes and display cap changes")
    func returnSources() {
        let ids = (0..<8).map { _ in UUID() }
        var queue = MagneticDesktopQueue()
        queue.synchronize(ids)
        queue.returnToRail(ids[6])
        queue.returnToRail(ids[7])
        queue.returnToBox(ids[0])
        queue.synchronize(ids)
        #expect(queue.partition(limit: 2).visible == [ids[7], ids[6]])
        let expanded = queue.partition(limit: 30)
        #expect(expanded.boxed == [ids[0]])
        #expect(Set(expanded.visible + expanded.boxed) == Set(ids))
        queue.retrieve(ids[0])
        #expect(queue.partition(limit: 30).boxed.isEmpty)
        queue.synchronize(Array(ids.dropLast()))
        #expect(!queue.partition(limit: 30).visible.contains(ids[7]))
    }

    @Test("Placement avoids existing cards and fixed obstacles, then shrinks crowded groups without overlap")
    func nonoverlappingPlacement() throws {
        let bounds = CGRect(x: -400, y: 40, width: 1300, height: 800)
        let fixed = CGRect(x: -400, y: 40, width: 160, height: 130)
        var occupied = [fixed]
        for _ in 0..<6 {
            let pose = try #require(MagneticDesktopPlacement.frame(size: CGSize(width: 350, height: 200),
                near: CGPoint(x: bounds.midX, y: bounds.midY), occupied: occupied, in: bounds))
            #expect(bounds.contains(pose))
            #expect(occupied.allSatisfy { !pose.intersects($0.insetBy(dx: -12, dy: -12)) })
            occupied.append(pose)
        }
        let crowded = Dictionary(uniqueKeysWithValues: (0..<8).map { _ in
            (UUID(), CGRect(x: 180, y: 100, width: 640, height: 480))
        })
        let small = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let blocker = CGRect(x: 0, y: 0, width: 150, height: 120)
        let packed = try #require(MagneticDesktopPlacement.reflow(crowded, fixed: [blocker], in: small))
        #expect(packed.count == 8)
        for (id, pose) in packed {
            #expect(small.contains(pose))
            #expect(pose.width >= 80 && pose.height >= 60)
            #expect(abs(pose.width / pose.height - 4 / 3) < 0.02)
            #expect(!pose.intersects(blocker.insetBy(dx: -12, dy: -12)))
            #expect(packed.allSatisfy { $0.key == id || !pose.intersects($0.value.insetBy(dx: -12, dy: -12)) })
        }
        #expect(MagneticDesktopPlacement.frame(size: CGSize(width: 80, height: 60),
            near: .zero, occupied: [small], in: small) == nil)
        #expect(MagneticDesktopPlacement.reflow(crowded, fixed: [small], in: small) == nil)
    }

    @Test("Group centering preserves every relative position and size, avoids obstacles and rejects an impossible fit")
    func groupCenterGeometry() throws {
        let first = UUID(), second = UUID()
        let input = [first: CGRect(x: -600, y: 150, width: 220, height: 130),
                     second: CGRect(x: -300, y: 240, width: 140, height: 210)]
        let bounds = CGRect(x: -900, y: -200, width: 1400, height: 1000)
        func group(_ frames: [UUID: CGRect]) -> CGRect { frames.values.reduce(CGRect.null) { $0.union($1) } }
        let centered = try #require(MagneticDesktopPlacement.centeredGroup(input, fixed: [], in: bounds))
        #expect(group(centered).midX == bounds.midX && group(centered).midY == bounds.midY)
        let dx = centered[first]!.minX - input[first]!.minX
        let dy = centered[first]!.minY - input[first]!.minY
        for id in input.keys {
            #expect(centered[id]!.size == input[id]!.size)
            #expect(centered[id]!.minX - input[id]!.minX == dx)
            #expect(centered[id]!.minY - input[id]!.minY == dy)
            #expect(bounds.contains(centered[id]!))
        }
        let obstacle = CGRect(x: bounds.midX - 50, y: bounds.midY - 50, width: 100, height: 100)
        let avoiding = try #require(MagneticDesktopPlacement.centeredGroup(input, fixed: [obstacle], in: bounds))
        #expect(!group(avoiding).intersects(obstacle.insetBy(dx: -12, dy: -12)))
        #expect(avoiding[first]!.minX - input[first]!.minX == avoiding[second]!.minX - input[second]!.minX)
        #expect(avoiding[first]!.minY - input[first]!.minY == avoiding[second]!.minY - input[second]!.minY)
        #expect(MagneticDesktopPlacement.centeredGroup(input, fixed: [bounds], in: bounds) == nil)
        #expect(MagneticDesktopPlacement.centeredGroup(input, fixed: [], in: CGRect(x: 0, y: 0, width: 100, height: 100)) == nil)
        #expect(MagneticDesktopPlacement.centeredGroup([:], fixed: [], in: bounds) == nil)
    }

    @Test("Desktop groups center after flights, preserve manual and locked layouts and expose an explicit menu action")
    func desktopGroupCentering() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticCenter-\(UUID())")
        let suite = "MagneticCenterTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(2, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<7 { _ = try store.add(syntheticImage(index)) }
        let ids = store.items.map(\.id)
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { false },
            pointerLocation: { CGPoint(x: -10000, y: -10000) })
        defer { controller.stop() }
        let screen = try #require(NSScreen.screens.first?.visibleFrame)
        let center = CGPoint(x: screen.minX + 16 + (screen.width - MagneticDesktopGeometry.cardSize.width - 40) / 2,
                             y: screen.midY)
        func frames() -> [UUID: CGRect] { controller.desktopPins.compactMapValues { $0.window?.frame } }
        func settledAtCenter(_ count: Int) -> Bool {
            let poses = frames()
            let group = poses.values.reduce(CGRect.null) { $0.union($1) }
            return poses.count == count && controller.activeFlightCount == 0
                && abs(group.midX - center.x) <= 1 && abs(group.midY - center.y) <= 1
                && poses.allSatisfy { controller.desktopFrames[$0.key] == $0.value }
        }
        func menu(for pin: PinWindowController) throws -> (NSMenu, PinImageView) {
            let window = try #require(pin.window)
            let view = try #require(window.contentView as? PinImageView)
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            return (try #require(view.menu(for: event)), view)
        }
        controller.start()
        try await waitUntil { controller.boxPanel?.isVisible == true }
        for (index, id) in ids.prefix(2).enumerated() {
            controller.extract(id)
            try await waitUntil { settledAtCenter(index + 1) }
        }
        let first = try #require(controller.desktopPins[ids[0]])
        let beforeReturn = try #require(first.window?.frame)
        let keyWindow = NSApp.keyWindow
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        controller.returnToEdge(ids[1])
        try await waitUntil { controller.activeFlightCount > 0 }
        #expect(first.window?.frame == beforeReturn)
        try await waitUntil { settledAtCenter(1) }
        #expect(NSApp.keyWindow === keyWindow)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
        #expect(first.window?.level == .normal)

        controller.extract(ids[1])
        try await waitUntil { settledAtCenter(2) }
        first.nudge(by: CGPoint(x: -80, y: -35))
        let manuallyPlaced = try #require(first.window?.frame)
        controller.returnToEdge(ids[1])
        try await waitUntil { controller.cardPanels[ids[1]]?.level == .floating && controller.activeFlightCount == 0 }
        #expect(first.window?.frame == manuallyPlaced)
        controller.extract(ids[2])
        try await waitUntil { controller.desktopPins[ids[2]] != nil && controller.activeFlightCount == 0 }
        #expect(first.window?.frame == manuallyPlaced)
        let beforeExplicit = frames()
        let (centerMenu, centerView) = try menu(for: first)
        let centerIndex = try #require(centerMenu.items.firstIndex { $0.title == L10n.text("magnetic.centerGroup") })
        #expect(centerMenu.items[centerIndex].isEnabled && centerView.validateMenuItem(centerMenu.items[centerIndex]))
        centerMenu.performActionForItem(at: centerIndex)
        try await waitUntil { settledAtCenter(2) }
        let afterExplicit = frames()
        let delta = CGPoint(x: afterExplicit[ids[0]]!.minX - beforeExplicit[ids[0]]!.minX,
                            y: afterExplicit[ids[0]]!.minY - beforeExplicit[ids[0]]!.minY)
        for id in beforeExplicit.keys {
            #expect(afterExplicit[id]!.size == beforeExplicit[id]!.size)
            #expect(abs(afterExplicit[id]!.minX - beforeExplicit[id]!.minX - delta.x) < 1)
            #expect(abs(afterExplicit[id]!.minY - beforeExplicit[id]!.minY - delta.y) < 1)
        }
        #expect(NSApp.keyWindow === keyWindow)
        let manualAfterCenter = try #require(first.window?.frame)
        controller.returnToEdge(ids[2])
        try await waitUntil { controller.cardPanels[ids[2]]?.level == .floating && controller.activeFlightCount == 0 }
        #expect(first.window?.frame == manualAfterCenter)
        first.togglePositionLock()
        controller.extract(ids[3])
        try await waitUntil { controller.desktopPins[ids[3]] != nil && controller.activeFlightCount == 0 }
        #expect(first.window?.frame == manualAfterCenter)
        let (lockedMenu, lockedView) = try menu(for: try #require(controller.desktopPins[ids[3]]))
        let lockedCenter = try #require(lockedMenu.items.first { $0.title == L10n.text("magnetic.centerGroup") })
        #expect(!lockedCenter.isEnabled && !lockedView.validateMenuItem(lockedCenter))
        let lockedFrames = frames()
        controller.centerDesktopGroup()
        try await Task.sleep(for: .milliseconds(220))
        #expect(frames() == lockedFrames)
        first.togglePositionLock()
        controller.returnAllToEdge()
        try await waitUntil { controller.desktopPins.isEmpty && controller.activeFlightCount == 0 }
        controller.extract(ids[0])
        try await waitUntil { settledAtCenter(1) }
        let fresh = try #require(controller.desktopPins[ids[0]])
        fresh.nudge(by: CGPoint(x: -100, y: -20))
        let shifted = try #require(fresh.window?.frame)
        controller.centerDesktopGroup()
        try await waitUntil { fresh.window?.frame != shifted }
        // A new user gesture must cancel an in-progress group animation before applying its own geometry.
        fresh.nudge(by: CGPoint(x: -40, y: 0))
        let interrupted = try #require(fresh.window?.frame)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fresh.window?.frame == interrupted)
        controller.centerDesktopGroup()
        try await waitUntil { fresh.window?.frame != interrupted }
        fresh.togglePositionLock()
        let lockedDuringAnimation = try #require(fresh.window?.frame)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fresh.window?.frame == lockedDuringAnimation)
        fresh.togglePositionLock()
        let fullArea = CGRect(x: screen.minX + 16, y: screen.minY + 16,
            width: screen.width - MagneticDesktopGeometry.cardSize.width - 40, height: screen.height - 32)
        fresh.window?.setFrame(fullArea, display: true)
        fresh.onSourceGeometryChanged?()
        let fullManualPose = try #require(fresh.window?.frame)
        controller.extract(ids[6])
        #expect(controller.desktopPins.count == 1 && controller.desktopFrames.count == 1)
        #expect(fresh.window?.frame == fullManualPose)
    }

    @Test("Cards, photo box and expanded reference remain inside display safe areas")
    func screenSafeAreas() {
        for frame in [CGRect(x: 0, y: 70, width: 1440, height: 805),
                      CGRect(x: -1024, y: -600, width: 1024, height: 550),
                      CGRect(x: 0, y: 0, width: 320, height: 480)] {
            #expect(frame.contains(MagneticDesktopGeometry.boxFrame(in: frame)))
            #expect(frame.contains(MagneticDesktopGeometry.foldedFrame(in: frame)))
            for count in [1, 10, 30] {
                let cards = MagneticDesktopGeometry.cardFrames(count: count, in: frame)
                #expect(cards.count == count)
                #expect(cards.allSatisfy { frame.contains($0) })
            }
            let reference = MagneticDesktopGeometry.expandedFrame(
                imageSize: CGSize(width: 200, height: 6000), near: CGPoint(x: frame.maxX + 100, y: frame.minY - 200), in: frame)
            #expect(frame.contains(reference))
        }
    }

    @Test("Rail previews sit beside the whole fan and leave every card unobscured")
    func railPreviewBesideFan() {
        for screen in [CGRect(x: 0, y: 70, width: 1440, height: 805),
                       CGRect(x: -1024, y: -600, width: 1024, height: 550),
                       CGRect(x: 0, y: 0, width: 320, height: 480)] {
            for count in [1, 10, 30] {
                let cards = MagneticDesktopGeometry.cardFrames(count: count, in: screen)
                let bounds = cards.dropFirst().reduce(cards[0]) { $0.union($1) }
                let previews = cards.map { MagneticDesktopGeometry.hoverFrame(for: $0, beside: cards, in: screen) }
                if bounds.minX - screen.minX <= 12 {
                    #expect(previews.allSatisfy { $0.isEmpty })
                } else {
                    #expect(previews.allSatisfy { screen.contains($0) })
                    #expect(previews.allSatisfy { $0.maxX <= bounds.minX - 12 })
                    #expect(previews.allSatisfy { preview in cards.allSatisfy { !preview.intersects($0) } })
                    #expect(previews.allSatisfy { $0.maxX == previews[0].maxX })
                }
            }
        }
    }

    @Test("Compact rail groups center vertically and spread out without covering the photo box")
    func centeredCardGroups() {
        let frame = CGRect(x: 0, y: 40, width: 1440, height: 1000)
        let box = MagneticDesktopGeometry.boxFrame(in: frame)
        for count in [1, 2, 3, 4, 10] {
            let cards = MagneticDesktopGeometry.cardFrames(count: count, in: frame)
            let bounds = cards.dropFirst().reduce(cards[0]) { $0.union($1) }
            #expect(abs(bounds.midY - frame.midY) <= 1)
            #expect(cards.allSatisfy { $0.size == cards[0].size && $0.width <= MagneticDesktopGeometry.cardSize.width })
            if count <= 4 { #expect(cards[0].size == MagneticDesktopGeometry.cardSize) }
            #expect(bounds.minY >= box.maxY + 52)
            for pair in zip(cards, cards.dropFirst()) {
                let step = pair.0.minY - pair.1.minY
                #expect(pair.0.minY - pair.1.maxY >= 5)
                if count <= 4 { #expect(step == 86) }
            }
        }
        // Dense layouts can shift upward, but every column remains centered within its safe bounds.
        let small = CGRect(x: -600, y: -200, width: 600, height: 480)
        let cards = MagneticDesktopGeometry.cardFrames(count: 30, in: small)
        #expect(cards.allSatisfy { small.contains($0) && !$0.intersects(MagneticDesktopGeometry.boxFrame(in: small)) })
        let layouts = MagneticDesktopGeometry.cardLayouts(count: 30, in: small)
        let columns = Dictionary(grouping: layouts, by: \.column).mapValues { $0.map(\.frame) }
        #expect(columns.count > 1)
        for column in columns.values {
            let bounds = column.dropFirst().reduce(column[0]) { $0.union($1) }
            let lower = MagneticDesktopGeometry.boxFrame(in: small).maxY + 52
            let ideal = min(max(small.midY, lower + bounds.height / 2), small.maxY - 12 - bounds.height / 2)
            #expect(abs(bounds.midY - ideal) <= 1)
        }
    }

    @Test("Shallow fan opens left with restrained angles and visible gaps when space permits")
    func shallowFan() {
        let screen = CGRect(x: -600, y: -200, width: 1440, height: 1280)
        let layouts = MagneticDesktopGeometry.cardLayouts(count: 10, in: screen)
        #expect(layouts.count == 10)
        #expect(layouts[0].frame.minX == layouts[9].frame.minX)
        #expect(layouts[4].frame.minX < layouts[0].frame.minX)
        #expect(layouts[0].frame.minX - layouts[4].frame.minX <= 48)
        #expect(layouts.first?.angle == 7 && layouts.last?.angle == -7)
        #expect(layouts.allSatisfy { abs($0.angle) <= 7 && screen.contains($0.frame) })
        for pair in zip(layouts, layouts.dropFirst()) {
            #expect(pair.0.frame.minY - pair.1.frame.maxY >= 10)
        }
        #expect(MagneticDesktopGeometry.cardLayouts(count: 3, in: screen).allSatisfy { abs($0.angle) <= 3.15 })
        let shorter = CGRect(x: 0, y: 30, width: 1440, height: 850)
        let compact = MagneticDesktopGeometry.cardLayouts(count: 10, in: shorter)
        for pair in zip(compact, compact.dropFirst()) { #expect(pair.0.frame.minY - pair.1.frame.maxY >= 5) }
        #expect(compact[0].frame.size.width < MagneticDesktopGeometry.cardSize.width)
    }

    @Test("Box wheel events scroll its document and remain contained at both ends and over padding")
    func nativeBoxScrollContainment() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticNative-\(UUID())")
        let suite = "MagneticNativeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(1, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<22 { _ = try store.add(syntheticImage(index)) }
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { true })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.boxPanel?.isVisible == true }
        controller.toggleBox()
        let panel = try #require(controller.contentsPanel)
        let hosting = try #require(panel.contentView as? MagneticBoxContentsHostingView)
        // A short screen still needs contained scrolling even though normal pages fit twenty thumbnails.
        panel.setContentSize(CGSize(width: 540, height: 260))
        hosting.layoutSubtreeIfNeeded()
        func scrollView(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView($0) }.first
        }
        try await waitUntil { scrollView(hosting)?.documentView?.bounds.height ?? 0 > panel.frame.height }
        let scroll = try #require(scrollView(hosting))
        let document = try #require(scroll.documentView)
        let sink = MagneticScrollSink()
        let originalNext = hosting.nextResponder
        hosting.nextResponder = sink
        defer { hosting.nextResponder = originalNext }
        func wheel(_ delta: Int32, horizontal: Bool = false) throws -> NSEvent {
            let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 2, wheel1: horizontal ? 0 : delta, wheel2: horizontal ? delta : 0, wheel3: 0))
            cg.location = CGPoint(x: panel.frame.midX, y: panel.frame.minY + 4)
            return try #require(NSEvent(cgEvent: cg))
        }
        let start = scroll.contentView.bounds.origin.y
        panel.sendEvent(try wheel(-120))
        try await waitUntil { scroll.contentView.bounds.origin.y > start }
        document.scroll(CGPoint(x: 0, y: document.bounds.height))
        for _ in 0..<4 { panel.sendEvent(try wheel(-120)) }
        document.scroll(.zero)
        for _ in 0..<4 { hosting.scrollWheel(with: try wheel(120)) }
        panel.sendEvent(try wheel(-120, horizontal: true))
        #expect(sink.received == 0)
        controller.refresh(force: true)
        try await waitUntil { controller.boxPanel?.isVisible == true }
        #expect(panel.contentView === hosting)
        controller.toggleBox()
        // Empty state has no scroll view, but must still swallow wheel events.
        hosting.rootView = MagneticBoxContents(items: [], historyStore: store, onRetrieve: { _ in }, onHover: { _, _ in }, onClose: {})
        hosting.layoutSubtreeIfNeeded()
        hosting.scrollWheel(with: try wheel(-120))
        #expect(sink.received == 0)
    }

    @Test("Tray and contents stay above rail windows without becoming keyboard windows")
    func passiveBoxWindowLevels() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticLevels-\(UUID())")
        let suite = "MagneticLevelsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(2, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<4 { _ = try store.add(syntheticImage(index)) }
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { true })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.boxPanel?.isVisible == true }
        let tray = try #require(controller.boxPanel)
        let rail = try #require(controller.cardPanels[store.items[0].id])
        #expect(tray.level.rawValue > rail.level.rawValue)
        #expect(!tray.canBecomeKey && !rail.canBecomeKey)
        controller.toggleBox()
        let contents = try #require(controller.contentsPanel)
        #expect(contents.level.rawValue > tray.level.rawValue)
        #expect(!contents.canBecomeKey)
        rail.orderFrontRegardless()
        #expect(contents.level.rawValue > rail.level.rawValue)
        controller.setCollapsed(true)
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        let folded = try #require(controller.foldedPanel)
        #expect(!folded.canBecomeKey && !folded.canBecomeMain)
        let competingPanel = NSPanel(contentRect: folded.frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        competingPanel.level = .popUpMenu
        defer { competingPanel.orderOut(nil) }
        competingPanel.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(50))
        let windows = try #require(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]])
        let foldedIndex = try #require(windows.firstIndex { ($0[kCGWindowNumber as String] as? Int) == folded.windowNumber })
        let competingIndex = try #require(windows.firstIndex { ($0[kCGWindowNumber as String] as? Int) == competingPanel.windowNumber })
        #expect(foldedIndex < competingIndex)
    }

    @Test("Box hover previews switch safely, stay passive and disappear on outside click, close and capture")
    func boxHoverAndDismissal() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticBoxHover-\(UUID())")
        let suite = "MagneticBoxHoverTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(2, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<6 { _ = try store.add(syntheticImage(index)) }
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { true },
            pointerLocation: { CGPoint(x: -10000, y: -10000) })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.boxPanel?.isVisible == true }
        controller.toggleBox()
        let contents = try #require(controller.contentsPanel)
        let hosting = try #require(contents.contentView as? MagneticBoxContentsHostingView)
        let first = try #require(hosting.rootView.items.first)
        let second = try #require(hosting.rootView.items.last)
        hosting.rootView.onHover(first, true)
        try await waitUntil { controller.boxPreviewPanel?.isVisible == true }
        let preview = try #require(controller.boxPreviewPanel)
        #expect(preview.ignoresMouseEvents && !preview.canBecomeKey)
        #expect(preview.level.rawValue > contents.level.rawValue)
        let screen = try #require(NSScreen.screens.first?.visibleFrame)
        #expect(screen.contains(preview.frame))
        #expect(preview.frame.width > 130 && preview.frame.height > 90)
        #expect(controller.hoverPanel?.isVisible != true)
        hosting.rootView.onHover(second, true)
        hosting.rootView.onHover(first, false)
        try await waitUntil { preview.isVisible }
        #expect((preview.contentView as? NSImageView)?.image != nil)
        controller.handleBoxClick(at: CGPoint(x: contents.frame.midX, y: contents.frame.midY))
        #expect(contents.isVisible && preview.isVisible)
        let tray = try #require(controller.boxPanel)
        controller.handleBoxClick(at: CGPoint(x: tray.frame.midX, y: tray.frame.midY))
        #expect(contents.isVisible)
        controller.handleBoxClick(at: CGPoint(x: -10000, y: -10000))
        #expect(!contents.isVisible && !preview.isVisible)
        // A late thumbnail completion must never reopen a preview after dismissal.
        controller.toggleBox()
        hosting.rootView.onHover(first, true)
        hosting.rootView.onClose()
        try await Task.sleep(for: .milliseconds(80))
        #expect(!contents.isVisible && !preview.isVisible)
        controller.toggleBox()
        hosting.rootView.onHover(first, true)
        try await waitUntil { preview.isVisible }
        controller.suspendForCapture()
        #expect(!contents.isVisible && !preview.isVisible)
        controller.resumeAfterCapture()
        try await waitUntil { contents.isVisible }
        #expect(!preview.isVisible)
        hosting.rootView.onHover(first, true)
        try await waitUntil { preview.isVisible }
        hosting.rootView.onRetrieve(first)
        #expect(!contents.isVisible && !preview.isVisible)
    }

    @Test("Native outside clicks dismiss the box and reach the original window without activation",
        .enabled(if: ProcessInfo.processInfo.environment["PINBOARDSHOT_NATIVE_MENU_SMOKE"] == "1"))
    func nativeBoxClickForwarding() async throws {
        let app = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticClick-\(UUID())")
        let suite = "MagneticClickTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(2, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<5 { _ = try store.add(syntheticImage(index)) }
        var now: TimeInterval = 0
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { true },
            pointerLocation: { CGPoint(x: -10000, y: -10000) }, idleClock: { now })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.boxPanel?.isVisible == true }
        let id = try #require(store.items.first?.id)
        controller.extract(id)
        try await waitUntil { controller.desktopPins[id] != nil }
        let target = MagneticClickProbeWindow(contentRect: CGRect(x: 250, y: 300, width: 480, height: 260),
            styleMask: [.titled], backing: .buffered, defer: false)
        target.isReleasedWhenClosed = false
        defer { target.close() }
        target.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 480, height: 260))
        target.orderFrontRegardless()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let keyWindow = app.keyWindow
        controller.toggleBox()
        let contents = try #require(controller.contentsPanel)
        let hosting = try #require(contents.contentView as? MagneticBoxContentsHostingView)
        let boxed = try #require(hosting.rootView.items.first)
        hosting.rootView.onHover(boxed, true)
        try await waitUntil { controller.boxPreviewPanel?.isVisible == true }
        try #require(!contents.canBecomeKey && controller.boxPreviewPanel?.canBecomeKey == false)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 30, y: 30),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: target.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        app.sendEvent(click)
        try #require(target.receivedClick === click)
        try #require(!contents.isVisible && controller.boxPreviewPanel?.isVisible == false)
        now = 61
        controller.checkForIdleCollapse()
        try await waitUntil { controller.foldedPanel?.isVisible == true && controller.boxPanel?.isVisible == false }
        try #require(app.keyWindow === keyWindow)
        try #require(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
    }

    @Test("Local idle folding ignores unrelated movement, resets on tray activity and keeps desktop pins")
    func localIdleFolding() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticNative-\(UUID())")
        let suite = "MagneticNativeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(3, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<7 { _ = try store.add(syntheticImage(index)) }
        var now: TimeInterval = 0
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, idleClock: { now })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.boxPanel?.isVisible == true }
        let id = try #require(store.items.first?.id)
        controller.extract(id)
        try await waitUntil { controller.desktopPins[id] != nil }
        let pin = try #require(controller.desktopPins[id])
        let pose = try #require(pin.window?.frame)
        controller.toggleBox()
        now = 59
        controller.updateHover(at: CGPoint(x: -10000, y: -10000))
        controller.checkForIdleCollapse()
        #expect(!MagneticDesktopSettings(defaults: defaults).isCollapsed)
        let tray = try #require(controller.boxPanel)
        controller.updateHover(at: CGPoint(x: tray.frame.midX, y: tray.frame.midY))
        now = 118
        controller.checkForIdleCollapse()
        #expect(!MagneticDesktopSettings(defaults: defaults).isCollapsed)
        now = 119
        controller.checkForIdleCollapse()
        try await waitUntil { controller.foldedPanel?.isVisible == true && controller.boxPanel?.isVisible == false }
        #expect(controller.contentsPanel?.isVisible == false)
        #expect(controller.hoverPanel?.isVisible != true)
        #expect(controller.desktopPins[id] === pin && pin.window?.isVisible == true && pin.window?.frame == pose)
        controller.suspendForCapture()
        #expect(pin.window?.isVisible == false)
        controller.resumeAfterCapture()
        try await waitUntil { controller.foldedPanel?.isVisible == true && pin.window?.isVisible == true }
        #expect(pin.window?.frame == pose)
        controller.setCollapsed(false)
        try await waitUntil { controller.boxPanel?.isVisible == true }
        #expect(controller.desktopPins[id] === pin && controller.desktopFrames[id] == pose)
        controller.returnToEdge(id)
        try await waitUntil { controller.desktopPins.isEmpty && controller.cardPanels[id]?.level == .floating }
        // Capture suspends the idle clock; resuming provides a fresh minute.
        controller.suspendForCapture()
        now = 1000
        controller.checkForIdleCollapse()
        #expect(!MagneticDesktopSettings(defaults: defaults).isCollapsed)
        controller.resumeAfterCapture()
        try await waitUntil { controller.boxPanel?.isVisible == true }
        now = 1059
        controller.checkForIdleCollapse()
        #expect(!MagneticDesktopSettings(defaults: defaults).isCollapsed)
        now = 1060
        controller.checkForIdleCollapse()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
    }

    @Test("Idle timer folds automatically and is rearmed after unfolding")
    func automaticIdleTimer() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticNative-\(UUID())")
        let suite = "MagneticNativeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, pointerLocation: { CGPoint(x: -10000, y: -10000) }, idleTimeout: 0.15)
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.boxPanel?.isVisible == true }
        try await waitUntil { controller.foldedPanel?.isVisible == true && controller.boxPanel?.isVisible == false }
        controller.setCollapsed(false)
        try await waitUntil { controller.boxPanel?.isVisible == true }
        try await waitUntil { controller.foldedPanel?.isVisible == true && controller.boxPanel?.isVisible == false }
    }

    @Test("Native panels respect cap changes, retrieval, capture suspension and history deletion")
    func nativeLifecycle() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticNative-\(UUID())")
        let suite = "MagneticNativeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(50, forKey: HistorySettings.maximumItemsDefaultsKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<14 { _ = try store.add(syntheticImage(index)) }
        let originalIDs = store.items.map(\.id)
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { true })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 10 && controller.boxPanel?.isVisible == true }
        #expect(controller.overflowCount == 4)
        #expect(Set(controller.cardPanels.keys) == Set(originalIDs.prefix(10)))
        try await snapshotRail(controller)
        try snapshot(controller.boxPanel, to: "/private/tmp/PinboardShot-magnetic-box-smoke.png")
        try snapshot(controller.cardPanels[originalIDs[0]], to: "/private/tmp/PinboardShot-magnetic-compact-smoke.png")

        defaults.set(5, forKey: MagneticDesktopSettings.maximumVisibleKey)
        controller.refresh()
        try await waitUntil { controller.cardPanels.count == 5 }
        #expect(controller.overflowCount == 9)
        controller.toggleBox()
        #expect(controller.contentsPanel?.isVisible == true)
        controller.suspendForCapture()
        #expect(controller.contentsPanel?.isVisible == false)
        controller.resumeAfterCapture()
        try await waitUntil { controller.contentsPanel?.isVisible == true }
        try await Task.sleep(for: .milliseconds(500))
        try snapshot(controller.contentsPanel, to: "/private/tmp/PinboardShot-magnetic-contents-smoke.png")
        let oldest = try #require(store.items.last)
        controller.extract(oldest.id)
        try await waitUntil { controller.cardPanels[oldest.id] != nil && controller.cardPanels.count == 6 }
        #expect(controller.overflowCount == 8)
        #expect(controller.contentsPanel?.isVisible == false)
        #expect(store.items.map(\.id) == originalIDs)
        try snapshot(controller.cardPanels[oldest.id], to: "/private/tmp/PinboardShot-magnetic-card-smoke.png")

        controller.suspendForCapture()
        #expect(controller.cardPanels.values.allSatisfy { !$0.isVisible })
        #expect(controller.boxPanel?.isVisible == false)
        _ = try store.add(syntheticImage(15))
        try await Task.sleep(for: .milliseconds(80))
        #expect(controller.cardPanels.values.allSatisfy { !$0.isVisible })
        controller.resumeAfterCapture()
        try await waitUntil { Set(controller.cardPanels.keys) == Set(store.items.prefix(5).map(\.id) + [oldest.id]) }
        #expect(controller.cardPanels.values.allSatisfy { $0.isVisible })
        #expect(controller.overflowCount == 9)

        defaults.set(30, forKey: MagneticDesktopSettings.maximumVisibleKey)
        controller.refresh()
        try await waitUntil { controller.cardPanels.count == 11 }
        #expect(controller.overflowCount == 0)
        try store.delete(oldest)
        try await waitUntil { controller.cardPanels.count == 10 }
        #expect(controller.cardPanels[oldest.id] == nil)
        defaults.set(false, forKey: HistorySettings.enabledDefaultsKey)
        controller.refresh()
        #expect(controller.cardPanels.isEmpty)
        #expect(controller.boxPanel == nil)
        #expect(store.items.count == 14)
        defaults.set(true, forKey: HistorySettings.enabledDefaultsKey)
        controller.refresh()
        try await waitUntil { controller.cardPanels.count == 10 }
        defaults.set(false, forKey: MagneticDesktopSettings.enabledKey)
        controller.refresh()
        #expect(controller.cardPanels.isEmpty)
        #expect(store.items.count == 14)
    }

    @Test("Inactive-panel hover and desktop extraction animate through intermediate frames")
    func hoverAndZoomAnimation() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticMotion-\(UUID())")
        let suite = "MagneticMotionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(1, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(1))
        _ = try store.add(syntheticImage(2))
        var reduceMotion = false
        var pointer = CGPoint(x: -10000, y: -10000)
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { reduceMotion }, pointerLocation: { pointer })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 1 && controller.boxPanel?.isVisible == true }
        let id = try #require(store.items.first?.id)
        let panel = try #require(controller.cardPanels[id])
        let hosting = try #require(panel.contentView as? MagneticCardHostingView)
        hosting.updateTrackingAreas()
        #expect(hosting.trackingAreas.contains { $0.options.contains(.activeAlways) })
        let originalFrame = panel.frame
        pointer = CGPoint(x: originalFrame.midX, y: originalFrame.midY)
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        #expect(hosting.acceptsFirstMouse(for: event))
        hosting.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(40))
        let preview = try #require(controller.hoverPanel)
        #expect(preview.ignoresMouseEvents)
        #expect(preview.frame.width > originalFrame.width)
        #expect(preview.frame.width < 210)
        #expect(!preview.frame.intersects(originalFrame))
        #expect(preview.frame.maxX <= originalFrame.minX - 11)
        #expect(panel.frame == originalFrame)
        try await waitUntil { preview.frame.width == 210 }
        pointer = CGPoint(x: -10000, y: -10000)
        hosting.mouseExited(with: event)
        try await waitUntil { !preview.isVisible }

        controller.extract(id)
        try await Task.sleep(for: .milliseconds(40))
        #expect(panel.frame.width > originalFrame.width)
        #expect(panel.frame.width < 420)
        try await waitUntil { controller.desktopPins[id] != nil }
        let pinPanel = try #require(controller.cardPanels[id])
        #expect(pinPanel.contentView is PinImageView)
        #expect(controller.desktopPins[id]?.window === pinPanel)
        try snapshot(pinPanel, to: "/private/tmp/PinboardShot-magnetic-expanded-smoke.png")
        var edited: [UUID] = []
        controller.onEdit = { edited.append($0.id) }
        let originalPNG = try Data(contentsOf: store.fileURL(for: store.items[0]))
        controller.desktopPins[id]?.onEditSourceImage?()
        #expect(edited == [id])
        #expect(try Data(contentsOf: store.fileURL(for: store.items[0])) == originalPNG)
        controller.returnToEdge(id)
        try await waitUntil { controller.cardPanels[id]?.frame == originalFrame && controller.desktopPins[id] == nil }
        let returnedPanel = try #require(controller.cardPanels[id])

        reduceMotion = true
        controller.setHover(id, entered: true)
        try await waitUntil { preview.frame.width == 210 && preview.isVisible }
        controller.suspendForCapture()
        #expect(!returnedPanel.isVisible)
        controller.setHover(id, entered: true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(!returnedPanel.isVisible)
        controller.resumeAfterCapture()
        try await waitUntil { returnedPanel.isVisible && returnedPanel.frame == originalFrame }
        #expect(!preview.isVisible)
    }

    @Test("Rapid hover switches keep rail hit zones fixed and stale tracking exits cannot shake the preview")
    func rapidHover() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticMotion-\(UUID())")
        let suite = "MagneticMotionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<10 { _ = try store.add(syntheticImage(index)) }
        var pointer = CGPoint(x: -10000, y: -10000)
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { false }, pointerLocation: { pointer })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 10 && controller.boxPanel?.isVisible == true }
        let ids = store.items.map(\.id)
        let base = ids.map { controller.cardPanels[$0]!.frame }
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        for index in [0, 1, 2, 5, 3, 8, 9, 4, 6, 2] {
            pointer = CGPoint(x: base[index].midX, y: base[index].maxY - 8)
            controller.updateHover(at: pointer)
            // A delayed exit from the old window must resolve the current fixed pointer slot.
            let oldHosting = try #require(controller.cardPanels[ids[0]]?.contentView as? MagneticCardHostingView)
            oldHosting.updateTrackingAreas()
            let areas = oldHosting.trackingAreas
            oldHosting.updateTrackingAreas()
            #expect(oldHosting.trackingAreas == areas)
            oldHosting.mouseExited(with: event)
            try await Task.sleep(for: .milliseconds(8))
            let preview = try #require(controller.hoverPanel)
            #expect((preview.contentView as? NSHostingView<MagneticCardView>)?.rootView.item.id == ids[index])
            #expect(preview.isVisible)
            #expect(base.allSatisfy { !preview.frame.intersects($0) })
            #expect(preview.frame.maxX <= base.map(\.minX).min()! - 11)
            #expect(ids.enumerated().allSatisfy { controller.cardPanels[$0.element]?.frame == base[$0.offset] })
        }
        let preview = try #require(controller.hoverPanel)
        let screen = NSScreen.screens[0].visibleFrame
        let railFrames = MagneticDesktopGeometry.cardFrames(count: ids.count, in: screen)
        let hoverTargets = railFrames.map { MagneticDesktopGeometry.hoverFrame(for: $0, beside: railFrames, in: screen) }
        func previewHasSettled(at index: Int) -> Bool {
            let target = hoverTargets[index]
            // Native panels align fractional layout to pixels; using an aligned card rounds twice.
            return preview.frame.size == target.size && abs(preview.frame.minX - target.minX) < 1
                && abs(preview.frame.minY - target.minY) < 1
        }
        try await waitUntil { previewHasSettled(at: 2) }
        try snapshot(preview, to: "/private/tmp/PinboardShot-magnetic-hover-smoke.png")
        controller.updateHover(at: CGPoint(x: base[2].minX - 240, y: base[2].midY))
        try await Task.sleep(for: .milliseconds(25))
        #expect(base.allSatisfy { !preview.frame.intersects($0) })
        pointer = CGPoint(x: base[7].midX, y: base[7].maxY - 8)
        controller.updateHover(at: pointer)
        try await waitUntil { previewHasSettled(at: 7) }
        #expect(preview.isVisible)
        pointer = CGPoint(x: -10000, y: -10000)
        controller.updateHover(at: pointer)
        try await waitUntil { !preview.isVisible }
        #expect(ids.enumerated().allSatisfy { controller.cardPanels[$0.element]?.frame == base[$0.offset] })
    }

    @Test("Expanded box occludes rail hover, cancels an existing preview and leaves uncovered cards responsive")
    func boxOccludesRailHover() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticHoverOcclusion-\(UUID())")
        let suite = "MagneticHoverOcclusionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(6, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<8 { _ = try store.add(syntheticImage(index)) }
        var pointer = CGPoint(x: -10000, y: -10000)
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, pointerLocation: { pointer })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 6 && controller.boxPanel?.isVisible == true }
        controller.toggleBox()
        let contents = try #require(controller.contentsPanel)
        let rail = store.items.prefix(6).compactMap { item in
            controller.cardPanels[item.id].map { (item.id, $0.frame) }
        }
        let covered = try #require(rail.first { !$0.1.intersection(contents.frame).isEmpty })
        let overlap = covered.1.intersection(contents.frame)
        pointer = CGPoint(x: overlap.midX, y: overlap.midY)
        controller.updateHover(at: pointer)
        #expect(controller.hoverPanel?.isVisible != true)

        controller.toggleBox()
        controller.updateHover(at: pointer)
        try await waitUntil { controller.hoverPanel?.isVisible == true }
        let preview = try #require(controller.hoverPanel)
        controller.toggleBox()
        #expect(!preview.isVisible)
        let hosting = try #require(controller.cardPanels[covered.0]?.contentView as? MagneticCardHostingView)
        let staleExit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        hosting.mouseExited(with: staleExit)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!preview.isVisible)

        let uncovered = try #require(rail.first {
            !contents.frame.contains(CGPoint(x: $0.1.midX, y: $0.1.midY))
        })
        pointer = CGPoint(x: uncovered.1.midX, y: uncovered.1.midY)
        controller.updateHover(at: pointer)
        try await waitUntil { preview.isVisible }
        #expect((preview.contentView as? NSHostingView<MagneticCardView>)?.rootView.item.id == uncovered.0)
        pointer = CGPoint(x: overlap.midX, y: overlap.midY)
        controller.updateHover(at: pointer)
        #expect(!preview.isVisible)
        controller.toggleBox()
        controller.updateHover(at: pointer)
        try await waitUntil { preview.isVisible }

        // The compact tray can also be dragged over rail cards.
        let tray = try #require(controller.boxPanel)
        tray.setFrameOrigin(CGPoint(x: pointer.x - tray.frame.width / 2, y: pointer.y - tray.frame.height / 2))
        controller.updateHover(at: pointer)
        #expect(!preview.isVisible)
    }

    @Test("Rail and box fold to a persistent edge handle and stay folded during captures and history changes")
    func foldingLifecycle() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticNative-\(UUID())")
        let suite = "MagneticNativeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(3, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<7 { _ = try store.add(syntheticImage(index)) }
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { false })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 3 && controller.boxPanel?.isVisible == true }
        let originalIDs = store.items.map(\.id)
        controller.toggleBox()
        let boxView = try #require(controller.boxPanel?.contentView as? MagneticPassiveHostingView<MagneticBoxView>)
        boxView.rootView.onCollapse()
        try await Task.sleep(for: .milliseconds(25))
        controller.setCollapsed(false)
        try await Task.sleep(for: .milliseconds(25))
        controller.setCollapsed(true)
        try await waitUntil { controller.foldedPanel?.isVisible == true && controller.cardPanels.values.allSatisfy { !$0.isVisible } && controller.boxPanel?.isVisible == false }
        let folded = try #require(controller.foldedPanel)
        let foldedView = try #require(folded.contentView as? MagneticPassiveHostingView<MagneticFoldedView>)
        #expect(foldedView.acceptsFirstMouse(for: nil))
        #expect(folded.frame == MagneticDesktopGeometry.foldedFrame(in: NSScreen.screens[0].visibleFrame))
        #expect(controller.contentsPanel?.isVisible == false)
        #expect(MagneticDesktopSettings(defaults: defaults).isCollapsed)
        #expect(store.items.map(\.id) == originalIDs)
        try snapshot(folded, to: "/private/tmp/PinboardShot-magnetic-folded-smoke.png")
        if ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" {
            // SwiftPM test runners do not include the compiled app asset catalog.
            let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Assets.xcassets")
            for name in MagneticFoldedView.artworkNames where NSImage(named: name) == nil {
                let image = try #require(NSImage(contentsOf: resources.appendingPathComponent("\(name).imageset/artwork.png")))
                #expect(image.setName(name))
            }
            let originalView = foldedView.rootView
            for dark in [false, true] {
                folded.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                foldedView.rootView = MagneticFoldedView(count: 17, onExpand: originalView.onExpand)
                try await Task.sleep(for: .milliseconds(80))
                try snapshot(folded, to: dark ? "/private/tmp/PinboardShot-folded-thumbnails-dark.png"
                    : "/private/tmp/PinboardShot-folded-thumbnails-light.png")
            }
            foldedView.rootView = MagneticFoldedView(count: 1234, onExpand: originalView.onExpand)
            try await Task.sleep(for: .milliseconds(80))
            try snapshot(folded, to: "/private/tmp/PinboardShot-folded-thumbnails-long-count.png")
            foldedView.rootView = originalView
            folded.appearance = nil
        }
        let removed = try #require(store.items.first)
        try store.delete(removed)
        try await waitUntil { controller.cardPanels[removed.id] == nil }
        #expect(folded.isVisible)
        controller.suspendForCapture()
        #expect(!folded.isVisible)
        _ = try store.add(syntheticImage(9))
        controller.resumeAfterCapture()
        try await waitUntil { folded.isVisible }
        #expect(controller.cardPanels.values.allSatisfy { !$0.isVisible })
        #expect(controller.overflowCount == 4)
        foldedView.rootView.onExpand()
        try await waitUntil { controller.cardPanels.values.allSatisfy(\.isVisible) && controller.boxPanel?.isVisible == true }
        #expect(!folded.isVisible)
        #expect(Set(controller.cardPanels.keys) == Set(store.items.prefix(3).map(\.id)))
        #expect(controller.contentsPanel?.isVisible == false)
        controller.setCollapsed(true)
        try await waitUntil { controller.cardPanels.values.allSatisfy { !$0.isVisible } }
        controller.stop()
        controller.start()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        #expect(controller.cardPanels.isEmpty)
        #expect(store.items.count == 7)
    }

    @Test("Second fold waits eight seconds, holds the first fold on hover and restarts after leaving or dragging")
    func secondFoldLifecycle() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticSecondFold-\(UUID())")
        let suite = "MagneticSecondFoldTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        var now: TimeInterval = 0
        let outside = CGPoint(x: -10000, y: -10000)
        var pointer = outside
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, pointerLocation: { pointer }, idleClock: { now })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        let panel = try #require(controller.foldedPanel)
        let first = panel.frame
        let hosting = try #require(panel.contentView as? MagneticFoldedHostingView)
        now = 7.99
        controller.checkForFoldedIdleCollapse()
        #expect(!controller.foldedIsCompact && panel.frame == first)
        now = 8
        controller.checkForFoldedIdleCollapse()
        #expect(controller.foldedIsCompact && panel.frame.size == CGSize(width: 20, height: 56))
        #expect(panel.frame.midY == first.midY && panel.frame.maxX == first.maxX)
        if ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" {
            let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Assets.xcassets")
            for name in MagneticFoldedView.artworkNames where NSImage(named: name) == nil {
                let image = try #require(NSImage(contentsOf: assets.appendingPathComponent("\(name).imageset/artwork.png")))
                #expect(image.setName(name))
            }
            for dark in [false, true] {
                panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                try await Task.sleep(for: .milliseconds(80))
                try snapshot(panel, to: dark ? "/private/tmp/PinboardShot-second-fold-dark.png"
                    : "/private/tmp/PinboardShot-second-fold-light.png")
            }
            panel.appearance = nil
        }
        now = 40
        _ = try store.add(syntheticImage(1))
        try await waitUntil { hosting.rootView.count == 2 }
        #expect(controller.foldedIsCompact && panel.frame.height == 56)
        pointer = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        controller.updateHover(at: pointer)
        #expect(!controller.foldedIsCompact && panel.frame == first)
        now = 200
        controller.checkForFoldedIdleCollapse()
        #expect(!controller.foldedIsCompact && MagneticDesktopSettings(defaults: defaults).isCollapsed)
        pointer = outside
        controller.updateHover(at: pointer)
        now = 207.99
        controller.checkForFoldedIdleCollapse()
        #expect(!controller.foldedIsCompact)
        now = 208
        controller.checkForFoldedIdleCollapse()
        #expect(controller.foldedIsCompact)

        func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 10, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
            panel.sendEvent(event)
        }
        var start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start)
        #expect(!controller.foldedIsCompact)
        let moved = CGPoint(x: start.x, y: start.y + 12)
        try send(.leftMouseDragged, at: moved)
        now = 300
        controller.checkForFoldedIdleCollapse()
        #expect(!controller.foldedIsCompact && hosting.isDragging)
        try send(.leftMouseUp, at: moved)
        now = 307.99
        controller.checkForFoldedIdleCollapse()
        #expect(!controller.foldedIsCompact)
        now = 308
        controller.checkForFoldedIdleCollapse()
        #expect(controller.foldedIsCompact)
        start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseUp, at: start)
        try await waitUntil { !panel.isVisible && controller.boxPanel?.isVisible == true }
        #expect(!MagneticDesktopSettings(defaults: defaults).isCollapsed)
        controller.setCollapsed(true)
        try await waitUntil { panel.isVisible }
        now = 316
        controller.checkForFoldedIdleCollapse()
        #expect(controller.foldedIsCompact)
        let compactCenter = panel.frame.midY
        defaults.set(false, forKey: MagneticDesktopSettings.enabledKey)
        controller.refresh(force: true)
        #expect(!panel.isVisible)
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        controller.refresh(force: true)
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        let restored = try #require(controller.foldedPanel)
        #expect(restored.frame.midY == compactCenter && !controller.foldedIsCompact)
    }

    @Test("Second fold timer runs automatically, pauses while hovered or capturing, and leaves floating stacks alone")
    func automaticSecondFoldTimer() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticSecondFoldTimer-\(UUID())")
        let suite = "MagneticSecondFoldTimerTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        let outside = CGPoint(x: -10000, y: -10000)
        var pointer = outside
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, pointerLocation: { pointer }, foldedIdleTimeout: 0.12)
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.foldedIsCompact }
        let panel = try #require(controller.foldedPanel)
        pointer = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        controller.updateHover(at: pointer)
        try await Task.sleep(for: .milliseconds(220))
        #expect(!controller.foldedIsCompact && panel.frame.height == 144)
        pointer = outside
        controller.updateHover(at: pointer)
        controller.suspendForCapture()
        try await Task.sleep(for: .milliseconds(220))
        #expect(!controller.foldedIsCompact && !panel.isVisible)
        controller.resumeAfterCapture()
        try await waitUntil { panel.isVisible }
        #expect(!controller.foldedIsCompact)
        try await waitUntil { controller.foldedIsCompact }
        let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start),
            (.leftMouseDragged, CGPoint(x: start.x - 100, y: start.y)),
            (.leftMouseUp, CGPoint(x: start.x - 100, y: start.y))] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 10, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
            panel.sendEvent(event)
        }
        #expect(controller.foldedIsDetached && !controller.foldedIsCompact)
        try await Task.sleep(for: .milliseconds(220))
        #expect(controller.foldedIsDetached && panel.frame.size == CGSize(width: 96, height: 112))
    }

    @Test("Folded decorative artwork resolves to valid bundled image assets")
    func foldedArtworkAssets() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Assets.xcassets")
        for name in MagneticFoldedView.artworkNames {
            let directory = resources.appendingPathComponent("\(name).imageset")
            let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
                directory.appendingPathComponent("Contents.json"))) as? [String: Any])
            let images = try #require(manifest["images"] as? [[String: Any]])
            let filename = try #require(images.first?["filename"] as? String)
            let image = try #require(NSImage(contentsOf: directory.appendingPathComponent(filename)))
            #expect(image.size.width > 0 && image.size.height > 0)
        }
    }

    @Test("Fan transitions reverse without moving hit windows, cancel for capture and honor reduced motion")
    func fanTransitionLifecycle() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticFan-\(UUID())")
        let suite = "MagneticFanTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(5, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<5 { _ = try store.add(syntheticImage(index)) }
        var reduced = false
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { reduced }, pointerLocation: { CGPoint(x: -10000, y: -10000) })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 5 && controller.boxPanel?.isVisible == true }
        let originals = controller.cardPanels.mapValues(\.frame)
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let keyWindow = NSApplication.shared.keyWindow
        controller.setCollapsed(true)
        try await waitUntil { controller.fanAnimationPanel?.isVisible == true && controller.fanAnimationProgress < 0.85 }
        let overlay = try #require(controller.fanAnimationPanel)
        #expect(overlay.ignoresMouseEvents && !overlay.canBecomeKey && !overlay.canBecomeMain)
        #expect(controller.cardPanels.values.allSatisfy { !$0.isVisible })
        #expect(controller.cardPanels.mapValues(\.frame) == originals)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
        #expect(NSApplication.shared.keyWindow === keyWindow)
        try snapshot(overlay, to: "/private/tmp/PinboardShot-fan-closing.png")
        let reversingAt = controller.fanAnimationProgress
        controller.setCollapsed(false)
        try await waitUntil { overlay.isVisible && controller.fanAnimationProgress > reversingAt }
        try snapshot(overlay, to: "/private/tmp/PinboardShot-fan-opening.png")
        try await waitUntil { !overlay.isVisible && controller.cardPanels.values.allSatisfy(\.isVisible) }
        #expect(controller.foldedPanel?.isVisible == false)
        #expect(controller.cardPanels.mapValues(\.frame) == originals)

        if ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" {
            controller.setCollapsed(true)
            for (index, progress) in [CGFloat(0.8), 0.5, 0.2].enumerated() {
                try await waitUntil { overlay.isVisible && controller.fanAnimationProgress <= progress }
                try snapshot(overlay, to: "/private/tmp/PinboardShot-fan-close-\(index).png")
            }
            try await waitUntil { !overlay.isVisible && controller.foldedPanel?.isVisible == true }
            controller.setCollapsed(false)
            for (index, progress) in [CGFloat(0.2), 0.5, 0.8].enumerated() {
                try await waitUntil { overlay.isVisible && controller.fanAnimationProgress >= progress }
                try snapshot(overlay, to: "/private/tmp/PinboardShot-fan-open-\(index).png")
            }
            try await waitUntil { !overlay.isVisible && controller.boxPanel?.isVisible == true }
        }

        controller.setCollapsed(true)
        try await waitUntil { overlay.isVisible && controller.fanAnimationProgress < 0.8 }
        controller.suspendForCapture()
        #expect(!overlay.isVisible && controller.foldedPanel?.isVisible == false)
        controller.resumeAfterCapture()
        try await waitUntil { controller.foldedPanel?.isVisible == true && !overlay.isVisible }
        #expect(controller.cardPanels.values.allSatisfy { !$0.isVisible })
        reduced = true
        controller.setCollapsed(false)
        try await waitUntil { controller.boxPanel?.isVisible == true && controller.cardPanels.values.allSatisfy(\.isVisible) }
        #expect(!overlay.isVisible && controller.foldedPanel?.isVisible == false)
        #expect(controller.cardPanels.mapValues(\.frame) == originals)
        reduced = false
        controller.setCollapsed(true)
        try await waitUntil { overlay.isVisible && controller.fanAnimationProgress < 0.8 }
        _ = try store.add(syntheticImage(7))
        try await waitUntil { !overlay.isVisible && controller.foldedPanel?.isVisible == true }
        let folded = try #require(controller.foldedPanel?.contentView as? MagneticPassiveHostingView<MagneticFoldedView>)
        #expect(folded.rootView.count == 6)
        controller.setCollapsed(false)
        try await waitUntil { !overlay.isVisible && controller.boxPanel?.isVisible == true
            && Set(controller.cardPanels.keys) == Set(store.items.prefix(5).map(\.id)) }
        #expect(controller.cardPanels.values.allSatisfy { $0.isVisible })
    }

    @Test("Only deliberate rightward momentum snaps back, and a paused release loses inertia")
    func throwPhysics() {
        let screen = CGRect(x: 0, y: 40, width: 1440, height: 900)
        let card = CGRect(x: 600, y: 300, width: 420, height: 300)
        #expect(MagneticDesktopThrow.shouldReturn(card: card, velocity: CGPoint(x: 1500, y: 100), screen: screen))
        #expect(!MagneticDesktopThrow.shouldReturn(card: card, velocity: CGPoint(x: 300, y: 0), screen: screen))
        #expect(!MagneticDesktopThrow.shouldReturn(card: card, velocity: CGPoint(x: -2000, y: 0), screen: screen))
        #expect(!MagneticDesktopThrow.shouldReturn(card: card, velocity: CGPoint(x: 1500, y: 2000), screen: screen))
        #expect(!MagneticDesktopThrow.shouldReturn(card: card.offsetBy(dx: -500, dy: 0), velocity: CGPoint(x: 900, y: 0), screen: screen))
        #expect(MagneticDesktopThrow.shouldReturn(card: card.offsetBy(dx: 400, dy: 0), velocity: .zero, screen: screen))
        #expect(screen.contains(MagneticDesktopThrow.settledFrame(card, velocity: CGPoint(x: 10000, y: -10000), screen: screen)))
        var tracker = MagneticDragVelocity()
        tracker.record(CGPoint(x: 100, y: 100), at: 1)
        tracker.record(CGPoint(x: 200, y: 110), at: 1.05)
        #expect(abs(tracker.velocity.x - 2000) < 1)
        tracker.record(CGPoint(x: 200, y: 110), at: 1.5)
        #expect(tracker.velocity == .zero)
    }

    @Test("Recovered magnetic pins retain rail and box homes, normal level, hidden state and return actions")
    func magneticSessionRecovery() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("MagneticRecovery-\(UUID())", isDirectory: true)
        let suite = "MagneticRecoveryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(1, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let history = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<4 { _ = try history.add(syntheticImage(index)) }
        let ids = history.items.map(\.id)
        let manager = PinWindowManager()
        let controller = MagneticDesktopController(historyStore: history, defaults: defaults, reduceMotion: { true },
            pointerLocation: { CGPoint(x: -10000, y: -10000) }, pinManager: manager)
        defer { controller.stop(); manager.closeAll() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 1 && controller.boxPanel?.isVisible == true }
        controller.extract(ids[0])
        try await waitUntil { controller.desktopPins[ids[0]] != nil }
        controller.extract(ids[3], from: .box)
        try await waitUntil { controller.desktopPins.count == 2 }
        let originalFrames = controller.desktopPins.compactMapValues { $0.window?.frame }
        let sources = Set(manager.sessionCaptures().compactMap { $0.magneticSource?.historyItemID })
        #expect(sources == Set([ids[0], ids[3]]))
        // Idle folding retains desktop references; explicit manual folding returns them first.
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        controller.refresh(force: true)
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        manager.toggleAll()
        let workspace = PinWorkspaceStore(rootDirectory: root.appendingPathComponent("workspaces", isDirectory: true))
        // Match application shutdown: save associations before stopping detaches the live pins.
        let snapshot = manager.sessionCaptures()
        #expect(snapshot.count == 2 && snapshot.allSatisfy { $0.state.isValid })
        let summary = try #require(try workspace.saveRecoverySession(captures: snapshot, pinsAreVisible: manager.pinsAreVisible))
        #expect(summary.pinCount == 2)
        var shutdownChanges = 0
        manager.onSessionChanged = { shutdownChanges += 1 }
        controller.stop(closeDesktopPins: false)
        #expect(shutdownChanges == 0)
        #expect(manager.sessionCaptures().compactMap(\.magneticSource).count == 2)
        manager.onSessionChanged = nil
        manager.closeAll()
        let recovery = try #require(workspace.loadRecoverySession())
        #expect(!recovery.pinsAreVisible)
        #expect(recovery.entries.compactMap(\.magneticSource).count == 2)

        let restoredManager = PinWindowManager()
        let restored = MagneticDesktopController(historyStore: history, defaults: defaults, reduceMotion: { true },
            pointerLocation: { CGPoint(x: -10000, y: -10000) }, pinManager: restoredManager)
        defer { restored.stop(); restoredManager.closeAll() }
        restored.start()
        restoredManager.restoreWorkspace(recovery.entries)
        restored.restoreSessionPins()
        restoredManager.toggleAll()
        try await waitUntil { restored.foldedPanel?.isVisible == true }
        #expect(restored.desktopPins.count == 2 && restoredManager.count == 2)
        for id in [ids[0], ids[3]] {
            let pin = try #require(restored.desktopPins[id])
            #expect(pin.window?.level == .normal && pin.window?.isVisible == false)
            #expect(pin.window?.frame == originalFrames[id])
            #expect(pin.onReturnToSource != nil && pin.onEditSourceImage != nil)
            #expect(pin.magneticSource == MagneticPinSource(historyItemID: id, home: id == ids[0] ? .rail : .box))
        }
        restored.restoreSessionPins()
        #expect(restoredManager.magneticPins.count == 2)
        restoredManager.toggleAll()
        restored.setCollapsed(false)
        try await waitUntil { restored.boxPanel?.isVisible == true }
        #expect(restored.cardPanels.count == 3)
        for id in [ids[0], ids[3]] {
            let pin = try #require(restored.desktopPins[id])
            let panel = try #require(pin.window)
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
                location: CGPoint(x: panel.frame.width / 2, y: panel.frame.height / 2), modifierFlags: [],
                timestamp: 1, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 0))
            panel.sendEvent(event)
            try await waitUntil {
                restored.desktopPins[id] == nil && restored.activeFlightCount == 0
                    && (id == ids[0] ? restored.cardPanels[id]?.level == .floating : restored.cardPanels[id] == nil)
            }
        }
        #expect(restoredManager.count == 0)
        #expect(restored.cardPanels[ids[0]]?.isVisible == true)
        #expect(restored.cardPanels[ids[3]] == nil && restored.overflowCount == 3)

        restored.extract(ids[0])
        try await waitUntil { restored.desktopPins[ids[0]] != nil }
        var sourceChanges = 0
        restoredManager.onSessionChanged = { sourceChanges += 1 }
        defaults.set(false, forKey: MagneticDesktopSettings.enabledKey)
        restored.refresh(force: true)
        #expect(restoredManager.count == 1 && restoredManager.magneticPins.isEmpty)
        #expect(sourceChanges > 0)
        #expect(restoredManager.sessionCaptures().first?.magneticSource == nil)
    }

    @Test("Unavailable history or disabled magnetic mode restores a saved image as an ordinary pin", arguments: [false, true])
    func unavailableMagneticSessionSource(historyDeleted: Bool) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticUnavailable-\(UUID())", isDirectory: true)
        let suite = "MagneticUnavailableTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(historyDeleted, forKey: MagneticDesktopSettings.enabledKey)
        let history = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        let image = syntheticImage(0)
        let item = try #require(try history.add(image))
        let manager = PinWindowManager()
        let frame = try #require(NSScreen.screens.first?.visibleFrame)
        let pose = MagneticDesktopGeometry.expandedFrame(imageSize: image.size,
            near: CGPoint(x: frame.midX, y: frame.midY), in: frame)
        let pin = manager.pinFromMagneticDesktop(image: image, frame: pose)
        let saved = pin.sessionCapture
        manager.closeAll()
        if historyDeleted { try history.delete(item) }
        manager.restoreWorkspace([PinWorkspaceRestoreEntry(image: image, state: saved.state, metadata: saved.metadata,
            magneticSource: MagneticPinSource(historyItemID: item.id, home: .rail))])
        let restored = try #require(manager.magneticPins.first)
        let controller = MagneticDesktopController(historyStore: history, defaults: defaults, reduceMotion: { true },
            pointerLocation: { CGPoint(x: -10000, y: -10000) }, pinManager: manager)
        defer { controller.stop(); manager.closeAll() }
        controller.start()
        controller.restoreSessionPins()
        #expect(manager.count == 1 && manager.magneticPins.isEmpty)
        #expect(controller.desktopPins.isEmpty)
        #expect(restored.window?.level == .floating && restored.window?.isVisible == true)
        #expect(restored.onReturnToSource == nil)
        #expect(manager.sessionCaptures().first?.magneticSource == nil)
    }

    @Test("Native magnetic pins stay on left and right displays, center per display and reject a blocked drop")
    func nativeMultipleScreenDrops() async throws {
        _ = NSApplication.shared
        let primary = try #require(NSScreen.screens.first?.visibleFrame)
        let right = primary.offsetBy(dx: primary.width + 80, dy: 0)
        let left = primary.offsetBy(dx: -primary.width - 80, dy: 0)
        let screens = [primary, right, left]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticScreens-\(UUID())", isDirectory: true)
        let suite = "MagneticScreenTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        let history = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<4 { _ = try history.add(syntheticImage(index)) }
        let ids = history.items.map(\.id)
        let manager = PinWindowManager()
        let controller = MagneticDesktopController(historyStore: history, defaults: defaults, reduceMotion: { true },
            pointerLocation: { CGPoint(x: -10000, y: -10000) }, pinManager: manager, screenFrames: { screens })
        defer { controller.stop(); manager.closeAll() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 4 && controller.boxPanel?.isVisible == true }
        func drag(_ pin: PinWindowController, to point: CGPoint, time: TimeInterval) throws {
            let panel = try #require(pin.window)
            let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            for (type, location, timestamp) in [(NSEvent.EventType.leftMouseDown, start, time),
                                               (.leftMouseDragged, point, time + 1), (.leftMouseUp, point, time + 1.5)] {
                panel.sendEvent(try #require(NSEvent.mouseEvent(with: type,
                    location: panel.convertPoint(fromScreen: location), modifierFlags: [], timestamp: timestamp,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)))
            }
        }
        controller.extract(ids[0])
        try await waitUntil { controller.desktopPins[ids[0]] != nil }
        let first = try #require(controller.desktopPins[ids[0]])
        try drag(first, to: CGPoint(x: right.midX + 120, y: right.midY - 80), time: 10)
        #expect(right.contains(try #require(first.window?.frame)))
        #expect(controller.desktopPins[ids[0]] === first)
        controller.extract(ids[1])
        try await waitUntil { controller.desktopPins[ids[1]] != nil }
        let second = try #require(controller.desktopPins[ids[1]])
        try drag(second, to: CGPoint(x: left.midX - 120, y: left.midY + 80), time: 20)
        #expect(left.contains(try #require(second.window?.frame)))
        let rightPose = try #require(first.window?.frame)
        let leftPose = try #require(second.window?.frame)
        controller.extract(ids[2])
        try await waitUntil { controller.desktopPins.count == 3 }
        #expect(first.window?.frame == rightPose && second.window?.frame == leftPose)
        controller.centerDesktopGroup()
        try await waitUntil {
            controller.activeFlightCount == 0 && abs((first.window?.frame.midX ?? 0) - right.midX) <= 1
                && abs((second.window?.frame.midX ?? 0) - left.midX) <= 1
                && primary.contains(controller.desktopPins[ids[2]]?.window?.frame ?? .zero)
        }
        #expect(right.contains(try #require(first.window?.frame)))
        #expect(left.contains(try #require(second.window?.frame)))

        let previous = try #require(first.window?.frame)
        let blocker = manager.pinFromMagneticDesktop(image: syntheticImage(9), frame: left)
        try drag(first, to: CGPoint(x: left.midX, y: left.midY), time: 30)
        #expect(first.window?.frame == previous)
        #expect(controller.desktopFrames[ids[0]] == previous)
        blocker.close()
        let width = try #require(first.window?.frame.width)
        try drag(first, to: CGPoint(x: primary.maxX - width / 2 - 5, y: primary.midY), time: 40)
        try await waitUntil {
            controller.desktopPins[ids[0]] == nil && controller.activeFlightCount == 0
                && controller.cardPanels[ids[0]]?.level == .floating
        }
        #expect(controller.cardPanels[ids[0]]?.level == .floating)
    }

    @Test("Multiple desktop cards stay at normal levels, preserve positions and return with synchronized light trails")
    func multipleDesktopCards() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticMotion-\(UUID())")
        let suite = "MagneticMotionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(3, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<8 { _ = try store.add(syntheticImage(index)) }
        let ids = store.items.map(\.id)
        let originals = try store.items.map { try Data(contentsOf: store.fileURL(for: $0)) }
        var reduced = false
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { reduced },
            pointerLocation: { CGPoint(x: -10000, y: -10000) })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 3 && controller.boxPanel?.isVisible == true }
        for (index, id) in ids.prefix(2).enumerated() {
            let panel = try #require(controller.cardPanels[id])
            let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            let end = CGPoint(x: start.x - 320, y: start.y - CGFloat(index * 60))
            controller.drag(id, at: start, ended: false, timestamp: 1)
            #expect(panel.level == .normal)
            controller.drag(id, at: end, ended: false, timestamp: 1.06)
            controller.drag(id, at: end, ended: true, timestamp: 1.08)
            try await Task.sleep(for: .milliseconds(40))
            let hosting = try #require(panel.contentView as? MagneticCardHostingView)
            #expect(hosting.rootView.motion.direction == .outward)
            #expect(hosting.rootView.motion.progress > 0 && hosting.rootView.motion.progress < 1)
            #expect(panel.level == .normal)
            try snapshot(panel, to: "/private/tmp/PinboardShot-magnetic-flip-smoke.png")
            try await waitUntil { controller.desktopPins[id] != nil && controller.activeFlightCount == 0 }
        }
        let first = try #require(controller.cardPanels[ids[0]])
        let firstPosition = first.frame
        let second = try #require(controller.cardPanels[ids[1]])
        let secondPosition = second.frame
        controller.extract(ids[7])
        try await waitUntil { controller.desktopFrames.count == 3 && controller.activeFlightCount == 0 && controller.cardPanels[ids[7]]?.frame == controller.desktopFrames[ids[7]] }
        #expect(first.frame == firstPosition && second.frame == secondPosition)
        #expect(controller.cardPanels.count == 6)
        let poses = Array(controller.desktopFrames.values)
        for (index, pose) in poses.enumerated() {
            #expect(poses.enumerated().allSatisfy { $0.offset == index || !pose.intersects($0.element) })
        }
        _ = try store.add(syntheticImage(10))
        try await waitUntil { controller.cardPanels[store.items[0].id]?.isVisible == true }
        #expect(controller.desktopFrames.count == 3)
        #expect(first.frame == firstPosition && second.frame == secondPosition)

        let start = CGPoint(x: first.frame.midX, y: first.frame.midY)
        controller.drag(ids[0], at: start, ended: false, timestamp: 10)
        controller.drag(ids[0], at: CGPoint(x: start.x + 40, y: start.y), ended: true, timestamp: 10.3)
        try await waitUntil { controller.activeFlightCount == 0 && first.frame == controller.desktopFrames[ids[0]] }
        #expect(first.frame.minX == firstPosition.minX + 40)
        #expect(second.frame == secondPosition)
        let throwStart = CGPoint(x: first.frame.midX, y: first.frame.midY)
        controller.drag(ids[0], at: throwStart, ended: false, timestamp: 11)
        controller.drag(ids[0], at: CGPoint(x: throwStart.x + 180, y: throwStart.y), ended: true, timestamp: 11.08)
        #expect(controller.desktopFrames[ids[0]] == nil)
        try await waitUntil { controller.activeFlightCount == 0 && controller.cardPanels[ids[0]]?.level == .floating }
        #expect(controller.desktopFrames.count == 2)
        #expect(second.frame == secondPosition)

        controller.extract(ids[0])
        try await waitUntil { controller.activeFlightCount == 0 && controller.desktopPins[ids[0]] != nil }
        let sourcePin = try #require(controller.desktopPins[ids[1]])
        sourcePin.onReturnAllToSource?()
        try await Task.sleep(for: .milliseconds(40))
        #expect(controller.activeFlightCount == 3)
        #expect(controller.trailPanel?.isVisible == true)
        #expect(controller.trailPanel?.level == .normal)
        #expect(controller.trailPanel?.ignoresMouseEvents == true)
        try snapshot(controller.trailPanel, to: "/private/tmp/PinboardShot-magnetic-trails-smoke.png")
        controller.suspendForCapture()
        #expect(controller.trailPanel?.isVisible == false)
        #expect(controller.activeFlightCount == 0)
        #expect(controller.cardPanels.values.allSatisfy { !$0.isVisible })
        controller.resumeAfterCapture()
        try await waitUntil { controller.cardPanels.count == 3 && controller.boxPanel?.isVisible == true }
        #expect(controller.desktopFrames.isEmpty)

        reduced = true
        controller.extract(ids[1])
        try await waitUntil { controller.cardPanels[ids[1]]?.frame == controller.desktopFrames[ids[1]] && controller.desktopFrames[ids[1]] != nil }
        #expect(controller.activeFlightCount == 0)
        #expect(controller.cardPanels[ids[1]]?.contentView is PinImageView)
        controller.returnAllToEdge()
        try await waitUntil { controller.cardPanels.count == 3 && controller.cardPanels.values.allSatisfy { $0.level == .floating } }
        for (index, id) in ids.enumerated() {
            let item = try #require(store.items.first { $0.id == id })
            #expect(try Data(contentsOf: store.fileURL(for: item)) == originals[index])
        }
    }

    @Test("Native mouse down, drag and release return a desktop card using event timestamps and moving-window coordinates")
    func nativeThrowEvents() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticMotion-\(UUID())")
        let suite = "MagneticMotionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(3, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<3 { _ = try store.add(syntheticImage(index)) }
        // The real pointer is deliberately unrelated: throw velocity must come from mouse events.
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, pointerLocation: { CGPoint(x: -10000, y: -10000) })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 3 && controller.boxPanel?.isVisible == true }
        let id = try #require(store.items.first?.id)
        var panel = try #require(controller.cardPanels[id])
        func event(_ type: NSEvent.EventType, at point: CGPoint, time: TimeInterval) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: time, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
        }
        func send(_ type: NSEvent.EventType, at point: CGPoint, time: TimeInterval) throws {
            panel.sendEvent(try event(type, at: point, time: time))
        }
        var start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start, time: 30)
        try send(.leftMouseUp, at: start, time: 30.02)
        try await waitUntil { controller.desktopPins[id] != nil }
        panel = try #require(controller.cardPanels[id])
        #expect(panel.level == .normal)
        #expect(panel.contentView is PinImageView)
        start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let initial = panel.frame
        try send(.leftMouseDown, at: start, time: 40)
        try send(.leftMouseDragged, at: CGPoint(x: start.x + 90, y: start.y), time: 40.03)
        #expect(panel.frame.minX == initial.minX + 90)
        try send(.leftMouseDragged, at: CGPoint(x: start.x + 160, y: start.y), time: 40.06)
        #expect(panel.frame.minX == initial.minX + 160)
        try send(.leftMouseUp, at: CGPoint(x: start.x + 175, y: start.y), time: 40.075)
        #expect(controller.desktopFrames[id] == nil)
        try await waitUntil { controller.cardPanels[id]?.level == .floating && controller.activeFlightCount == 0 }

        controller.extract(id)
        try await waitUntil { controller.desktopPins[id] != nil }
        panel = try #require(controller.cardPanels[id])
        start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start, time: 50)
        try send(.leftMouseDragged, at: CGPoint(x: start.x + 40, y: start.y), time: 50.3)
        try send(.leftMouseUp, at: CGPoint(x: start.x + 40, y: start.y), time: 50.31)
        try await waitUntil { controller.desktopFrames[id] != nil && panel.frame == controller.desktopFrames[id] }
        #expect(panel.level == .normal)
        start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start, time: 51)
        try send(.leftMouseDragged, at: CGPoint(x: start.x + 90, y: start.y), time: 51.05)
        try send(.leftMouseUp, at: CGPoint(x: start.x + 90, y: start.y), time: 51.4)
        try await waitUntil { controller.desktopFrames[id] != nil && panel.frame == controller.desktopFrames[id] }
        #expect(panel.level == .normal)
    }

    @Test("Magnetic pin menu actions remain enabled after returning and extracting the same image again")
    func nativeContextMenuReopens() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticMenu-\(UUID())")
        let suite = "MagneticMenuTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        let item = try #require(try store.add(syntheticImage(0)))
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, pointerLocation: { CGPoint(x: -10000, y: -10000) })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels[item.id]?.isVisible == true }

        for cycle in 0..<3 {
            controller.extract(item.id)
            try await waitUntil { controller.desktopPins[item.id] != nil }
            let pin = try #require(controller.desktopPins[item.id])
            let panel = try #require(pin.window as? PinPanel)
            let view = try #require(panel.contentView as? PinImageView)
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
                location: CGPoint(x: 40, y: 40), modifierFlags: [], timestamp: Double(cycle + 1),
                windowNumber: panel.windowNumber, context: nil, eventNumber: cycle,
                clickCount: 1, pressure: 1))
            let menu = try #require(view.menu(for: event))
            menu.update()
            let zoomIndex = try #require(menu.items.firstIndex { $0.title == L10n.text("pin.zoomIn") })
            let returnIndex = try #require(menu.items.firstIndex { $0.title == L10n.text("magnetic.return") })
            #expect(menu.items[zoomIndex].isEnabled)
            #expect(menu.items[returnIndex].isEnabled)
            let initialWidth = panel.frame.width
            var requests = 0
            panel.onContextMenuRequested = { _ in
                requests += 1
                menu.performActionForItem(at: zoomIndex)
                #expect(panel.frame.width > initialWidth)
                menu.performActionForItem(at: returnIndex)
            }
            panel.sendEvent(event)
            #expect(requests == 0)
            try await waitUntil {
                requests == 1 && controller.desktopPins[item.id] == nil
                    && controller.cardPanels[item.id]?.level == .floating
            }
        }
    }

    @Test("The real native center-group menu action moves a manual layout without changing its size",
        .enabled(if: ProcessInfo.processInfo.environment["PINBOARDSHOT_NATIVE_MENU_SMOKE"] == "1"))
    func nativeCenterGroupMenu() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticCenterMenu-\(UUID())")
        let suite = "MagneticCenterMenuTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        let item = try #require(try store.add(syntheticImage(0)))
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { false },
            pointerLocation: { CGPoint(x: -10000, y: -10000) })
        let probe = MagneticContextMenuProbe()
        probe.selectionTitle = L10n.text("magnetic.centerGroup")
        NotificationCenter.default.addObserver(probe, selector: #selector(MagneticContextMenuProbe.menuBeganTracking(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(probe); controller.stop() }
        let screen = try #require(NSScreen.screens.first?.visibleFrame)
        let centerX = screen.minX + 16 + (screen.width - MagneticDesktopGeometry.cardSize.width - 40) / 2
        controller.start()
        try await waitUntil { controller.boxPanel?.isVisible == true }
        controller.extract(item.id)
        try await waitUntil {
            guard let panel = controller.desktopPins[item.id]?.window else { return false }
            return abs(panel.frame.midX - centerX) <= 1 && controller.desktopFrames[item.id] == panel.frame
        }
        let pin = try #require(controller.desktopPins[item.id])
        pin.nudge(by: CGPoint(x: -80, y: -40))
        let panel = try #require(pin.window as? PinPanel)
        probe.panel = panel
        let size = panel.frame.size
        let rightClick = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
            location: CGPoint(x: 40, y: 40), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        panel.sendEvent(rightClick)
        try await waitUntil { probe.selectedCount == 1 && abs(panel.frame.midX - centerX) <= 1
            && abs(panel.frame.midY - screen.midY) <= 1 && controller.desktopFrames[item.id] == panel.frame }
        try #require(probe.openedCount == 1 && panel.frame.size == size && panel.level == .normal)
    }

    @Test("Real magnetic context menus track mouse events and reopen after an image is returned",
        .enabled(if: ProcessInfo.processInfo.environment["PINBOARDSHOT_NATIVE_MENU_SMOKE"] == "1"))
    func nativeContextMenuTracking() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticMenuTracking-\(UUID())")
        let suite = "MagneticMenuTrackingTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        let item = try #require(try store.add(syntheticImage(0)))
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, pointerLocation: { CGPoint(x: -10000, y: -10000) })
        let probe = MagneticContextMenuProbe()
        NotificationCenter.default.addObserver(probe,
            selector: #selector(MagneticContextMenuProbe.menuBeganTracking(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        defer {
            NotificationCenter.default.removeObserver(probe)
            controller.stop()
        }
        controller.start()
        try await waitUntil { controller.cardPanels[item.id]?.isVisible == true }
        for cycle in 0..<3 {
            controller.extract(item.id)
            try await waitUntil { controller.desktopPins[item.id] != nil }
            let panel = try #require(controller.desktopPins[item.id]?.window as? PinPanel)
            probe.panel = panel
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
                location: CGPoint(x: 40, y: 40), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: cycle, clickCount: 1, pressure: 1))
            // Keep the production event route; scripts/test-pin-menu.sh supplies the full NSApplication loop.
            panel.sendEvent(event)
            try await waitUntil { probe.selectedCount == cycle + 1 }
            try #require(probe.selectedCount == cycle + 1)
            try #require(probe.openedCount == cycle + 1)
            try #require(probe.zoomSucceeded)
            controller.returnToEdge(item.id)
            try await waitUntil { controller.desktopPins[item.id] == nil && controller.cardPanels[item.id]?.level == .floating }
        }
    }

    @Test("Extracted images are registered pins and native double-click returns them to the original rail or box")
    func nativeSourceReturns() async throws {
        _ = NSApplication.shared
        if ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" {
            // SwiftPM tests do not contain the app's compiled asset catalog.
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let artwork = try #require(NSImage(contentsOf: root.appendingPathComponent(
                "Resources/Assets.xcassets/TrayPanelBackdropTexture.imageset/tray-panel-backdrop-texture.png")))
            #expect(artwork.setName("TrayPanelBackdropTexture"))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticMotion-\(UUID())")
        let suite = "MagneticMotionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(2, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<6 { _ = try store.add(syntheticImage(index)) }
        let ids = store.items.map(\.id)
        let manager = PinWindowManager()
        var reduced = false
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { reduced }, pointerLocation: { CGPoint(x: -10000, y: -10000) }, pinManager: manager)
        defer { controller.stop(); manager.closeAll() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 2 && controller.boxPanel?.isVisible == true }
        controller.extract(ids[0])
        try await waitUntil { controller.desktopPins[ids[0]] != nil }
        let railPin = try #require(controller.desktopPins[ids[0]])
        #expect(manager.count == 1 && railPin.window?.contentView is PinImageView)
        let windowNumber = try #require(railPin.window?.windowNumber)
        let menuEvent = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 79, windowNumber: windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        let menu = try #require((railPin.window?.contentView as? PinImageView)?.menu(for: menuEvent))
        #expect(menu.items.contains { $0.title == L10n.text("pin.copy") })
        #expect(menu.items.contains { $0.title == L10n.text("magnetic.return") })
        #expect(menu.items.contains { $0.title == L10n.text("magnetic.edit") })
        railPin.scale(by: 1.1)
        let zoomed = try #require(railPin.window?.frame)
        controller.refresh(force: true)
        try await waitUntil { controller.desktopFrames[ids[0]] == zoomed }
        controller.extract(ids[5], from: .box)
        try await waitUntil { controller.desktopPins[ids[5]] != nil }
        #expect(manager.count == 2)
        let boxPin = try #require(controller.desktopPins[ids[5]])
        #expect(railPin.window?.frame == zoomed)
        #expect(!zoomed.intersects(try #require(boxPin.window?.frame)))

        func doubleClick(_ pin: PinWindowController) throws {
            let panel = try #require(pin.window as? NSPanel)
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
                location: CGPoint(x: panel.frame.width / 2, y: panel.frame.height / 2), modifierFlags: [],
                timestamp: 80, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 2, pressure: 0))
            panel.sendEvent(event)
        }
        try doubleClick(railPin)
        try await waitUntil { controller.activeFlightCount == 0 && controller.cardPanels[ids[0]]?.level == .floating }
        #expect(manager.count == 1 && controller.desktopPins[ids[5]] === boxPin)
        defaults.set(30, forKey: MagneticDesktopSettings.maximumVisibleKey)
        controller.refresh(force: true)
        try await waitUntil { controller.cardPanels.count == 6 && controller.activeFlightCount == 0 }
        try doubleClick(boxPin)
        try await waitUntil { controller.boxArrivalProgress < 1 && controller.desktopFrames.isEmpty && controller.cardPanels[ids[5]] == nil }
        #expect(manager.count == 0)
        #expect(controller.overflowCount == 1 && controller.cardPanels[ids[5]] == nil)
        try snapshot(controller.boxPanel, to: "/private/tmp/PinboardShot-magnetic-box-arrival.png")
        try await waitUntil { controller.boxArrivalProgress == 1 }
        controller.boxPanel?.appearance = NSAppearance(named: .aqua)
        try snapshot(controller.boxPanel, to: "/private/tmp/PinboardShot-magnetic-box-light.png")
        controller.boxPanel?.appearance = NSAppearance(named: .darkAqua)
        try snapshot(controller.boxPanel, to: "/private/tmp/PinboardShot-magnetic-box-dark.png")
        controller.boxPanel?.appearance = nil
        try await snapshotTrayStates(item: store.items[0])

        reduced = true
        controller.extract(ids[5], from: .box)
        try await waitUntil { controller.desktopPins[ids[5]] != nil }
        try doubleClick(try #require(controller.desktopPins[ids[5]]))
        try await waitUntil { controller.desktopFrames.isEmpty && controller.cardPanels[ids[5]] == nil }
        #expect(controller.boxArrivalProgress == 1 && controller.activeFlightCount == 0)
        controller.extract(ids[5], from: .box)
        try await waitUntil { controller.desktopPins[ids[5]] != nil }
        controller.desktopPins[ids[5]]?.close()
        try await waitUntil { controller.desktopFrames.isEmpty && controller.cardPanels[ids[5]] == nil }
        #expect(manager.count == 0 && controller.overflowCount == 1)
        controller.suspendForCapture()
        #expect(controller.boxArrivalProgress == 1 && controller.boxPanel?.isVisible == false)
    }

    @Test("Native tray dragging survives history refresh, folding and capture, and leaves footer buttons alone")
    func nativeTrayDragging() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticNative-\(UUID())")
        let suite = "MagneticNativeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(2, forKey: MagneticDesktopSettings.maximumVisibleKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        for index in 0..<4 { _ = try store.add(syntheticImage(index)) }
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults, reduceMotion: { true })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.cardPanels.count == 2 && controller.boxPanel?.isVisible == true }
        let panel = try #require(controller.boxPanel)
        let hosting = try #require(panel.contentView as? MagneticBoxHostingView)
        let screen = NSScreen.screens[0].visibleFrame
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 10, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
        }
        func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
            panel.sendEvent(try event(type, at: point))
        }
        var start = CGPoint(x: panel.frame.midX, y: panel.frame.maxY - 20)
        let original = panel.frame
        try send(.leftMouseDown, at: start)
        try send(.leftMouseUp, at: start)
        #expect(controller.contentsPanel?.isVisible == true)
        let contentsBefore = try #require(controller.contentsPanel?.frame)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 120, y: start.y + 90))
        #expect(panel.frame.origin == CGPoint(x: original.minX - 120, y: original.minY + 90))
        defaults.set(3, forKey: MagneticDesktopSettings.maximumVisibleKey)
        controller.refresh()
        try await waitUntil { controller.cardPanels.count == 3 && hosting.rootView.count == 1 }
        #expect(panel.contentView === hosting)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 180, y: start.y + 130))
        try send(.leftMouseUp, at: CGPoint(x: start.x - 200, y: start.y + 140))
        let moved = panel.frame
        #expect(moved.origin == CGPoint(x: original.minX - 200, y: original.minY + 140))
        #expect(controller.contentsPanel?.frame != contentsBefore)
        #expect(screen.contains(try #require(controller.contentsPanel?.frame)))
        #expect(controller.contentsPanel?.isVisible == true)

        _ = try store.add(syntheticImage(8))
        try await waitUntil { hosting.rootView.count == 2 && controller.cardPanels[store.items[0].id] != nil }
        #expect(panel.frame == moved)
        let footer = CGPoint(x: panel.frame.maxX - 18, y: panel.frame.minY + 20)
        #expect(!hosting.handleMouseEvent(try event(.leftMouseDown, at: footer)))
        #expect(!hosting.handleMouseEvent(try event(.leftMouseUp, at: footer)))
        #expect(panel.frame == moved)

        start = CGPoint(x: panel.frame.midX, y: panel.frame.maxY - 20)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 10000, y: start.y + 10000))
        try send(.leftMouseUp, at: CGPoint(x: start.x - 10000, y: start.y + 10000))
        let clamped = panel.frame
        #expect(screen.contains(clamped))
        #expect(panel.level.rawValue == NSWindow.Level.floating.rawValue + 1)
        controller.setCollapsed(true)
        try await waitUntil { controller.foldedPanel?.isVisible == true && !panel.isVisible }
        controller.setCollapsed(false)
        try await waitUntil { panel.isVisible && panel.frame == clamped }

        start = CGPoint(x: panel.frame.midX, y: panel.frame.maxY - 20)
        try send(.leftMouseDown, at: start)
        controller.suspendForCapture()
        controller.resumeAfterCapture()
        try await waitUntil { panel.isVisible }
        try send(.leftMouseDragged, at: CGPoint(x: start.x + 40, y: start.y - 40))
        try send(.leftMouseUp, at: CGPoint(x: start.x + 40, y: start.y - 40))
        #expect(panel.frame == clamped)
    }

    @Test("Folded handle slides vertically along the right edge, keeps click expansion and survives refresh and capture")
    func nativeFoldedDragging() async throws {
        let app = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticFoldedDrag-\(UUID())")
        let suite = "MagneticFoldedDragTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        var screen = CGRect(x: 100, y: -100, width: 1200, height: 800)
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { true }, screenFrames: { [screen] })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        let panel = try #require(controller.foldedPanel)
        let hosting = try #require(panel.contentView as? MagneticFoldedHostingView)
        let keyWindow = app.keyWindow
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(hosting.acceptsFirstMouse(for: nil))
        func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 10, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
            panel.sendEvent(event)
        }
        let original = panel.frame
        var start = CGPoint(x: original.midX, y: original.midY)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 40, y: start.y))
        try send(.leftMouseUp, at: CGPoint(x: start.x - 40, y: start.y))
        #expect(panel.frame == original && panel.isVisible && MagneticDesktopSettings(defaults: defaults).isCollapsed)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 2, y: start.y + 1))
        #expect(!hosting.isDragging && panel.frame == original)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 20, y: start.y + 60))
        #expect(hosting.isDragging && panel.frame.origin == CGPoint(x: original.minX, y: original.minY + 60))
        _ = try store.add(syntheticImage(1))
        try await waitUntil { hosting.rootView.count == 2 }
        #expect(panel.contentView === hosting && hosting.isDragging)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 24, y: start.y + 75))
        try send(.leftMouseUp, at: CGPoint(x: start.x - 25, y: start.y + 80))
        let moved = panel.frame
        #expect(moved.origin == CGPoint(x: original.minX, y: original.minY + 80))
        #expect(!hosting.isDragging && panel.isVisible && MagneticDesktopSettings(defaults: defaults).isCollapsed)
        #expect(app.keyWindow === keyWindow)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)

        controller.refresh(force: true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(panel.frame == moved && panel.contentView === hosting)
        start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 10, y: start.y + 10000))
        try send(.leftMouseUp, at: CGPoint(x: start.x - 10, y: start.y + 10000))
        #expect(panel.frame.maxX == screen.maxX && panel.frame.maxY == screen.maxY)
        #expect(screen.contains(panel.frame))
        start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseDragged, at: CGPoint(x: start.x + 10000, y: start.y - 10000))
        try send(.leftMouseUp, at: CGPoint(x: start.x + 10000, y: start.y - 10000))
        #expect(panel.frame.maxX == screen.maxX && panel.frame.minY == screen.minY)

        let clamped = panel.frame
        start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start)
        controller.suspendForCapture()
        #expect(!panel.isVisible && !hosting.isDragging)
        controller.resumeAfterCapture()
        try await waitUntil { panel.isVisible }
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 40, y: start.y + 40))
        try send(.leftMouseUp, at: CGPoint(x: start.x - 40, y: start.y + 40))
        #expect(panel.frame == clamped && MagneticDesktopSettings(defaults: defaults).isCollapsed)

        start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 1, y: start.y + 1))
        try send(.leftMouseUp, at: CGPoint(x: start.x - 1, y: start.y + 1))
        try await waitUntil { !panel.isVisible && controller.boxPanel?.isVisible == true }
        #expect(!MagneticDesktopSettings(defaults: defaults).isCollapsed)
        controller.setCollapsed(true)
        try await waitUntil { panel.isVisible }
        #expect(panel.frame == clamped)

        screen = CGRect(x: -400, y: 0, width: 600, height: 400)
        controller.refresh(force: true)
        try await waitUntil { screen.contains(panel.frame) }
        #expect(panel.frame.size == MagneticDesktopGeometry.foldedFrame(in: screen).size)
        #expect(panel.frame.maxX == screen.maxX)
        #expect(MagneticDesktopSettings(defaults: defaults).isCollapsed)
    }

    @Test("A deliberate pull morphs the folded strip into a free stack, preserves its grab point and snaps it back")
    func nativeFoldedDetachment() async throws {
        let app = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticFoldedDetach-\(UUID())")
        let suite = "MagneticFoldedDetachTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        let screen = CGRect(x: 100, y: -100, width: 1200, height: 800)
        var reducedMotion = false
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { reducedMotion }, screenFrames: { [screen] })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        let panel = try #require(controller.foldedPanel)
        let hosting = try #require(panel.contentView as? MagneticFoldedHostingView)
        let keyWindow = app.keyWindow
        func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 10, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
            panel.sendEvent(event)
        }
        let start = CGPoint(x: panel.frame.minX + 2, y: panel.frame.midY)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseDragged, at: CGPoint(x: start.x - 63, y: start.y))
        #expect(!controller.foldedIsDetached && panel.frame.maxX == screen.maxX)
        let detachedPoint = CGPoint(x: start.x - 80, y: start.y + 8)
        try send(.leftMouseDragged, at: detachedPoint)
        #expect(controller.foldedIsDetached && hosting.rootView.motion.progress == 1)
        #expect(panel.frame.size == CGSize(width: 96, height: 112))
        #expect(panel.frame.contains(detachedPoint) && panel.frame.maxX < screen.maxX - 16)
        if ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" {
            try await Task.sleep(for: .milliseconds(80))
            try snapshot(panel, to: "/private/tmp/PinboardShot-folded-detaching.png")
        }
        let firstPose = panel.frame
        _ = try store.add(syntheticImage(1))
        try await waitUntil { hosting.rootView.count == 2 }
        #expect(panel.contentView === hosting && hosting.isDragging && panel.frame == firstPose)
        let movedPoint = CGPoint(x: detachedPoint.x - 80, y: detachedPoint.y + 40)
        try send(.leftMouseDragged, at: movedPoint)
        try send(.leftMouseUp, at: movedPoint)
        let moved = panel.frame
        #expect(moved.minX == firstPose.minX - 80 && moved.minY == firstPose.minY + 40)
        #expect(controller.foldedIsDetached && !hosting.isDragging && app.keyWindow === keyWindow)
        controller.refresh(force: true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(panel.frame == moved && hosting.rootView.motion.progress == 1)
        try await Task.sleep(for: .milliseconds(400))
        try snapshot(panel, to: "/private/tmp/PinboardShot-folded-detached.png")
        if ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" {
            for dark in [false, true] {
                panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                try await Task.sleep(for: .milliseconds(80))
                try snapshot(panel, to: dark ? "/private/tmp/PinboardShot-folded-detached-dark.png"
                    : "/private/tmp/PinboardShot-folded-detached-light.png")
            }
            panel.appearance = nil
        }

        var point = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: point)
        controller.suspendForCapture()
        #expect(!hosting.isDragging && !panel.isVisible)
        controller.resumeAfterCapture()
        try await waitUntil { panel.isVisible }
        try send(.leftMouseDragged, at: CGPoint(x: point.x - 30, y: point.y + 30))
        try send(.leftMouseUp, at: CGPoint(x: point.x - 30, y: point.y + 30))
        #expect(panel.frame == moved && controller.foldedIsDetached)
        point = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: point)
        try send(.leftMouseUp, at: point)
        try await waitUntil { !panel.isVisible && controller.boxPanel?.isVisible == true }
        controller.setCollapsed(true)
        try await waitUntil { panel.isVisible }
        #expect(panel.frame == moved && controller.foldedIsDetached)

        point = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: point)
        let snapPoint = CGPoint(x: screen.maxX - 10, y: point.y + 15)
        try send(.leftMouseDragged, at: snapPoint)
        #expect(!controller.foldedIsDetached && hosting.rootView.motion.progress == 0)
        #expect(panel.frame.maxX == screen.maxX && panel.frame.width == 32)
        try send(.leftMouseUp, at: snapPoint)
        #expect(MagneticDesktopSettings(defaults: defaults).isCollapsed)
        try await Task.sleep(for: .milliseconds(400))
        try snapshot(panel, to: "/private/tmp/PinboardShot-folded-reattached.png")

        reducedMotion = true
        point = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: point)
        let offscreen = CGPoint(x: point.x - 10000, y: point.y - 10000)
        try send(.leftMouseDragged, at: offscreen)
        try send(.leftMouseUp, at: offscreen)
        #expect(!controller.foldedIsDetached && hosting.rootView.motion.progress == 0)
        #expect(screen.contains(panel.frame) && panel.frame.minX == screen.minX && panel.frame.minY == screen.minY)
    }

    @Test("Docking uses the nearest edge within sixteen points and preserves the edge at corner ties")
    func foldedDockingThresholds() {
        let screen = CGRect(x: -100, y: 50, width: 1000, height: 800)
        #expect(MagneticDockEdge.nearest(to: CGRect(x: 200, y: 300, width: 96, height: 112),
                                        in: screen, preferring: .right) == nil)
        #expect(MagneticDockEdge.nearest(to: CGRect(x: -84, y: 300, width: 96, height: 112),
                                        in: screen, preferring: .right) == .left)
        #expect(MagneticDockEdge.nearest(to: CGRect(x: -83, y: 300, width: 96, height: 112),
                                        in: screen, preferring: .right) == nil)
        let corner = CGRect(x: -100, y: 50, width: 96, height: 112)
        #expect(MagneticDockEdge.nearest(to: corner, in: screen, preferring: .bottom) == .bottom)
        #expect(MagneticDockEdge.nearest(to: corner, in: screen, preferring: .left) == .left)
        #expect(MagneticDockEdge.nearest(to: corner.offsetBy(dx: 8, dy: 12), in: screen, preferring: .bottom) == .left)
    }

    @Test("Folded handles snap to all four edges and keep their edge through compacting, hover and capture",
          arguments: MagneticDockEdge.allCases, [true, false])
    func nativeFoldedEdgeDocking(edge: MagneticDockEdge, motionReduced: Bool) async throws {
        let app = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticEdges-\(UUID())")
        let suite = "MagneticEdgesTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        let screen = CGRect(x: -500, y: 40, width: 1000, height: 800)
        var now: TimeInterval = 0
        var pointer = CGPoint(x: -10000, y: -10000)
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { motionReduced }, pointerLocation: { pointer }, idleClock: { now }, screenFrames: { [screen] })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        let panel = try #require(controller.foldedPanel)
        let hosting = try #require(panel.contentView as? MagneticFoldedHostingView)
        let keyWindow = app.keyWindow
        func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 10, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
            panel.sendEvent(event)
        }
        try send(.leftMouseDown, at: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        try send(.leftMouseDragged, at: CGPoint(x: screen.midX, y: screen.midY))
        try send(.leftMouseUp, at: CGPoint(x: screen.midX, y: screen.midY))
        #expect(controller.foldedIsDetached)
        let target: CGPoint
        switch edge {
        case .right: target = CGPoint(x: screen.maxX - 8, y: screen.midY)
        case .left: target = CGPoint(x: screen.minX + 8, y: screen.midY)
        case .top: target = CGPoint(x: screen.midX, y: screen.maxY - 8)
        case .bottom: target = CGPoint(x: screen.midX, y: screen.minY + 8)
        }
        try send(.leftMouseDown, at: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        try send(.leftMouseDragged, at: target)
        try send(.leftMouseUp, at: target)
        #expect(!controller.foldedIsDetached && controller.foldedDockEdge == edge)
        #expect(hosting.rootView.motion.dockEdge == edge && hosting.rootView.motion.progress == 0)
        let docked = panel.frame
        #expect(docked.size == (edge.isHorizontal ? CGSize(width: 144, height: 32) : CGSize(width: 32, height: 144)))
        func touchesEdge() -> Bool {
            switch edge {
            case .right: panel.frame.maxX == screen.maxX
            case .left: panel.frame.minX == screen.minX
            case .top: panel.frame.maxY == screen.maxY
            case .bottom: panel.frame.minY == screen.minY
            }
        }
        #expect(touchesEdge() && screen.contains(docked))
        controller.refresh(force: true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(panel.frame == docked && panel.contentView === hosting)
        now = 8
        controller.checkForFoldedIdleCollapse()
        #expect(controller.foldedIsCompact && touchesEdge())
        #expect(panel.frame.size == (edge.isHorizontal ? CGSize(width: 56, height: 20) : CGSize(width: 20, height: 56)))
        if motionReduced {
            #expect(controller.foldedBubblePanel?.isVisible != true)
        } else {
            let bubbles = try #require(controller.foldedBubblePanel)
            #expect(bubbles.isVisible && bubbles.ignoresMouseEvents && screen.contains(bubbles.frame))
            let view = try #require(bubbles.contentView as? MagneticPassiveHostingView<MagneticCapsuleBubbles>)
            #expect(view.rootView.edge == edge && view.rootView.capsuleFrame == panel.frame)
        }
        if edge.isHorizontal { #expect(panel.frame.midX == docked.midX) }
        else { #expect(panel.frame.midY == docked.midY) }
        pointer = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        controller.updateHover(at: pointer)
        #expect(!controller.foldedIsCompact && panel.frame == docked)
        #expect(controller.foldedBubblePanel?.isVisible != true)
        pointer = CGPoint(x: -10000, y: -10000)
        controller.updateHover(at: pointer)
        controller.suspendForCapture()
        controller.resumeAfterCapture()
        try await waitUntil { panel.isVisible }
        #expect(panel.frame == docked && controller.foldedDockEdge == edge)
        try send(.leftMouseDown, at: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        try send(.leftMouseUp, at: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        try await waitUntil { controller.boxPanel?.isVisible == true && !panel.isVisible }
        controller.setCollapsed(true)
        try await waitUntil { panel.isVisible }
        #expect(controller.foldedDockEdge == edge && panel.frame == docked)
        let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let inward: CGPoint
        switch edge {
        case .right: inward = CGPoint(x: -96, y: 0)
        case .left: inward = CGPoint(x: 96, y: 0)
        case .top: inward = CGPoint(x: 0, y: -96)
        case .bottom: inward = CGPoint(x: 0, y: 96)
        }
        let detached = CGPoint(x: start.x + inward.x, y: start.y + inward.y)
        try send(.leftMouseDown, at: start)
        try send(.leftMouseDragged, at: detached)
        try send(.leftMouseUp, at: detached)
        #expect(controller.foldedIsDetached && screen.contains(panel.frame))
        #expect(app.keyWindow === keyWindow)
    }

    @Test("Folded capsule crosses displays, docks and keeps its destination through refresh, capture and expansion",
          arguments: MagneticDockEdge.allCases, [
            CGRect(x: 1200, y: 0, width: 1000, height: 800),
            CGRect(x: -1100, y: -100, width: 1000, height: 900),
            CGRect(x: 0, y: 900, width: 1200, height: 800)
          ])
    func nativeFoldedMultipleScreens(edge: MagneticDockEdge, targetScreen: CGRect) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticFoldedScreens-\(UUID())")
        let suite = "MagneticFoldedScreensTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        // Keep the synthetic upper display's tray within the real desktop's vertical range;
        // AppKit otherwise constrains normal-level panels to the only physically connected display.
        let ceiling = try #require(NSScreen.screens.first?.visibleFrame.maxY)
        let primary = CGRect(x: 0, y: 0, width: 1200, height: (ceiling * 0.4).rounded(.down))
        let targetScreen = targetScreen.minY > primary.maxY
            ? CGRect(x: 0, y: (ceiling * 0.5).rounded(.down), width: 1200,
                     height: (ceiling * 0.4).rounded(.down)) : targetScreen
        var screens = [primary, targetScreen]
        var now: TimeInterval = 0
        let pointer = CGPoint(x: -10000, y: -10000)
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { false }, pointerLocation: { pointer }, idleClock: { now }, screenFrames: { screens })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        let panel = try #require(controller.foldedPanel)
        let hosting = try #require(panel.contentView as? MagneticFoldedHostingView)
        func send(_ type: NSEvent.EventType, at point: CGPoint, timestamp: TimeInterval) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: timestamp, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
            panel.sendEvent(event)
        }
        func drag(to point: CGPoint, timestamp: TimeInterval) throws {
            let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            try send(.leftMouseDown, at: start, timestamp: timestamp)
            try send(.leftMouseDragged, at: point, timestamp: timestamp + 1)
            try send(.leftMouseUp, at: point, timestamp: timestamp + 1.5)
        }
        let entryPoint: CGPoint
        let gapPoint: CGPoint?
        let entryEdge: MagneticDockEdge
        if targetScreen.minX >= primary.maxX {
            entryPoint = CGPoint(x: targetScreen.minX + 8, y: primary.midY)
            gapPoint = nil
            entryEdge = .left
        } else if targetScreen.maxX <= primary.minX {
            entryPoint = CGPoint(x: targetScreen.maxX - 8, y: primary.midY)
            gapPoint = CGPoint(x: primary.minX - 1, y: primary.midY)
            entryEdge = .right
        } else {
            entryPoint = CGPoint(x: primary.midX, y: targetScreen.minY + 8)
            gapPoint = CGPoint(x: primary.midX, y: primary.maxY + 1)
            entryEdge = .bottom
        }
        let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: start, timestamp: 10)
        if let gapPoint {
            try send(.leftMouseDragged, at: gapPoint, timestamp: 11)
            #expect(primary.contains(panel.frame))
        }
        try send(.leftMouseDragged, at: entryPoint, timestamp: 12)
        try send(.leftMouseUp, at: entryPoint, timestamp: 12.5)
        #expect(targetScreen.contains(panel.frame))
        #expect(!controller.foldedIsDetached && controller.foldedDockEdge == entryEdge)

        try drag(to: CGPoint(x: targetScreen.midX, y: targetScreen.midY), timestamp: 20)
        #expect(controller.foldedIsDetached && targetScreen.contains(panel.frame))
        let dockPoint: CGPoint
        switch edge {
        case .right: dockPoint = CGPoint(x: targetScreen.maxX - 8, y: targetScreen.midY)
        case .left: dockPoint = CGPoint(x: targetScreen.minX + 8, y: targetScreen.midY)
        case .top: dockPoint = CGPoint(x: targetScreen.midX, y: targetScreen.maxY - 8)
        case .bottom: dockPoint = CGPoint(x: targetScreen.midX, y: targetScreen.minY + 8)
        }
        try drag(to: dockPoint, timestamp: 30)
        #expect(!controller.foldedIsDetached && controller.foldedDockEdge == edge)
        let docked = panel.frame
        #expect(targetScreen.contains(docked))
        controller.refresh(force: true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(panel.frame == docked && panel.contentView === hosting)

        _ = try store.add(syntheticImage(1))
        controller.refresh(force: true)
        try await waitUntil { hosting.rootView.count == 2 }
        screens = [targetScreen, primary]
        controller.refresh(force: true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(panel.frame == docked && targetScreen.contains(panel.frame))
        now = 8
        controller.checkForFoldedIdleCollapse()
        #expect(controller.foldedIsCompact && targetScreen.contains(panel.frame))
        let bubbles = try #require(controller.foldedBubblePanel)
        #expect(bubbles.isVisible && bubbles.ignoresMouseEvents && targetScreen.contains(bubbles.frame))
        let bubbleView = try #require(bubbles.contentView as? MagneticPassiveHostingView<MagneticCapsuleBubbles>)
        #expect(bubbleView.rootView.edge == edge && bubbleView.rootView.capsuleFrame == panel.frame)
        controller.updateHover(at: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        #expect(!controller.foldedIsCompact && !bubbles.isVisible && panel.frame.size == docked.size)
        controller.updateHover(at: pointer)
        now = 16
        controller.checkForFoldedIdleCollapse()
        #expect(controller.foldedIsCompact && bubbles.isVisible)
        let compact = panel.frame
        controller.suspendForCapture()
        controller.resumeAfterCapture()
        try await waitUntil { panel.isVisible }
        #expect(panel.frame == compact && controller.foldedDockEdge == edge)

        let click = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try send(.leftMouseDown, at: click, timestamp: 40)
        try send(.leftMouseUp, at: click, timestamp: 40.5)
        try await waitUntil { controller.boxPanel?.isVisible == true && !panel.isVisible && controller.cardPanels.count == 2 }
        let boxFrame = try #require(controller.boxPanel?.frame)
        #expect(targetScreen.contains(boxFrame), "Box frame: \(boxFrame), target: \(targetScreen)")
        #expect(controller.cardPanels.values.allSatisfy { targetScreen.contains($0.frame) })
        controller.setCollapsed(true)
        try await waitUntil { panel.isVisible }
        #expect(panel.frame == docked && controller.foldedDockEdge == edge && targetScreen.contains(panel.frame))

        screens = [primary]
        controller.refresh(force: true)
        try await waitUntil { panel.isVisible && primary.contains(panel.frame) }
        screens = [targetScreen, primary]
        controller.refresh(force: true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(panel.isVisible && primary.contains(panel.frame))
    }

    @Test("Capsule bubbles are click-through, pause near the pointer and release their timeline when hidden")
    func capsuleBubbleLifecycle() async throws {
        let app = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagneticBubbles-\(UUID())")
        let suite = "MagneticBubblesTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: MagneticDesktopSettings.enabledKey)
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        let store = HistoryStore(fileManager: MagneticFileManager(root: root), defaults: defaults)
        _ = try store.add(syntheticImage(0))
        let screen = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let outside = CGPoint(x: -10000, y: -10000)
        var pointer = outside
        var now: TimeInterval = 0
        var systemReduced = false
        let controller = MagneticDesktopController(historyStore: store, defaults: defaults,
            reduceMotion: { systemReduced }, pointerLocation: { pointer }, idleClock: { now }, screenFrames: { [screen] })
        defer { controller.stop() }
        controller.start()
        try await waitUntil { controller.foldedPanel?.isVisible == true }
        #expect(controller.foldedBubblePanel == nil)
        let capsule = try #require(controller.foldedPanel)
        let keyWindow = app.keyWindow
        now = 8
        controller.checkForFoldedIdleCollapse()
        let bubblePanel = try #require(controller.foldedBubblePanel)
        #expect(bubblePanel.isVisible && bubblePanel.ignoresMouseEvents)
        #expect(!bubblePanel.canBecomeKey && !bubblePanel.canBecomeMain && bubblePanel.sharingType == .none)
        #expect(!bubblePanel.hasShadow && bubblePanel.level == capsule.level)
        #expect(screen.contains(bubblePanel.frame))
        if ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" {
            let hosting = try #require(bubblePanel.contentView as? MagneticPassiveHostingView<MagneticCapsuleBubbles>)
            let preview = hosting.rootView
                .frame(width: bubblePanel.frame.width, height: bubblePanel.frame.height)
                .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: preview)
            renderer.scale = 4
            let image = try #require(renderer.cgImage)
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/private/tmp/PinboardShot-capsule-bubbles.png"))
        }
        let compact = capsule.frame
        pointer = CGPoint(x: compact.minX - 10, y: compact.midY)
        controller.updateHover(at: pointer)
        #expect(controller.foldedIsCompact && capsule.frame == compact)
        #expect(!bubblePanel.isVisible && bubblePanel.contentView == nil)
        pointer = outside
        controller.updateHover(at: pointer)
        #expect(bubblePanel.isVisible && capsule.frame == compact)
        for style in [MagneticAnimationStyle.simple, .elastic, .arc, .full] {
            defaults.set(style.rawValue, forKey: MagneticDesktopSettings.animationStyleKey)
            controller.refresh()
            try await waitUntil { bubblePanel.isVisible == (style != .simple) }
            if style == .simple { #expect(bubblePanel.contentView == nil) }
        }
        defaults.set(true, forKey: MagneticDesktopSettings.reduceMotionKey)
        controller.refresh()
        try await waitUntil { !bubblePanel.isVisible }
        #expect(bubblePanel.contentView == nil)
        defaults.set(false, forKey: MagneticDesktopSettings.reduceMotionKey)
        controller.refresh()
        try await waitUntil { bubblePanel.isVisible }
        systemReduced = true
        controller.refresh(force: true)
        try await waitUntil { !bubblePanel.isVisible }
        systemReduced = false
        controller.refresh(force: true)
        try await waitUntil { bubblePanel.isVisible }
        controller.suspendForCapture()
        #expect(!bubblePanel.isVisible && bubblePanel.contentView == nil)
        controller.resumeAfterCapture()
        try await waitUntil { bubblePanel.isVisible }
        #expect(capsule.frame == compact && app.keyWindow === keyWindow)
        controller.stop()
        #expect(!bubblePanel.isVisible && bubblePanel.contentView == nil && controller.foldedBubblePanel == nil)
    }

    @Test("Ordinary pins retain normal mouse behavior without source-return callbacks")
    func ordinaryPinDoubleClick() throws {
        _ = NSApplication.shared
        var closed = 0
        let pin = PinWindowController(id: UUID(), image: syntheticImage(1), hasShadow: true,
            onClose: { _ in closed += 1 })
        defer { pin.close() }
        pin.show(near: CGPoint(x: 300, y: 300))
        let panel = try #require(pin.window as? NSPanel)
        let original = panel.frame
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type,
                location: CGPoint(x: original.width / 2, y: original.height / 2), modifierFlags: [],
                timestamp: 90, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 2, pressure: 0))
            panel.sendEvent(event)
        }
        #expect(closed == 0 && panel.isVisible && panel.frame == original)
        #expect(pin.onReturnToSource == nil)
        #expect(pin.onCenterSourceGroup == nil && pin.canCenterSourceGroup == nil)
        #expect(pin.onSourceGeometryWillChange == nil && pin.onSourceGeometryChanged == nil)
    }

    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(15))
        }
        try #require(condition(), "Native magnetic panels did not settle", sourceLocation: sourceLocation)
    }

    private func syntheticImage(_ index: Int) -> NSImage {
        let image = NSImage(size: CGSize(width: 240, height: 140))
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        CGRect(origin: .zero, size: image.size).fill()
        NSColor.systemBlue.withAlphaComponent(0.7).setFill()
        for column in 0..<4 {
            NSBezierPath(roundedRect: CGRect(x: 20 + column * 53, y: 22, width: 35,
                height: 28 + (index + column * 11) % 70), xRadius: 4, yRadius: 4).fill()
        }
        image.unlockFocus()
        return image
    }

    private func snapshotTrayStates(item: HistoryItem) async throws {
        guard ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" else { return }
        let motion = MagneticBoxMotion()
        let images = (0..<5).map { index in
            let image = NSImage(size: CGSize(width: 180, height: 120))
            image.lockFocus()
            [NSColor.systemPurple, .systemPink, .systemTeal, .systemOrange, .systemBlue][index].setFill()
            CGRect(origin: .zero, size: image.size).fill()
            NSColor.white.withAlphaComponent(0.7).setFill()
            NSBezierPath(ovalIn: CGRect(x: 25 + index * 9, y: 48, width: 70, height: 70)).fill()
            NSColor.black.withAlphaComponent(0.14).setFill()
            CGRect(x: 0, y: 0, width: 180, height: 42).fill()
            image.unlockFocus()
            return image
        }
        for isDark in [false, true] {
            let panel = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 660, height: 220),
                styleMask: [.borderless], backing: .buffered, defer: false)
            panel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            panel.contentView = NSHostingView(rootView: HStack(spacing: 30) {
                ForEach(0..<3) { index in
                    VStack(spacing: 12) {
                        MagneticBoxView(images: Array(images.prefix([0, 1, 5][index])), count: [0, 1, 37][index],
                            desktopCount: 3, motion: motion,
                            onReturnAll: {}, onOpen: {}, onCollapse: {})
                        Text(["空托盘", "一张截图", "多张截图"][index])
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(30).frame(width: 660, height: 220)
            .environment(\.colorScheme, isDark ? .dark : .light)
            .background(LinearGradient(colors: isDark
                ? [Color(red: 0.15, green: 0.18, blue: 0.22), Color(red: 0.07, green: 0.10, blue: 0.14)]
                : [Color(red: 0.89, green: 0.91, blue: 0.94), Color(red: 0.74, green: 0.82, blue: 0.88)],
                startPoint: .topLeading, endPoint: .bottomTrailing)))
            panel.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(60))
            try snapshot(panel, to: isDark ? "/private/tmp/PinboardShot-magnetic-tray-preview-dark.png"
                : "/private/tmp/PinboardShot-magnetic-tray-preview.png")
            panel.close()
        }
        let contextPanel = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 600, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        contextPanel.appearance = NSAppearance(named: .aqua)
        func card(_ index: Int, expanded: Bool) -> MagneticCardView {
            MagneticCardView(image: syntheticImage(index), item: item, isExpanded: expanded,
                onExtract: {}, onReturn: {}, onReturnAll: {}, motion: MagneticCardMotion(),
                onCopy: {}, onPin: {}, onEdit: {}, onDrag: { _, _, _ in })
        }
        contextPanel.contentView = NSHostingView(rootView: HStack(spacing: 20) {
            card(2, expanded: true).frame(width: 310, height: 240)
            VStack(spacing: 12) {
                card(1, expanded: false).frame(width: 112, height: 88)
                card(3, expanded: false).frame(width: 112, height: 88)
                MagneticBoxView(images: images, count: 37, desktopCount: 3, motion: motion,
                    onReturnAll: {}, onOpen: {}, onCollapse: {})
            }
        }
        .padding(30).frame(width: 600, height: 400)
        .environment(\.colorScheme, .light)
        .background(LinearGradient(colors: [Color(red: 0.89, green: 0.91, blue: 0.94),
            Color(red: 0.74, green: 0.82, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        contextPanel.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(60))
        try snapshot(contextPanel, to: "/private/tmp/PinboardShot-magnetic-tray-context.png")
        contextPanel.close()

        let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 200, y: 200),
            size: MagneticDesktopGeometry.boxSize), styleMask: [.borderless], backing: .buffered, defer: false)
        defer { panel.close() }
        panel.appearance = NSAppearance(named: .aqua)
        panel.contentView = NSHostingView(rootView: MagneticBoxView(images: images, count: 37,
            desktopCount: 3, motion: motion, onReturnAll: {}, onOpen: {}, onCollapse: {}))
        panel.orderFrontRegardless()
        // Render peak lift inside the actual panel bounds, not a padded presentation canvas.
        for (index, progress) in [CGFloat(1), 0.25, 0.5, 0.75].enumerated() {
            motion.progress = progress
            try await Task.sleep(for: .milliseconds(60))
            try snapshot(panel, to: "/private/tmp/PinboardShot-magnetic-tray-motion-\(index).png")
        }
    }

    private func snapshotRail(_ controller: MagneticDesktopController) async throws {
        guard ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" else { return }
        let screen = try #require(NSScreen.screens.first?.visibleFrame)
        let panels = Array(controller.cardPanels.values) + [controller.boxPanel, controller.pagerPanel].compactMap { $0 }
        for dark in [false, true] {
            panels.forEach { $0.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
            try await Task.sleep(for: .milliseconds(80))
            let canvas = NSImage(size: CGSize(width: 260, height: screen.height))
            canvas.lockFocus()
            (dark ? NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.19, alpha: 1)
                  : NSColor(calibratedRed: 0.87, green: 0.91, blue: 0.95, alpha: 1)).setFill()
            CGRect(origin: .zero, size: canvas.size).fill()
            for panel in panels {
                let view = try #require(panel.contentView)
                view.layoutSubtreeIfNeeded()
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                NSImage(cgImage: try #require(bitmap.cgImage), size: panel.frame.size).draw(in:
                    CGRect(x: panel.frame.minX - screen.maxX + 260, y: panel.frame.minY - screen.minY,
                           width: panel.frame.width, height: panel.frame.height))
            }
            canvas.unlockFocus()
            let tiff = try #require(canvas.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to:
                URL(fileURLWithPath: dark ? "/private/tmp/PinboardShot-magnetic-fan-dark.png"
                    : "/private/tmp/PinboardShot-magnetic-fan-light.png"))
        }
        panels.forEach { $0.appearance = nil }
    }

    private func snapshot(_ panel: NSPanel?, to path: String) throws {
        // Native visual checks are opt-in; normal test runs leave no screenshot artifacts.
        guard ProcessInfo.processInfo.environment["PINBOARDSHOT_MAGNETIC_VISUAL_CHECK"] == "1" else { return }
        let view = try #require(panel?.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path))
    }

}

@MainActor
@objc(PinboardShotNativeMenuSmoke)
final class PinboardShotNativeMenuSmoke: NSObject {
    @objc func runProgressiveSmoke() {
        Task { @MainActor in
            do {
                try await MagneticDesktopTests().fanCapacityLifecycle()
                try await MagneticDesktopTests().progressiveLifecycle()
                try await MagneticDesktopTests().nativeBoxScrollContainment()
                try await MagneticDesktopTests().nativeBoxClickForwarding()
                print("Native progressive smoke passed: all 100 images, ten-card groups, twenty-image pages, passive previews, source pins, capture, deletion, folding and input focus")
                exit(0)
            } catch {
                print("Native progressive smoke failed: \(error)")
                exit(1)
            }
        }
    }

    @objc func runFoldedSmoke() {
        Task { @MainActor in
            do {
                try await MagneticDesktopTests().foldingLifecycle()
                try await MagneticDesktopTests().fanTransitionLifecycle()
                try await MagneticDesktopTests().nativeFoldedDragging()
                try await MagneticDesktopTests().nativeFoldedDetachment()
                for edge in MagneticDockEdge.allCases {
                    for targetScreen in [CGRect(x: 1200, y: 0, width: 1000, height: 800),
                                         CGRect(x: -1100, y: -100, width: 1000, height: 900),
                                         CGRect(x: 0, y: 900, width: 1200, height: 800)] {
                        try await MagneticDesktopTests().nativeFoldedMultipleScreens(edge: edge, targetScreen: targetScreen)
                    }
                }
                try await MagneticDesktopTests().secondFoldLifecycle()
                try await MagneticDesktopTests().automaticSecondFoldTimer()
                try await MagneticDesktopTests().nativeBoxClickForwarding()
                print("Native folded smoke passed: edge sliding, elastic detachment, free dragging, snap-back, capture recovery and focus preservation")
                exit(0)
            } catch {
                print("Native folded fan smoke failed: \(error)")
                exit(1)
            }
        }
    }

    @objc func runSmoke() {
        Task { @MainActor in
            do {
                try await MagneticDesktopTests().nativeContextMenuTracking()
                try await MagneticDesktopTests().nativeCenterGroupMenu()
                try await MagneticDesktopTests().nativeBoxClickForwarding()
                print("Native magnetic smoke passed: 3 zoom/return menu cycles; real group-centering menu; outside-click forwarding and idle-fold activation state")
                exit(0)
            } catch {
                print("Native magnetic smoke failed: \(error)")
                exit(1)
            }
        }
    }
}
