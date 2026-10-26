import AppKit
import Combine
import SwiftUI

private final class MagneticDesktopPanel: NSPanel {
    // Rail and box controls must leave keyboard focus in the app where the user is typing.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var onInteraction: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
            .rightMouseDown, .scrollWheel, .keyDown].contains(event.type) { onInteraction?() }
        if event.type == .scrollWheel, let hosting = contentView as? MagneticBoxContentsHostingView {
            hosting.scrollWheel(with: event)
            return
        }
        if let hosting = contentView as? MagneticCardHostingView, hosting.handleMouseEvent(event) { return }
        if let hosting = contentView as? MagneticBoxHostingView, hosting.handleMouseEvent(event) { return }
        if let hosting = contentView as? MagneticFoldedHostingView, hosting.handleMouseEvent(event) { return }
        super.sendEvent(event)
    }
}

@MainActor
final class MagneticDesktopController {
    private let historyStore: HistoryStore
    private let defaults: UserDefaults
    private let reduceMotion: () -> Bool
    private let pointerLocation: () -> CGPoint
    private let screenFrames: () -> [CGRect]
    private let pinManager: PinWindowManager
    private let ownsPinManager: Bool
    private(set) var desktopPins: [UUID: PinWindowController] = [:]
    private var homes: [UUID: MagneticCardHome] = [:]
    private let boxMotion = MagneticBoxMotion()
    private var boxPreferredOrigin: CGPoint?
    private var foldedPreferredOrigin: CGPoint?
    private var magneticScreenFrame: CGRect?
    private let foldedMotion = MagneticFoldedMotion()
    private(set) var foldedDockEdge: MagneticDockEdge = .right
    private(set) var foldedIsDetached = false
    private(set) var foldedIsCompact = false
    private var foldedIsHovered = false
    private let foldedIdleTimeout: TimeInterval
    private var lastFoldedInteraction: TimeInterval?
    private var foldedIdleTask: Task<Void, Never>?
    private var foldedDragStart: (point: CGPoint, anchor: CGPoint, detached: Bool)?
    private var boxTask: Task<Void, Never>?
    private var boxGeneration = 0
    private var subscriptions: [AnyCancellable] = []
    private var refreshTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var hoveredID: UUID?
    private var boxHoverTask: Task<Void, Never>?
    private var boxHoveredID: UUID?
    private(set) var boxPreviewPanel: NSPanel?
    private let idleTimeout: TimeInterval
    private let idleClock: () -> TimeInterval
    private var lastInteraction: TimeInterval = 0
    private var idleTask: Task<Void, Never>?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var isReconciling = false
    private var queue = MagneticDesktopQueue()
    private var thumbnails: [UUID: NSImage] = [:]
    private(set) var desktopFrames: [UUID: CGRect] = [:]
    private var desktopOrder: [UUID] = []
    private var pendingFlights: [UUID: MagneticFlightDirection] = [:]
    private var cardMotions: [UUID: MagneticCardMotion] = [:]
    private let trailState = MagneticFlightTrailState()
    private(set) var trailPanel: NSPanel?
    private var dockFlightPanels: [NSPanel] = []
    private var effectGeneration = 0
    private let fanMotion = MagneticFanMotion()
    private var fanPanels: [NSPanel] = []
    private(set) var fanAnimationPanel: NSPanel?
    private var dockMotionView: MagneticDockMotionView?
    var fanAnimationProgress: CGFloat { dockMotionView?.progress ?? fanMotion.progress }
    private var dragVelocity = MagneticDragVelocity()
    private var dragStart: (id: UUID, mouse: CGPoint, origin: CGPoint)?
    private var desktopLayoutWasAdjusted = false
    private var desktopCenterRequest: Bool? // true is an explicit request; false is membership-driven.
    private var desktopCenterGeneration: Int?
    private var suspended = false
    private var lastSettings: MagneticDesktopSettings?
    private var lastHistoryEnabled: Bool?
    private var lastIDs: [UUID] = []
    private var refreshGeneration = 0
    private var hasPresented = false
    private var shouldRestoreContents = false
    private(set) var cardPanels: [UUID: NSPanel] = [:]
    private(set) var boxPanel: NSPanel?
    private(set) var contentsPanel: NSPanel?
    private(set) var hoverPanel: NSPanel?
    private(set) var foldedPanel: NSPanel?
    private(set) var foldedBubblePanel: NSPanel?
    private(set) var pagerPanel: NSPanel?
    private var collectionPage = 0
    private var focusedRailID: UUID?
    private var pendingRailPreview: UUID?
    private var lastRailPage = 0
    var onCopy: ((HistoryItem) -> Void)?
    var onEdit: ((HistoryItem) -> Void)?

    private var partition: (visible: [UUID], boxed: [UUID]) {
        queue.partition(limit: settings.maximumVisible, excluding: Set(desktopFrames.keys))
    }
    var overflowCount: Int { partition.boxed.count }
    var railPageIndex: Int { queue.pageIndex }
    private var fanIDs: [UUID] { queue.fanIDs(limit: settings.maximumVisible, excluding: Set(desktopFrames.keys)) }
    var railPageCount: Int {
        max(1, (fanIDs.count + MagneticDesktopSettings.maximumCardsPerGroup - 1) / MagneticDesktopSettings.maximumCardsPerGroup)
    }
    var collectionPageIndex: Int { collectionPage }
    private var collectionItems: [HistoryItem] { historyStore.items.filter { desktopFrames[$0.id] == nil } }
    private var collectionPageItems: [HistoryItem] { Array(collectionItems.dropFirst(collectionPage * 20).prefix(20)) }
    var activeFlightCount: Int { trailState.flights.count }
    var boxArrivalProgress: CGFloat { boxMotion.progress }
    private var settings: MagneticDesktopSettings { MagneticDesktopSettings(defaults: defaults) }
    private var visibleFrame: CGRect? {
        let frames = screenFrames()
        guard let preferred = magneticScreenFrame else { return frames.first }
        if frames.contains(preferred) { return preferred }
        // A disconnected or rearranged display must leave the entry point on an available screen.
        return MagneticDesktopGeometry.screenFrame(for: foldedPanel?.frame ?? preferred, in: frames)
    }
    private var motionReduced: Bool { reduceMotion() || settings.reduceMotion }
    private var decorativeEffects: Bool { !motionReduced && settings.animationStyle != .simple }

    private func foldedAnimation(response: Double, damping: Double) -> Animation? {
        guard !motionReduced else { return nil }
        switch settings.animationStyle {
        case .full: return .spring(response: response, dampingFraction: damping)
        case .elastic: return .spring(response: response * 1.2, dampingFraction: 0.58)
        case .arc: return .easeInOut(duration: response)
        case .simple: return .easeOut(duration: 0.18)
        }
    }

    init(historyStore: HistoryStore, defaults: UserDefaults = .standard,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         pinManager: PinWindowManager? = nil,
         idleTimeout: TimeInterval = 60,
         foldedIdleTimeout: TimeInterval = 8,
         idleClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         screenFrames: @escaping () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) }) {
        self.idleTimeout = idleTimeout
        self.foldedIdleTimeout = foldedIdleTimeout
        self.idleClock = idleClock
        self.historyStore = historyStore
        self.defaults = defaults
        self.reduceMotion = reduceMotion
        self.pointerLocation = pointerLocation
        self.screenFrames = screenFrames
        self.pinManager = pinManager ?? PinWindowManager()
        ownsPinManager = pinManager == nil
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .mouseMoved { self.updateHover(at: self.pointerLocation()) }
                else {
                    let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? self.pointerLocation()
                    self.handleBoxClick(at: point)
                }
            }
            // Dismiss the box without swallowing the click intended for another window.
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            // AppKit delivers monitors on the main thread. Avoid delaying an old click until after reopening.
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .mouseMoved { self.updateHover(at: self.pointerLocation()) }
                else { self.handleBoxClick(at: self.pointerLocation()) }
            }
        }
        historyStore.$items.map { $0.map(\.id) }.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh(force: true) }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh(force: true) }
            }.store(in: &subscriptions)
        refresh(force: true)
        recordInteraction()
    }

    func restoreSessionPins() {
        let retained = Set(historyStore.items.map(\.id))
        for pin in pinManager.magneticPins {
            guard let source = pin.magneticSource else { continue }
            if desktopPins[source.historyItemID] === pin { continue }
            guard settings.isEnabled, HistorySettings.isEnabled(defaults: defaults),
                  retained.contains(source.historyItemID), desktopPins[source.historyItemID] == nil,
                  let frame = pin.window?.frame else {
                // Expired history and disabled magnetic mode leave the saved image as an ordinary pin.
                pin.magneticSource = nil
                continue
            }
            let id = source.historyItemID
            homes[id] = source.home
            desktopFrames[id] = frame
            desktopOrder.append(id)
            bindPin(pin, to: id)
        }
        // Restored positions are user layout, not a freshly extracted group to auto-center.
        if !desktopPins.isEmpty { desktopLayoutWasAdjusted = true }
        refresh(force: true)
    }

    func stop(closeDesktopPins: Bool = true) {
        idleTask?.cancel()
        idleTask = nil
        foldedIdleTask?.cancel()
        foldedIdleTask = nil
        lastFoldedInteraction = nil
        foldedIsHovered = false
        // Shutdown detaches live callbacks but retains the source metadata saved for recovery.
        for id in Array(desktopPins.keys) { releasePin(id, close: closeDesktopPins, keepSource: !closeDesktopPins) }
        if ownsPinManager { pinManager.closeAll() }
        stopBoxMotion()
        homes.removeAll()
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
        hoverTask?.cancel()
        hoveredID = nil
        shouldRestoreContents = false
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        subscriptions.removeAll()
        clearEffects()
        desktopFrames.removeAll()
        resetDesktopCentering()
        desktopOrder.removeAll()
        pendingFlights.removeAll()
        cardMotions.removeAll()
        dragStart = nil
        hidePanels()
        cardPanels.removeAll()
        boxPanel = nil
        boxPreferredOrigin = nil
        contentsPanel = nil
        boxPreviewPanel = nil
        hoverPanel = nil
        foldedPanel = nil
        foldedBubblePanel = nil
        foldedPreferredOrigin = nil
        magneticScreenFrame = nil
        foldedIsDetached = false
        foldedDockEdge = .right
        foldedMotion.dockEdge = .right
        foldedIsCompact = false
        foldedMotion.compactProgress = 0
        foldedMotion.progress = 0
        foldedMotion.pull = 0
        pagerPanel = nil
        thumbnails.removeAll()
    }

    func suspendForCapture() {
        interruptDesktopCentering()
        desktopCenterRequest = nil
        foldedIdleTask?.cancel()
        foldedIdleTask = nil
        foldedIsHovered = false
        idleTask?.cancel()
        idleTask = nil
        hoverTask?.cancel()
        hoveredID = nil
        hoverPanel?.orderOut(nil)
        shouldRestoreContents = contentsPanel?.isVisible == true
        refreshGeneration += 1
        suspended = true
        stopBoxMotion()
        clearEffects()
        dragStart = nil
        refreshTask?.cancel()
        hidePanels()
    }

    func resumeAfterCapture() {
        suspended = false
        refresh(force: true)
        recordInteraction()
        recordFoldedInteraction()
    }

    func refresh(force: Bool = false) {
        let current = settings
        let historyEnabled = HistorySettings.isEnabled(defaults: defaults)
        let ids = historyStore.items.map(\.id)
        guard force || current != lastSettings || ids != lastIDs || historyEnabled != lastHistoryEnabled else { return }
        guard !suspended else { return }
        if force || current.animationStyle != lastSettings?.animationStyle || current.reduceMotion != lastSettings?.reduceMotion {
            clearEffects()
            stopBoxMotion()
            hideFoldedBubbles()
        }
        lastSettings = current
        lastHistoryEnabled = historyEnabled
        lastIDs = ids
        let previousNewest = queue.recentIDs.first
        queue.synchronize(ids)
        let retained = Set(ids)
        for (id, pin) in desktopPins {
            if !retained.contains(id) { releasePin(id, close: false); homes.removeValue(forKey: id) }
            else if let pose = pin.window?.frame { desktopFrames[id] = pose }
        }
        homes = homes.filter { retained.contains($0.key) }
        desktopFrames = desktopFrames.filter { retained.contains($0.key) }
        if desktopFrames.isEmpty { resetDesktopCentering() }
        desktopOrder.removeAll { !retained.contains($0) }
        queue.setPage(queue.pageIndex, limit: current.maximumVisible, excluding: Set(desktopFrames.keys))
        collectionPage = min(collectionPage, max(0, (collectionItems.count - 1) / 20))
        if let focusedRailID, !retained.contains(focusedRailID) { self.focusedRailID = nil; pendingRailPreview = nil }
        cardMotions = cardMotions.filter { retained.contains($0.key) }
        refreshTask?.cancel()
        hoverTask?.cancel()
        hoveredID = nil
        hoverPanel?.orderOut(nil)
        refreshGeneration += 1
        guard current.isEnabled, historyEnabled, let frame = visibleFrame else {
            foldedIdleTask?.cancel()
            foldedIdleTask = nil
            lastFoldedInteraction = nil
            foldedIsHovered = false
            setFoldedCompact(false)
            idleTask?.cancel()
            idleTask = nil
            for id in Array(desktopPins.keys) { releasePin(id, close: false) }
            homes.removeAll()
            stopBoxMotion()
            clearEffects()
            desktopFrames.removeAll()
            resetDesktopCentering()
            desktopOrder.removeAll()
            pendingFlights.removeAll()
            cardMotions.removeAll()
            hidePanels()
            cardPanels.removeAll()
            thumbnails.removeAll()
            boxPanel = nil
            contentsPanel = nil
            hoverPanel = nil
            foldedPanel = nil
            hasPresented = false
            shouldRestoreContents = false
            return
        }
        if magneticScreenFrame != nil { magneticScreenFrame = frame }
        if current.isCollapsed {
            idleTask?.cancel()
            idleTask = nil
        }
        let partition = self.partition
        let items = Dictionary(uniqueKeysWithValues: historyStore.items.map { ($0.id, $0) })
        let generation = refreshGeneration
        let newCapture = previousNewest != nil && previousNewest != ids.first
        let changingPage = lastRailPage != queue.pageIndex && !newCapture
        lastRailPage = queue.pageIndex
        if newCapture { focusedRailID = nil; pendingRailPreview = nil; collectionPage = 0 }
        isReconciling = true
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.refreshGeneration { self.isReconciling = false }
            }
            if current.isCollapsed {
                await self.reconcileFolded(frame: frame, generation: generation)
            } else {
                await self.reconcile(partition: partition, items: items, frame: frame,
                                     generation: generation, newCapture: newCapture, changingPage: changingPage)
            }
            // Finish the rail flights before translating the remaining desktop group once.
            await self.performDesktopCentering(in: frame, generation: generation)
            if generation == self.refreshGeneration, !Task.isCancelled {
                self.isReconciling = false
                if let id = self.pendingRailPreview {
                    self.pendingRailPreview = nil
                    self.setHover(id, entered: true)
                }
            }
        }
    }

    private func hidePanels() {
        clearFanAnimation()
        hideFoldedBubbles()
        (boxPanel?.contentView as? MagneticBoxHostingView)?.cancelDrag()
        (foldedPanel?.contentView as? MagneticFoldedHostingView)?.cancelDrag()
        cardPanels.values.forEach { $0.orderOut(nil) }
        boxPanel?.orderOut(nil)
        closeBox()
        hoverPanel?.orderOut(nil)
        foldedPanel?.orderOut(nil)
        pagerPanel?.orderOut(nil)
        trailPanel?.orderOut(nil)
    }

    func setCollapsed(_ collapsed: Bool) {
        guard settings.isCollapsed != collapsed else { return }
        if !collapsed {
            setFoldedCompact(false)
            foldedIdleTask?.cancel()
            foldedIdleTask = nil
            lastFoldedInteraction = nil
            foldedIsHovered = false
        } else {
            lastFoldedInteraction = idleClock()
        }
        defaults.set(collapsed, forKey: MagneticDesktopSettings.collapsedKey)
        (boxPanel?.contentView as? MagneticBoxHostingView)?.cancelDrag()
        (foldedPanel?.contentView as? MagneticFoldedHostingView)?.cancelDrag()
        if collapsed {
            for id in Array(desktopFrames.keys) {
                restoreFlightProxy(id)
                pendingFlights[id] = .inward
            }
            desktopFrames.removeAll()
            resetDesktopCentering()
            desktopOrder.removeAll()
            homes.removeAll()
            dragStart = nil
            queue.returnToEdge()
            idleTask?.cancel()
            idleTask = nil
        }
        shouldRestoreContents = false
        closeBox()
        refresh(force: true)
        if !collapsed { recordInteraction() }
    }

    private func recordInteraction() {
        guard settings.isEnabled, !settings.isCollapsed, !suspended,
              HistorySettings.isEnabled(defaults: defaults) else { return }
        lastInteraction = idleClock()
        guard idleTask == nil else { return }
        idleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = max(0.1, self.idleTimeout - (self.idleClock() - self.lastInteraction))
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                guard !Task.isCancelled else { return }
                self.checkForIdleCollapse()
                if self.settings.isCollapsed { return }
            }
        }
    }

    func checkForIdleCollapse() {
        guard settings.isEnabled, !settings.isCollapsed, !suspended, !isReconciling,
              HistorySettings.isEnabled(defaults: defaults), dragStart == nil,
              (boxPanel?.contentView as? MagneticBoxHostingView)?.isDragging != true,
              activeFlightCount == 0, idleClock() - lastInteraction >= idleTimeout else { return }
        // Idle folding hides only the rail and tray. Desktop references retain their position and return home.
        defaults.set(true, forKey: MagneticDesktopSettings.collapsedKey)
        idleTask?.cancel()
        idleTask = nil
        shouldRestoreContents = false
        closeBox()
        hoverTask?.cancel()
        hoveredID = nil
        hoverPanel?.orderOut(nil)
        refresh(force: true)
    }

    private func recordFoldedInteraction() {
        guard !subscriptions.isEmpty, settings.isEnabled, settings.isCollapsed, !suspended,
              HistorySettings.isEnabled(defaults: defaults) else { return }
        lastFoldedInteraction = idleClock()
        armFoldedIdleTimer()
    }

    private func armFoldedIdleTimer() {
        guard !subscriptions.isEmpty, settings.isEnabled, settings.isCollapsed, !foldedIsDetached, !foldedIsCompact,
              !foldedIsHovered, !suspended, foldedIdleTask == nil else { return }
        if lastFoldedInteraction == nil { lastFoldedInteraction = idleClock() }
        foldedIdleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let last = self.lastFoldedInteraction else { return }
                let remaining = max(0.1, self.foldedIdleTimeout - (self.idleClock() - last))
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                guard !Task.isCancelled else { return }
                self.checkForFoldedIdleCollapse()
                if self.foldedIsCompact || self.foldedIsDetached || self.foldedIsHovered { return }
            }
        }
    }

    func checkForFoldedIdleCollapse() {
        guard settings.isEnabled, settings.isCollapsed, !suspended, !isReconciling,
              HistorySettings.isEnabled(defaults: defaults), !foldedIsDetached, !foldedIsCompact,
              !foldedIsHovered, foldedDragStart == nil,
              let panel = foldedPanel, panel.isVisible, let last = lastFoldedInteraction,
              idleClock() - last >= foldedIdleTimeout else { return }
        // A stationary pointer still protects the first fold, even if no new mouse-moved event arrives.
        if panel.frame.contains(pointerLocation()) { setFoldedHovered(true); return }
        setFoldedCompact(true)
        foldedIdleTask?.cancel()
        foldedIdleTask = nil
    }

    private func setFoldedHovered(_ hovered: Bool) {
        guard !subscriptions.isEmpty, settings.isEnabled, settings.isCollapsed, !suspended,
              foldedPanel?.isVisible == true, foldedIsHovered != hovered else { return }
        foldedIsHovered = hovered
        if hovered {
            foldedIdleTask?.cancel()
            foldedIdleTask = nil
            setFoldedCompact(false)
        }
        recordFoldedInteraction()
    }

    private func setFoldedCompact(_ compact: Bool) {
        guard foldedIsCompact != compact, !foldedIsDetached else { return }
        let center = foldedPanel?.frame.midpoint
        foldedIsCompact = compact
        withAnimation(foldedAnimation(response: 0.3, damping: 0.85)) {
            foldedMotion.compactProgress = compact ? 1 : 0
        }
        guard let frame = visibleFrame, let panel = foldedPanel, let center else { return }
        let size = resolvedFoldedFrame(in: frame).size
        foldedPreferredOrigin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        let pose = resolvedFoldedFrame(in: frame)
        foldedPreferredOrigin = pose.origin
        panel.setFrame(pose, display: true)
        updateFoldedBubbles()
    }

    private func hideFoldedBubbles() {
        foldedBubblePanel?.orderOut(nil)
        // Remove the TimelineView so a hidden effect does not keep scheduling frames.
        foldedBubblePanel?.contentView = nil
    }

    private func updateFoldedBubbles() {
        guard foldedIsCompact, !foldedIsHovered, !foldedIsDetached, foldedDragStart == nil,
              !suspended, settings.isEnabled, settings.isCollapsed, decorativeEffects,
              let capsule = foldedPanel, capsule.isVisible, let screen = visibleFrame,
              !capsule.frame.insetBy(dx: -36, dy: -36).contains(pointerLocation()) else {
            hideFoldedBubbles()
            return
        }
        let viewport = capsule.frame.insetBy(dx: -28, dy: -28).intersection(screen)
        guard !viewport.isEmpty else { hideFoldedBubbles(); return }
        let panel = foldedBubblePanel ?? makePanel(frame: viewport)
        foldedBubblePanel = panel
        if panel.isVisible, panel.frame == viewport,
           let hosting = panel.contentView as? MagneticPassiveHostingView<MagneticCapsuleBubbles>,
           hosting.rootView.capsuleFrame == capsule.frame, hosting.rootView.edge == foldedDockEdge { return }
        panel.level = capsule.level
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = MagneticPassiveHostingView(rootView:
            MagneticCapsuleBubbles(capsuleFrame: capsule.frame, viewport: viewport, edge: foldedDockEdge))
        panel.setFrame(viewport, display: true)
        panel.order(.below, relativeTo: capsule.windowNumber)
    }

    private func reconcileFolded(frame: CGRect, generation: Int) async {
        guard !Task.isCancelled, generation == refreshGeneration, !suspended else { return }
        // Release cached rail content removed by history retention or deletion even while folded.
        let retained = Set(queue.recentIDs)
        for id in cardPanels.keys.filter({ !retained.contains($0) }) {
            cardPanels.removeValue(forKey: id)?.orderOut(nil)
        }
        thumbnails = thumbnails.filter { retained.contains($0.key) }
        // Restore hidden pins after capture, but never raise existing pins over the app receiving keyboard input.
        if pinManager.pinsAreVisible {
            for (id, pin) in desktopPins where retained.contains(id) && pin.window?.isVisible != true {
                pin.showWithoutActivating()
            }
        }
        let destination = resolvedFoldedFrame(in: frame)
        let panel = foldedPanel ?? makePanel(frame: destination)
        foldedPanel = panel
        // Keep the collapsed entry point above other apps' floating panels and pop-up windows.
        panel.level = .screenSaver
        (panel as? MagneticDesktopPanel)?.onInteraction = { [weak self] in self?.recordFoldedInteraction() }
        let content = MagneticFoldedView(count: queue.recentIDs.count, motion: foldedMotion,
            onExpand: { [weak self] in self?.setCollapsed(false) },
            onHoverChanged: { [weak self] in self?.setFoldedHovered($0) })
        if let hosting = panel.contentView as? MagneticFoldedHostingView {
            // Retain the press coordinates when history changes during a drag.
            hosting.rootView = content
        } else {
            let hosting = MagneticFoldedHostingView(rootView: content)
            hosting.onDragBegan = { [weak self] in self?.beginFoldedDrag(at: $0) }
            hosting.onDrag = { [weak self] in self?.dragFolded(to: $0, ended: $1) }
            hosting.onDragCancelled = { [weak self] in self?.cancelFoldedDrag() }
            panel.contentView = hosting
        }
        panel.setFrame(destination, display: true)
        panel.orderFrontRegardless()
        updateFoldedBubbles()
        armFoldedIdleTimer()
        closeBox()
        pagerPanel?.orderOut(nil)
        let ordered = partition.visible
        let rail = ordered.compactMap { cardPanels[$0] } + cardPanels.filter {
            !ordered.contains($0.key) && desktopFrames[$0.key] == nil
        }.map(\.value)
        let moving = (rail + [boxPanel].compactMap { $0 }).filter { panel in
            panel.isVisible || fanPanels.contains(where: { $0 === panel })
        }
        pendingFlights.removeAll()
        await animateFan(moving, opening: false, in: frame, generation: generation)
        guard !Task.isCancelled, generation == refreshGeneration, !suspended else { return }
        moving.forEach { $0.orderOut(nil) }
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = MagneticDesktopPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.onInteraction = { [weak self] in self?.recordInteraction() }
        // Do not join fullscreen apps; visibleFrame also keeps the rail and box clear of the Dock.
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = .none
        return panel
    }

    private func clearFanAnimation() {
        fanAnimationPanel?.orderOut(nil)
        fanAnimationPanel?.contentView = nil
        dockMotionView = nil
        fanMotion.leaves = []
        fanPanels.removeAll()
        foldedPanel?.alphaValue = 1
    }

    private func animateFan(_ panels: [NSPanel], opening: Bool, in screen: CGRect, generation: Int) async {
        guard !panels.isEmpty, !motionReduced else { clearFanAnimation(); return }
        let simple = settings.animationStyle == .simple
        let continuing = fanAnimationPanel?.isVisible == true
        let start = continuing ? fanAnimationProgress : (opening ? CGFloat(0) : CGFloat(1))
        let end: CGFloat = opening ? 1 : 0
        let reusingLeaves = continuing && dockMotionView != nil && panels.count == fanPanels.count
            && zip(panels, fanPanels).allSatisfy { $0.0 === $0.1 }
        let leaves = reusingLeaves ? fanMotion.leaves : panels.enumerated().compactMap { index, panel -> MagneticFanLeaf? in
            guard let view = panel.contentView else { return nil }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let image = bitmap.cgImage else { return nil }
            return MagneticFanLeaf(id: index, image: NSImage(cgImage: image, size: panel.frame.size), frame: panel.frame)
        }
        guard !leaves.isEmpty else { clearFanAnimation(); return }
        fanMotion.leaves = leaves
        fanMotion.progress = start
        fanPanels = panels
        let folded = resolvedFoldedFrame(in: screen)
        let pivot: CGPoint
        if foldedIsDetached { pivot = folded.midpoint }
        else {
            switch foldedDockEdge {
            case .right: pivot = CGPoint(x: folded.maxX - 7, y: folded.minY + folded.height * 25 / 144)
            case .left: pivot = CGPoint(x: folded.minX + 7, y: folded.minY + folded.height * 25 / 144)
            case .top: pivot = CGPoint(x: folded.maxX - folded.width * 25 / 144, y: folded.maxY - 7)
            case .bottom: pivot = CGPoint(x: folded.minX + folded.width * 25 / 144, y: folded.minY + 7)
            }
        }
        let overlay = fanAnimationPanel ?? makePanel(frame: screen)
        fanAnimationPanel = overlay
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        overlay.hasShadow = false
        // Only the visual leaves move. They must never take clicks or activate another app's keyboard focus.
        overlay.ignoresMouseEvents = true
        let baseDuration = settings.animationStyle == .full ? 0.32 : 0.56
        let duration = simple ? 0.16 : max(settings.animationStyle == .full ? 0.12 : 0.16,
                                         baseDuration * Double(abs(end - start)))
        if settings.animationStyle == .full {
            let dock = MagneticDockMotionView(leaves: leaves, screen: screen, pivot: pivot,
                                             start: start, end: end, duration: duration)
            dockMotionView = dock
            overlay.contentView = dock
        } else {
            dockMotionView = nil
            overlay.contentView = MagneticPassiveHostingView(rootView:
                MagneticFanMotionView(motion: fanMotion, screenFrame: screen, pivot: pivot,
                                      simple: simple, style: settings.animationStyle))
        }
        overlay.setFrame(screen, display: true)
        overlay.orderFrontRegardless()
        panels.forEach { $0.orderOut(nil) }
        defer {
            // A cancelled transition must not hide the newer animation created by a rapid reversal.
            if generation == refreshGeneration { clearFanAnimation() }
        }
        if dockMotionView != nil {
            // Progress is derived from elapsed time so reversals remain continuous at any refresh rate.
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard !Task.isCancelled, generation == refreshGeneration, !suspended else { return }
            fanMotion.progress = end
            return
        }
        let steps = max(1, Int(duration * 60))
        for step in 0...steps {
            guard !Task.isCancelled, generation == refreshGeneration, !suspended else { return }
            fanMotion.progress = start + (end - start) * CGFloat(step) / CGFloat(steps)
            foldedPanel?.alphaValue = 1 - min(1, Double(fanMotion.progress) * 4)
            if step < steps {
                do { try await Task.sleep(for: .seconds(duration / Double(steps))) } catch { return }
            }
        }
    }

    private func motion(for id: UUID) -> MagneticCardMotion {
        if let existing = cardMotions[id] { return existing }
        let state = MagneticCardMotion()
        cardMotions[id] = state
        return state
    }

    private func clearEffects() {
        effectGeneration += 1
        cardMotions.values.forEach { $0.finish() }
        trailState.flights = []
        trailPanel?.orderOut(nil)
        trailPanel?.contentView = nil
        dockFlightPanels.forEach { $0.orderFrontRegardless() }
        dockFlightPanels.removeAll()
    }

    private func animateMany(_ targets: [(NSPanel, CGRect)], duration: TimeInterval = 0.24,
                             flights: [UUID: MagneticFlightDirection] = [:]) async {
        let changing = targets.filter { $0.0.frame != $0.1 }
        guard !changing.isEmpty else { return }
        guard !motionReduced else {
            changing.forEach { $0.0.setFrame($0.1, display: true) }
            return
        }
        let starts = changing.map { $0.0.frame }
        let style = settings.animationStyle
        let flying = decorativeEffects ? flights.filter { id, _ in changing.contains { $0.0 === cardPanels[id] } } : [:]
        var generation: Int?
        if !flying.isEmpty, let screen = visibleFrame {
            clearEffects()
            generation = effectGeneration
            for (id, direction) in flying {
                motion(for: id).style = style
                motion(for: id).begin(direction)
            }
            trailState.flights = flying.keys.compactMap { id in
                guard let index = changing.firstIndex(where: { $0.0 === cardPanels[id] }) else { return nil }
                return MagneticFlightTrail(id: id, start: starts[index].midpoint, end: changing[index].1.midpoint,
                                           progress: 0, style: style)
            }
            let trail = trailPanel ?? makePanel(frame: screen)
            trailPanel = trail
            trail.level = .normal
            trail.hasShadow = false
            trail.ignoresMouseEvents = true
            if style == .full {
                // Animate cached pixels instead of resizing SwiftUI windows and redrawing effects every frame.
                dockFlightPanels = changing.map(\.0)
                let leaves = changing.enumerated().compactMap { index, target -> MagneticFanLeaf? in
                    let panel = target.0
                    panel.orderOut(nil)
                    let capture = starts[index].width * starts[index].height > target.1.width * target.1.height
                        ? starts[index] : target.1
                    panel.setFrame(capture, display: false)
                    defer { panel.setFrame(target.1, display: false) }
                    guard let view = panel.contentView else { return nil }
                    view.layoutSubtreeIfNeeded()
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    guard let image = bitmap.cgImage else { return nil }
                    return MagneticFanLeaf(id: index, image: NSImage(cgImage: image, size: capture.size), frame: capture)
                }
                let frames = leaves.map { (start: starts[$0.id], end: changing[$0.id].1) }
                let viewport = frames.reduce(screen) { $0.union($1.start).union($1.end) }
                trail.contentView = MagneticDockMotionView(leaves: leaves, screen: viewport, frames: frames,
                                                          duration: 0.32)
                trail.setFrame(viewport, display: true)
                trail.orderFrontRegardless()
            } else {
                trail.contentView = MagneticPassiveHostingView(rootView: MagneticFlightTrailView(state: trailState, screenFrame: screen))
                trail.setFrame(screen, display: true)
                trail.orderFrontRegardless()
                for (id, _) in flying { cardPanels[id]?.orderFrontRegardless() }
            }
        }
        defer {
            if let generation, generation == effectGeneration { clearEffects() }
        }
        if style == .full, generation != nil {
            do { try await Task.sleep(for: .seconds(0.32)) } catch { return }
            return
        }
        // Window frames and visual progress share one clock, including all-card returns.
        let animationDuration = duration * (style == .elastic || style == .arc ? 1.25 : 1)
        let steps = max(1, Int(animationDuration * 60))
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let progress = CGFloat(step) / CGFloat(steps)
            let eased = style.progress(progress)
            for (index, target) in changing.enumerated() {
                let start = starts[index], end = target.1
                let center = style.point(from: start.midpoint, to: end.midpoint, progress: eased)
                let size = CGSize(width: start.width + (end.width - start.width) * eased,
                                  height: start.height + (end.height - start.height) * eased)
                let pose = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                  width: size.width, height: size.height)
                // Curved travel may bow outside a display; all other styles retain the existing path.
                target.0.setFrame(style == .arc && step < steps
                    ? PinWindowVisibleGeometry.constrainedFrame(pose, visibleFrames: screenFrames()) : pose, display: true)
            }
            if generation == effectGeneration {
                for id in flying.keys { cardMotions[id]?.progress = progress }
                trailState.flights = trailState.flights.map { flight in
                    var changed = flight
                    changed.progress = eased
                    return changed
                }
            }
            if step < steps {
                do { try await Task.sleep(for: .seconds(animationDuration / Double(steps))) }
                catch { return }
            }
        }
    }

    private func reconcile(partition: (visible: [UUID], boxed: [UUID]), items: [UUID: HistoryItem], frame: CGRect,
                           generation: Int, newCapture: Bool, changingPage: Bool) async {
        func isCurrent() -> Bool { !Task.isCancelled && generation == refreshGeneration && !suspended }
        guard isCurrent() else { return }
        let unfolding = foldedPanel?.isVisible == true
        let boxFrame = resolvedBoxFrame(in: frame)
        let displayIDs = partition.visible + desktopOrder
        let wanted = Set(displayIDs)
        let outgoing = cardPanels.keys.filter { !wanted.contains($0) }
        let needed = wanted.union(partition.boxed.prefix(5))
        thumbnails = thumbnails.filter { needed.contains($0.key) }
        for id in needed where thumbnails[id] == nil {
            guard let item = items[id] else { continue }
            let image = await historyStore.thumbnail(for: item, maxPixelSize: 300)
            guard isCurrent() else { return }
            if let image { thumbnails[id] = image }
        }
        guard isCurrent() else { return }
        let layouts = MagneticDesktopGeometry.cardLayouts(count: partition.visible.count, in: frame)
        let frames = layouts.map(\.frame)
        let flightDirections = pendingFlights
        pendingFlights.removeAll()
        var moving: [(NSPanel, CGRect)] = outgoing.compactMap { id in
            if changingPage { cardPanels[id]?.orderOut(nil); return nil }
            guard items[id] != nil, let panel = cardPanels[id] else { return nil }
            return (panel, CGRect(x: boxFrame.midX - 30, y: boxFrame.midY, width: 60, height: 48))
        }
        for id in displayIDs {
            if let pin = desktopPins[id], let panel = pin.window as? NSPanel {
                desktopFrames[id] = panel.frame
                cardPanels[id] = panel
                if pinManager.pinsAreVisible && !panel.isVisible { pin.showWithoutActivating() }
                continue
            }
            guard let item = items[id] else { continue }
            let isDesktop = desktopFrames[id] != nil
            let image = isDesktop ? historyStore.image(for: item) : thumbnails[id]
            guard let image else { cardPanels[id]?.orderOut(nil); continue }
            let destination: CGRect
            if let desktop = desktopFrames[id] { destination = desktop }
            else if let index = partition.visible.firstIndex(of: id) { destination = frames[index] }
            else { continue }
            let isNew = cardPanels[id] == nil
            let panel = cardPanels[id] ?? makePanel(frame: isDesktop ? boxFrame : destination)
            cardPanels[id] = panel
            updateCard(panel, item: item, image: image, expanded: isDesktop)
            if !isDesktop, let index = partition.visible.firstIndex(of: id),
               let hosting = panel.contentView as? MagneticCardHostingView {
                hosting.rootView.fanAngle = layouts[index].angle
            }
            // Return flights stay on the desktop plane until they actually reach the rail.
            panel.level = isDesktop || flightDirections[id] == .inward ? .normal : .floating
            panel.alphaValue = 1
            if isNew && hasPresented && decorativeEffects && !unfolding && !changingPage {
                panel.setFrame(PinWindowVisibleGeometry.constrainedFrame(
                    CGRect(origin: newCapture ? pointerLocation() : boxFrame.origin,
                           size: MagneticDesktopGeometry.cardSize), visibleFrames: [frame]), display: false)
            } else if isNew && !isDesktop {
                panel.setFrame(destination, display: false)
            }
            if !unfolding || isDesktop { panel.orderFrontRegardless() }
            moving.append((panel, destination))
        }
        if unfolding || changingPage {
            moving.forEach { $0.0.setFrame($0.1, display: true) }
            if changingPage && !unfolding && !motionReduced {
                let cards = moving.map(\.0).filter { panel in !desktopPins.values.contains { $0.window === panel } }
                defer { if isCurrent() { cards.forEach { $0.alphaValue = 1 } } }
                for step in 0...8 {
                    guard isCurrent() else { return }
                    cards.forEach { $0.alphaValue = CGFloat(step) / 8 }
                    if step < 8 { try? await Task.sleep(for: .milliseconds(16)) }
                }
            }
        } else {
            await animateMany(moving, duration: flightDirections.isEmpty ? 0.24 : 0.42, flights: flightDirections)
        }
        guard isCurrent() else { return }
        for id in outgoing {
            cardPanels.removeValue(forKey: id)?.orderOut(nil)
            cardMotions.removeValue(forKey: id)
        }
        for id in desktopOrder where desktopPins[id] == nil {
            guard let pose = desktopFrames[id], let item = items[id], let image = historyStore.image(for: item) else { continue }
            installPin(id, image: image, frame: pose)
        }
        for id in partition.visible { cardPanels[id]?.level = .floating }
        for id in desktopOrder { cardPanels[id]?.level = .normal }
        hasPresented = true
        if !partition.boxed.isEmpty {
            let box = boxPanel ?? makePanel(frame: boxFrame)
            boxPanel = box
            // Separate levels keep box controls above the rail even when another magnetic window is clicked.
            box.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            let content = MagneticBoxView(
                images: partition.boxed.prefix(5).compactMap { thumbnails[$0] }, count: partition.boxed.count,
                desktopCount: desktopFrames.count, motion: boxMotion,
                onReturnAll: { [weak self] in self?.returnAllToEdge() },
                onOpen: { [weak self] in self?.toggleBox() },
                onCollapse: { [weak self] in self?.setCollapsed(true) },
                motionReduced: motionReduced, decorativeEffects: decorativeEffects, animationStyle: settings.animationStyle)
            if let hosting = box.contentView as? MagneticBoxHostingView {
                // A history refresh during a drag must retain its original press coordinates.
                hosting.rootView = content
            } else {
                let hosting = MagneticBoxHostingView(rootView: content)
                hosting.onMove = { [weak self] in self?.moveBox(to: $0) }
                box.contentView = hosting
            }
            // Thumbnail loads and flights await; the user may have moved the tray in the meantime.
            box.setFrame(resolvedBoxFrame(in: frame), display: true)
        } else {
            (boxPanel?.contentView as? MagneticBoxHostingView)?.cancelDrag()
            stopBoxMotion()
            boxPanel?.orderOut(nil)
            closeBox()
            shouldRestoreContents = false
        }
        if unfolding {
            let boxes = partition.boxed.isEmpty ? [] : [boxPanel].compactMap { $0 }
            await animateFan(partition.visible.compactMap { cardPanels[$0] } + boxes,
                             opening: true, in: frame, generation: generation)
            guard isCurrent() else { return }
            foldedPanel?.orderOut(nil)
            for id in partition.visible { cardPanels[id]?.orderFrontRegardless() }
        }
        if !partition.boxed.isEmpty { boxPanel?.orderFrontRegardless() }
        updatePager(in: frame)
        if !changingPage && outgoing.contains(where: { items[$0] != nil && partition.boxed.contains($0) }) { shakeBox() }
        if shouldRestoreContents {
            shouldRestoreContents = false
            toggleBox()
        }
        if contentsPanel?.isVisible == true { updateBoxContents() }
        if idleTask == nil { recordInteraction() }
    }

    private func updateCard(_ panel: NSPanel, item: HistoryItem, image: NSImage, expanded: Bool) {
        let originalFrame = panel.frame
        let content = MagneticCardView(
            image: image, item: item, isExpanded: expanded,
            isFocused: !expanded && focusedRailID == item.id,
            onExtract: { [weak self] in self?.extract(item.id) },
            onReturn: { [weak self] in self?.returnToEdge(item.id) },
            onReturnAll: { [weak self] in self?.returnAllToEdge() },
            motion: motion(for: item.id),
            onCopy: { [weak self] in self?.onCopy?(item) },
            onPin: { [weak self] in self?.extract(item.id) },
            onEdit: { [weak self] in self?.edit(item.id) },
            onDrag: { [weak self] point, ended, time in self?.drag(item.id, at: point, ended: ended, timestamp: time) })
        let hosting: MagneticCardHostingView
        if let existing = panel.contentView as? MagneticCardHostingView {
            hosting = existing
            hosting.rootView = content
        } else {
            hosting = MagneticCardHostingView(rootView: content)
            hosting.sizingOptions = []
            panel.contentView = hosting
        }
        hosting.onHoverChanged = { [weak self] _ in
            if let self { self.updateHover(at: self.pointerLocation()) }
        }
        panel.setFrame(originalFrame, display: false)
    }

    func updateHover(at point: CGPoint) {
        if settings.isCollapsed, let panel = foldedPanel, panel.isVisible {
            setFoldedHovered(panel.frame.contains(point))
            updateFoldedBubbles()
        }
        let rail = cardPanels.filter { desktopFrames[$0.key] == nil }.map(\.value)
        if (rail + [boxPanel, contentsPanel, pagerPanel].compactMap { $0 }).contains(where: { $0.isVisible && $0.frame.contains(point) }) {
            recordInteraction()
        }
        guard !suspended, !isReconciling, dragStart == nil, settings.isEnabled, !settings.isCollapsed,
              let frame = visibleFrame else { return }
        // Global pointer coordinates still hit cards underneath the tray and its expanded contents.
        if [boxPanel, contentsPanel, pagerPanel].compactMap({ $0 }).contains(where: {
            $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(point)
        }) {
            hoverTask?.cancel()
            hoverTask = nil
            hoveredID = nil
            hoverPanel?.orderOut(nil)
            return
        }
        let ids = partition.visible
        let frames = MagneticDesktopGeometry.cardFrames(count: ids.count, in: frame)
        let candidate = MagneticDesktopGeometry.hoveredCard(at: point, ids: ids, frames: frames, excluding: nil)
        if let candidate {
            setHover(candidate, entered: true)
        } else if let hoveredID {
            setHover(hoveredID, entered: false)
        }
    }

    func setHover(_ id: UUID, entered: Bool) {
        guard !suspended, !isReconciling, dragStart == nil, desktopFrames[id] == nil,
              settings.isEnabled, !settings.isCollapsed, let frame = visibleFrame else { return }
        let ids = partition.visible
        guard ids.contains(id), entered ? hoveredID != id : hoveredID == id else { return }
        let frames = MagneticDesktopGeometry.cardFrames(count: ids.count, in: frame)
        guard let index = ids.firstIndex(of: id), let card = cardPanels[id] else { return }
        let base = frames[index]
        let expanded = MagneticDesktopGeometry.hoverFrame(for: base, beside: frames, in: frame)
        // If a dense rail leaves no side space, suppress the preview rather than obscure the cards.
        guard !expanded.isEmpty else {
            hoverTask?.cancel()
            hoveredID = nil
            hoverPanel?.orderOut(nil)
            return
        }
        hoveredID = entered ? id : nil
        hoverTask?.cancel()
        let smallSize = CGSize(width: min(base.width, expanded.width), height: min(base.height, expanded.height))
        // Grow and shrink beside the fan too; animating from the card would briefly cover its neighbours.
        let collapsed = CGRect(x: expanded.maxX - smallSize.width, y: expanded.midY - smallSize.height / 2,
                               width: smallSize.width, height: smallSize.height)
        let preview: NSPanel
        if entered {
            guard var content = (card.contentView as? MagneticCardHostingView)?.rootView else { return }
            content.fanAngle = 0
            preview = hoverPanel ?? makePanel(frame: collapsed)
            hoverPanel = preview
            // The preview never participates in pointer hit testing or rail stacking.
            // Resizing the hit windows themselves causes tracking/z-order feedback and flicker.
            preview.ignoresMouseEvents = true
            let originalFrame = preview.frame
            if let hosting = preview.contentView as? NSHostingView<MagneticCardView> {
                hosting.rootView = content
            } else {
                let hosting = NSHostingView(rootView: content)
                hosting.sizingOptions = []
                preview.contentView = hosting
            }
            preview.setFrame(preview.isVisible ? originalFrame : collapsed, display: false)
            preview.orderFrontRegardless()
        } else {
            guard let existing = hoverPanel else { return }
            preview = existing
        }
        let destination = entered ? expanded : collapsed
        hoverTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.animateMany([(preview, destination)], duration: 0.16)
            guard !Task.isCancelled, !self.suspended else { return }
            if self.hoveredID == nil { preview.orderOut(nil) }
        }
    }

    func edit(_ id: UUID) {
        guard !suspended, let item = historyStore.items.first(where: { $0.id == id }) else { return }
        closeBox()
        onEdit?(item)
    }

    func extract(_ id: UUID, from source: MagneticCardHome? = nil) {
        guard !suspended, settings.isEnabled, !settings.isCollapsed,
              desktopFrames[id] == nil, let frame = visibleFrame,
              let item = historyStore.items.first(where: { $0.id == id }),
              let image = historyStore.image(for: item) else { return }
        let offset = CGFloat(desktopOrder.count % 5) * 28
        let desired = MagneticDesktopGeometry.expandedFrame(imageSize: image.size,
            near: CGPoint(x: frame.midX + offset, y: frame.midY - offset), in: frame)
        guard let pose = placeDesktop(id, desired: desired, in: frame) else { return }
        homes[id] = source ?? (partition.visible.contains(id) ? .rail : .box)
        closeBox()
        desktopFrames[id] = pose
        desktopOrder.append(id)
        pendingFlights[id] = .outward
        requestAutomaticDesktopCentering()
        refresh(force: true)
    }

    func returnToEdge(_ id: UUID, closePin: Bool = true) {
        guard desktopFrames[id] != nil, let home = homes[id] else { return }
        restoreFlightProxy(id, closePin: closePin)
        if home == .box { queue.returnToBox(id) } else { queue.returnToRail(id) }
        desktopFrames.removeValue(forKey: id)
        desktopOrder.removeAll { $0 == id }
        homes.removeValue(forKey: id)
        pendingFlights[id] = .inward
        requestAutomaticDesktopCentering()
        refresh(force: true)
    }

    func returnAllToEdge() {
        guard !desktopFrames.isEmpty else { return }
        for id in Array(desktopOrder) {
            guard let home = homes[id] else { continue }
            restoreFlightProxy(id)
            if home == .box { queue.returnToBox(id) } else { queue.returnToRail(id) }
            pendingFlights[id] = .inward
        }
        desktopFrames.removeAll()
        resetDesktopCentering()
        desktopOrder.removeAll()
        homes.removeAll()
        refresh(force: true)
    }

    func drag(_ id: UUID, at point: CGPoint, ended: Bool,
              timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !suspended, settings.isEnabled, !settings.isCollapsed,
              let panel = cardPanels[id], let frame = visibleFrame else { return }
        if dragStart?.id != id {
            interruptDesktopCentering()
            refreshTask?.cancel()
            hoverTask?.cancel()
            clearEffects()
            hoveredID = nil
            hoverPanel?.orderOut(nil)
            if homes[id] == nil { homes[id] = partition.visible.contains(id) ? .rail : .box }
            dragStart = (id, point, panel.frame.origin)
            dragVelocity = MagneticDragVelocity()
            // A pulled card belongs to the normal desktop window plane from the first drag event.
            panel.level = .normal
            panel.orderFrontRegardless()
        }
        dragVelocity.record(point, at: timestamp)
        guard let start = dragStart else { return }
        let origin = PinWindowDragGeometry.origin(initialWindowOrigin: start.origin,
            initialMouseLocation: start.mouse, currentMouseLocation: point)
        let constrained = PinWindowVisibleGeometry.constrainedFrame(
            CGRect(origin: origin, size: panel.frame.size), visibleFrames: screenFrames())
        panel.setFrame(constrained, display: true)
        guard ended else { return }
        dragStart = nil
        let velocity = dragVelocity.velocity
        if MagneticDesktopThrow.shouldReturn(card: constrained, velocity: velocity, screen: frame) {
            restoreFlightProxy(id)
            if homes[id] == .box { queue.returnToBox(id) } else { queue.returnToRail(id) }
            desktopFrames.removeValue(forKey: id)
            desktopOrder.removeAll { $0 == id }
            homes.removeValue(forKey: id)
            pendingFlights[id] = .inward
            requestAutomaticDesktopCentering()
        } else if let item = historyStore.items.first(where: { $0.id == id }), let image = historyStore.image(for: item) {
            guard let destinationScreen = MagneticDesktopGeometry.screenFrame(for: constrained, in: screenFrames()) else { return }
            let wasDesktop = desktopFrames[id] != nil
            let expanded = wasDesktop ? constrained : MagneticDesktopGeometry.expandedFrame(
                imageSize: image.size, near: constrained.midpoint, in: destinationScreen)
            let projected = MagneticDesktopThrow.settledFrame(expanded, velocity: velocity, screen: destinationScreen)
            guard let settled = placeDesktop(id, desired: projected, in: destinationScreen) else {
                if let previous = desktopFrames[id] { panel.setFrame(previous, display: true) }
                else { homes.removeValue(forKey: id); refresh(force: true) }
                return
            }
            noteDesktopAdjustment()
            desktopFrames[id] = settled
            desktopPins[id]?.window?.setFrame(settled, display: true)
            desktopOrder.removeAll { $0 == id }
            desktopOrder.append(id)
            if !wasDesktop { pendingFlights[id] = .outward }
        }
        refresh(force: true)
    }

    private func releasePin(_ id: UUID, close: Bool, keepSource: Bool = false) {
        guard let pin = desktopPins.removeValue(forKey: id) else { return }
        if !keepSource { pin.magneticSource = nil }
        pin.onReturnToSource = nil
        pin.onReturnAllToSource = nil
        pin.onCenterSourceGroup = nil
        pin.canCenterSourceGroup = nil
        pin.onSourceGeometryWillChange = nil
        pin.onSourceGeometryChanged = nil
        pin.onEditSourceImage = nil
        pin.onSourceDragEnded = nil
        pin.onSourceClosed = nil
        pin.returnToSourceTitle = nil
        pin.window?.contentView?.toolTip = nil
        cardPanels.removeValue(forKey: id)
        if close { pin.close() }
    }

    private func installPin(_ id: UUID, image: NSImage, frame: CGRect) {
        let pin = pinManager.pinFromMagneticDesktop(image: image, frame: frame)
        guard pin.window is NSPanel else { pin.close(); return }
        bindPin(pin, to: id)
    }

    private func bindPin(_ pin: PinWindowController, to id: UUID) {
        guard let panel = pin.window as? NSPanel, let home = homes[id] else { return }
        let old = cardPanels[id]
        pin.magneticSource = MagneticPinSource(historyItemID: id, home: home)
        panel.level = .normal
        desktopPins[id] = pin
        cardPanels[id] = panel
        pin.returnToSourceTitle = L10n.text(homes[id] == .box ? "magnetic.returnBox" : "magnetic.return")
        panel.contentView?.toolTip = L10n.text("magnetic.returnHelp")
        pin.onReturnToSource = { [weak self] in self?.returnToEdge(id) }
        pin.onReturnAllToSource = { [weak self] in self?.returnAllToEdge() }
        pin.onCenterSourceGroup = { [weak self] in self?.centerDesktopGroup() }
        pin.canCenterSourceGroup = { [weak self] in self?.canCenterDesktopGroup == true }
        pin.onSourceGeometryWillChange = { [weak self] in self?.interruptDesktopCentering() }
        pin.onSourceGeometryChanged = { [weak self] in self?.noteDesktopAdjustment() }
        pin.onEditSourceImage = { [weak self] in self?.edit(id) }
        // windowWillClose already owns teardown; returning its image must not close that window again.
        pin.onSourceClosed = { [weak self] in self?.returnToEdge(id, closePin: false) }
        pin.onSourceDragEnded = { [weak self, weak pin] pose, velocity in
            guard let self, let frame = self.visibleFrame else { return }
            if MagneticDesktopThrow.shouldReturn(card: pose, velocity: velocity, screen: frame) {
                self.desktopFrames[id] = pose
                self.returnToEdge(id)
            } else {
                guard let destinationScreen = MagneticDesktopGeometry.screenFrame(for: pose, in: self.screenFrames()) else { return }
                let previous = self.desktopFrames[id]
                self.noteDesktopAdjustment()
                let projected = MagneticDesktopThrow.settledFrame(pose, velocity: velocity, screen: destinationScreen)
                guard let settled = self.placeDesktop(id, desired: projected, in: destinationScreen) else {
                    // noteDesktopAdjustment samples the dragged pose; rollback needs the pre-drag pose.
                    if let previous {
                        pin?.window?.setFrame(previous, display: true)
                        self.desktopFrames[id] = previous
                        pin?.didFinishGeometryChange()
                    }
                    return
                }
                pin?.window?.setFrame(settled, display: true)
                self.desktopFrames[id] = settled
                pin?.didFinishGeometryChange()
            }
        }
        if old !== panel {
            old?.orderOut(nil)
            old?.close()
        }
    }

    private func restoreFlightProxy(_ id: UUID, closePin: Bool = true) {
        guard let pin = desktopPins[id], let pose = pin.window?.frame,
              let item = historyStore.items.first(where: { $0.id == id }),
              let image = historyStore.image(for: item) else { return }
        let proxy = makePanel(frame: pose)
        proxy.level = .normal
        updateCard(proxy, item: item, image: image, expanded: true)
        releasePin(id, close: closePin)
        cardPanels[id] = proxy
        proxy.orderFrontRegardless()
    }

    private func resetDesktopCentering() {
        desktopCenterGeneration = nil
        desktopLayoutWasAdjusted = false
        desktopCenterRequest = nil
    }

    private func requestAutomaticDesktopCentering() {
        if desktopFrames.isEmpty { resetDesktopCentering() }
        else if desktopCenterRequest != true { desktopCenterRequest = false }
    }

    private func noteDesktopAdjustment() {
        // Manual arrangements stay manual until all cards are returned, even after explicit centering.
        desktopLayoutWasAdjusted = true
        if desktopCenterRequest == false { desktopCenterRequest = nil }
        for (id, pin) in desktopPins {
            if let pose = pin.window?.frame { desktopFrames[id] = pose }
        }
    }

    private func interruptDesktopCentering() {
        guard desktopCenterGeneration != nil else { return }
        desktopCenterGeneration = nil
        desktopCenterRequest = nil
        refreshTask?.cancel()
        for (id, pin) in desktopPins {
            if let pose = pin.window?.frame { desktopFrames[id] = pose }
        }
    }

    var canCenterDesktopGroup: Bool {
        settings.isEnabled && !suspended && !desktopFrames.isEmpty && dragStart == nil
            && desktopPins.count == desktopFrames.count && pinManager.pinsAreVisible
            && desktopPins.values.allSatisfy { !$0.isPositionLocked && $0.window?.isVisible == true }
    }

    func centerDesktopGroup() {
        guard canCenterDesktopGroup else { return }
        desktopCenterRequest = true
        if !isReconciling { refresh(force: true) }
    }

    private func desktopLayoutBounds(in screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + 16, y: screen.minY + 16,
               width: max(0, screen.width - (screen == visibleFrame ? MagneticDesktopGeometry.cardSize.width + 40 : 32)),
               height: max(0, screen.height - 32))
    }

    private func magneticObstacles(in screen: CGRect) -> [CGRect] {
        guard screen == visibleFrame else { return [] }
        if settings.isCollapsed { return [resolvedFoldedFrame(in: screen)] }
        let cards = MagneticDesktopGeometry.cardFrames(count: partition.visible.count, in: screen)
        return (partition.boxed.isEmpty ? [] : [resolvedBoxFrame(in: screen)]) + cards
            + (railPageCount > 1 ? [MagneticDesktopGeometry.pagerFrame(beside: cards, in: screen)] : [])
    }

    private func performDesktopCentering(in screen: CGRect, generation: Int) async {
        while !Task.isCancelled, generation == refreshGeneration, !suspended,
              let explicit = desktopCenterRequest {
            desktopCenterRequest = nil
            guard canCenterDesktopGroup, explicit || !desktopLayoutWasAdjusted else { continue }
            let current = desktopPins.compactMapValues { $0.window?.frame }
            let fixed = pinManager.visibleFrames(excluding: Set(desktopPins.values.map(\.id)))
            var layout: [UUID: CGRect] = [:]
            let frames = screenFrames()
            // Center each display's group independently; cross-display cards must not migrate to the rail display.
            for target in frames {
                let group = current.filter { MagneticDesktopGeometry.screenFrame(for: $0.value, in: frames) == target }
                guard !group.isEmpty,
                      let centered = MagneticDesktopPlacement.centeredGroup(group,
                          fixed: fixed + magneticObstacles(in: target), in: desktopLayoutBounds(in: target)) else { continue }
                layout.merge(centered) { _, new in new }
            }
            guard !layout.isEmpty else { continue }
            let targets = desktopOrder.compactMap { id -> (NSPanel, CGRect)? in
                guard let panel = desktopPins[id]?.window as? NSPanel, let pose = layout[id] else { return nil }
                return (panel, pose)
            }
            desktopCenterGeneration = generation
            // Only frame changes: do not raise windows or take focus from the application being referenced.
            await animateMany(targets, duration: 0.18)
            if desktopCenterGeneration == generation { desktopCenterGeneration = nil }
            guard !Task.isCancelled, generation == refreshGeneration, !suspended else { return }
            for (id, pin) in desktopPins {
                if let pose = pin.window?.frame { desktopFrames[id] = pose }
                pin.didFinishGeometryChange()
            }
        }
    }

    private func placeDesktop(_ id: UUID, desired: CGRect, in screen: CGRect) -> CGRect? {
        let bounds = desktopLayoutBounds(in: screen)
        let locked = desktopPins.filter { $0.value.isPositionLocked }
        let fixed = pinManager.visibleFrames(excluding: Set(desktopPins.values.map(\.id)))
            + locked.values.compactMap { $0.window?.frame }
            + magneticObstacles(in: screen)
        let frames = screenFrames()
        var existing = desktopFrames.filter { MagneticDesktopGeometry.screenFrame(for: $0.value, in: frames) == screen }
        for (otherID, pin) in desktopPins where otherID != id {
            if let pose = pin.window?.frame,
               MagneticDesktopGeometry.screenFrame(for: pose, in: frames) == screen { existing[otherID] = pose }
        }
        existing.removeValue(forKey: id)
        // A locked pin remains an obstacle even when a crowded desktop needs repacking.
        for lockedID in locked.keys { existing.removeValue(forKey: lockedID) }
        if let pose = MagneticDesktopPlacement.frame(size: desired.size, near: desired.midpoint,
                                                     occupied: fixed + Array(existing.values), in: bounds) { return pose }
        // Crowding must not silently repack a layout the user has arranged by hand.
        guard !desktopLayoutWasAdjusted else { return nil }
        existing[id] = desired
        guard let layout = MagneticDesktopPlacement.reflow(existing, fixed: fixed, in: bounds) else { return nil }
        for (otherID, pose) in layout where otherID != id {
            desktopFrames[otherID] = pose
            desktopPins[otherID]?.window?.setFrame(pose, display: true)
            desktopPins[otherID]?.didFinishGeometryChange()
        }
        return layout[id]
    }

    private func stopBoxMotion() {
        boxGeneration += 1
        boxTask?.cancel()
        boxMotion.progress = 1
    }

    private func shakeBox() {
        stopBoxMotion()
        guard decorativeEffects, !suspended else { return }
        let generation = boxGeneration
        boxMotion.progress = 0
        boxTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == self.boxGeneration { self.boxMotion.progress = 1 } }
            for step in 1...24 {
                guard !Task.isCancelled, !self.suspended else { return }
                self.boxMotion.progress = CGFloat(step) / 24
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }

    private func attachedFoldedSize(in frame: CGRect) -> CGSize {
        let thickness: CGFloat = foldedIsCompact ? 20 : 32
        let length: CGFloat = foldedIsCompact ? 56 : 144
        if foldedDockEdge.isHorizontal {
            return CGSize(width: min(length, frame.width * 0.65), height: min(thickness, frame.height))
        }
        return CGSize(width: min(thickness, frame.width), height: min(length, frame.height * 0.65))
    }

    private func resolvedFoldedFrame(in frame: CGRect) -> CGRect {
        let initial = MagneticDesktopGeometry.foldedFrame(in: frame)
        let size = foldedIsDetached
            ? CGSize(width: min(96, frame.width), height: min(112, frame.height))
            : attachedFoldedSize(in: frame)
        var origin = foldedPreferredOrigin ?? initial.origin
        if !foldedIsDetached {
            switch foldedDockEdge {
            case .right: origin.x = frame.maxX - size.width
            case .left: origin.x = frame.minX
            case .top: origin.y = frame.maxY - size.height
            case .bottom: origin.y = frame.minY
            }
        }
        return PinWindowVisibleGeometry.constrainedFrame(
            CGRect(origin: origin, size: size), visibleFrames: [frame])
    }

    private func beginFoldedDrag(at point: CGPoint) {
        hideFoldedBubbles()
        setFoldedCompact(false)
        recordFoldedInteraction()
        guard let panel = foldedPanel else { return }
        foldedDragStart = (point, CGPoint(x: (point.x - panel.frame.minX) / panel.frame.width,
            y: (point.y - panel.frame.minY) / panel.frame.height), foldedIsDetached)
    }

    private func cancelFoldedDrag() {
        foldedDragStart = nil
        withAnimation(foldedAnimation(response: 0.3, damping: 0.75)) {
            foldedMotion.pull = 0
        }
        recordFoldedInteraction()
    }

    private func changeFoldedAttachment(detached: Bool) {
        guard foldedIsDetached != detached else { return }
        foldedIsDetached = detached
        if detached {
            foldedIdleTask?.cancel()
            foldedIdleTask = nil
        } else {
            recordFoldedInteraction()
        }
        withAnimation(foldedAnimation(response: 0.34, damping: 0.78)) {
            foldedMotion.progress = detached ? 1 : 0
            foldedMotion.pull = 0
        }
    }

    private func dragFolded(to point: CGPoint, ended: Bool) {
        guard let currentScreen = visibleFrame, let panel = foldedPanel, panel.isVisible,
              let start = foldedDragStart, settings.isEnabled, settings.isCollapsed, !suspended else { return }
        // Keep the current screen through gaps and menu/Dock areas, switching once the pointer enters another display.
        let frame = currentScreen.contains(point) ? currentScreen
            : screenFrames().first(where: { $0.contains(point) }) ?? currentScreen
        let changedScreen = frame != currentScreen
        magneticScreenFrame = frame
        let delta = CGPoint(x: point.x - start.point.x, y: point.y - start.point.y)
        let wasDetached = foldedIsDetached
        let previousEdge = foldedDockEdge
        if changedScreen { changeFoldedAttachment(detached: true) }
        if !foldedIsDetached {
            let inward = foldedDockEdge.inwardTravel(delta)
            let tangent = foldedDockEdge.isHorizontal ? abs(delta.x) : abs(delta.y)
            // Pull inward to detach; motion along the active edge remains a slide.
            if !start.detached && inward >= 64 && inward > tangent * 0.75 {
                changeFoldedAttachment(detached: true)
            } else {
                let size = attachedFoldedSize(in: frame)
                foldedPreferredOrigin = CGPoint(x: point.x - start.anchor.x * size.width,
                                                y: point.y - start.anchor.y * size.height)
                if !ended { foldedMotion.pull = min(1, max(0, inward / 64)) }
                let pose = resolvedFoldedFrame(in: frame)
                foldedPreferredOrigin = pose.origin
                panel.setFrame(pose, display: true)
                return
            }
        }
        let floating = resolvedFoldedFrame(in: frame)
        var anchor = start.anchor
        if !start.detached {
            // Grow inward from the grip so detaching does not immediately enter the snap zone again.
            switch foldedDockEdge {
            case .right: anchor.x = max(0.65, anchor.x)
            case .left: anchor.x = min(0.35, anchor.x)
            case .top: anchor.y = max(0.65, anchor.y)
            case .bottom: anchor.y = min(0.35, anchor.y)
            }
        }
        let origin = CGPoint(x: point.x - anchor.x * floating.width, y: point.y - anchor.y * floating.height)
        if let edge = MagneticDockEdge.nearest(to: CGRect(origin: origin, size: floating.size),
                                               in: frame, preferring: foldedDockEdge) {
            foldedDockEdge = edge
            foldedMotion.dockEdge = edge
            changeFoldedAttachment(detached: false)
            let size = attachedFoldedSize(in: frame)
            foldedPreferredOrigin = CGPoint(x: point.x - start.anchor.x * size.width,
                                            y: point.y - start.anchor.y * size.height)
        } else {
            foldedPreferredOrigin = origin
        }
        let pose = resolvedFoldedFrame(in: frame)
        foldedPreferredOrigin = pose.origin
        panel.setFrame(pose, display: true)
        if changedScreen || wasDetached != foldedIsDetached || previousEdge != foldedDockEdge {
            // Restart the grip at the new shape, including when snapping to a different edge mid-drag.
            foldedDragStart = (point, CGPoint(x: min(1, max(0, (point.x - pose.minX) / pose.width)),
                                              y: min(1, max(0, (point.y - pose.minY) / pose.height))), foldedIsDetached)
        }
    }

    private func resolvedBoxFrame(in frame: CGRect) -> CGRect {
        guard let origin = boxPreferredOrigin else { return MagneticDesktopGeometry.boxFrame(in: frame) }
        return PinWindowVisibleGeometry.constrainedFrame(
            CGRect(origin: origin, size: MagneticDesktopGeometry.boxSize), visibleFrames: [frame])
    }

    private func boxContentsFrame(in frame: CGRect) -> CGRect {
        let width = min(540, frame.width - 24)
        let columns = max(1, Int((max(110, width - 32) + 12) / 122))
        let rows = max(1, (min(20, collectionItems.count) + columns - 1) / columns)
        let size = CGSize(width: width, height: min(700, frame.height - 160, max(260, 100 + CGFloat(rows) * 142)))
        let tray = resolvedBoxFrame(in: frame)
        let y = tray.maxY + size.height + 8 <= frame.maxY ? tray.maxY + 8 : tray.minY - size.height - 8
        return PinWindowVisibleGeometry.constrainedFrame(
            CGRect(x: tray.maxX - size.width, y: y, width: size.width, height: size.height), visibleFrames: [frame])
    }

    private func moveBox(to origin: CGPoint) {
        guard let frame = visibleFrame, let box = boxPanel, box.isVisible,
              settings.isEnabled, !settings.isCollapsed, !suspended else { return }
        stopBoxMotion()
        boxPreferredOrigin = origin
        let pose = resolvedBoxFrame(in: frame)
        boxPreferredOrigin = pose.origin
        box.setFrame(pose, display: true)
        if contentsPanel?.isVisible == true { contentsPanel?.setFrame(boxContentsFrame(in: frame), display: true) }
    }

    func toggleBox() {
        recordInteraction()
        if contentsPanel?.isVisible == true { closeBox(); return }
        guard let frame = visibleFrame, settings.isEnabled, !settings.isCollapsed, !suspended,
              !partition.boxed.isEmpty else { return }
        let rect = boxContentsFrame(in: frame)
        guard rect.width > 0, rect.height > 0 else { return }
        let panel = contentsPanel ?? makePanel(frame: rect)
        contentsPanel = panel
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.setFrame(rect, display: true)
        collectionPage = min(collectionPage, max(0, (collectionItems.count - 1) / 20))
        updateBoxContents()
        panel.orderFrontRegardless()
        updateHover(at: pointerLocation())
    }

    func handleBoxClick(at point: CGPoint) {
        guard contentsPanel?.isVisible == true else { return }
        if [contentsPanel, boxPanel].compactMap({ $0 }).contains(where: { $0.isVisible && $0.frame.contains(point) }) { return }
        closeBox()
    }

    func closeBox() {
        clearBoxHover()
        contentsPanel?.orderOut(nil)
    }

    private func clearBoxHover() {
        boxHoverTask?.cancel()
        boxHoverTask = nil
        boxHoveredID = nil
        boxPreviewPanel?.orderOut(nil)
    }

    func setBoxHover(_ item: HistoryItem, entered: Bool) {
        if !entered {
            // SwiftUI may deliver the previous cell's exit after the next cell's enter.
            if boxHoveredID == item.id { clearBoxHover() }
            return
        }
        guard contentsPanel?.isVisible == true, !suspended, !settings.isCollapsed,
              collectionPageItems.contains(where: { $0.id == item.id }), boxHoveredID != item.id else { return }
        clearBoxHover()
        boxHoveredID = item.id
        recordInteraction()
        boxHoverTask = Task { @MainActor [weak self] in
            guard let self, let image = await self.historyStore.thumbnail(for: item, maxPixelSize: 900),
                  !Task.isCancelled, self.boxHoveredID == item.id,
                  self.contentsPanel?.isVisible == true, !self.suspended,
                  self.collectionPageItems.contains(where: { $0.id == item.id }), let screen = self.visibleFrame,
                  let box = self.contentsPanel else { return }
            let leftSpace = max(0, box.frame.minX - screen.minX - 12)
            let rightSpace = max(0, screen.maxX - box.frame.maxX - 12)
            let useLeft = leftSpace >= rightSpace
            let availableWidth = min(360, useLeft ? leftSpace : rightSpace)
            guard availableWidth >= 40 else { return }
            let scale = min(availableWidth / max(1, image.size.width), 280 / max(1, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let x = useLeft ? box.frame.minX - size.width - 12 : box.frame.maxX + 12
            let rect = PinWindowVisibleGeometry.constrainedFrame(
                CGRect(x: x, y: self.pointerLocation().y - size.height / 2, width: size.width, height: size.height),
                visibleFrames: [screen])
            let preview = self.boxPreviewPanel ?? self.makePanel(frame: rect)
            self.boxPreviewPanel = preview
            preview.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
            preview.ignoresMouseEvents = true
            let view = NSImageView(frame: CGRect(origin: .zero, size: rect.size))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            preview.contentView = view
            preview.setFrame(rect, display: true)
            preview.orderFrontRegardless()
        }
    }

    private func updateBoxContents() {
        let items = collectionItems
        guard let panel = contentsPanel else { return }
        if let boxHoveredID, !collectionPageItems.contains(where: { $0.id == boxHoveredID }) { clearBoxHover() }
        let content = MagneticBoxContents(
            items: items, historyStore: historyStore,
            onRetrieve: { [weak self] item in self?.locateInFan(item.id) },
            onHover: { [weak self] item, entered in self?.setBoxHover(item, entered: entered) },
            onClose: { [weak self] in self?.closeBox() },
            page: collectionPage, onPageChange: { [weak self] page in self?.setCollectionPage(page) })
        if let hosting = panel.contentView as? MagneticBoxContentsHostingView {
            hosting.rootView = content
        } else {
            let frame = panel.frame
            let hosting = MagneticBoxContentsHostingView(rootView: content)
            hosting.sizingOptions = []
            panel.contentView = hosting
            panel.setFrame(frame, display: true)
        }
    }

    func turnFanPage(_ delta: Int) {
        guard !suspended, !settings.isCollapsed, settings.isEnabled else { return }
        let previous = queue.pageIndex
        queue.setPage(previous + delta, limit: settings.maximumVisible, excluding: Set(desktopFrames.keys))
        guard previous != queue.pageIndex else { return }
        recordInteraction()
        focusedRailID = nil; pendingRailPreview = nil
        closeBox()
        // Once the page changes, the old thumbnails must not remain actionable while the next batch loads.
        for id in cardPanels.keys where desktopFrames[id] == nil { cardPanels[id]?.orderOut(nil) }
        refresh(force: true)
    }

    func locateInFan(_ id: UUID) {
        guard !suspended, settings.isEnabled, !settings.isCollapsed,
              collectionItems.contains(where: { $0.id == id }) else { return }
        queue.locate(id, limit: settings.maximumVisible, excluding: Set(desktopFrames.keys))
        focusedRailID = id; pendingRailPreview = id
        recordInteraction(); closeBox(); refresh(force: true)
    }

    func setCollectionPage(_ page: Int) {
        guard contentsPanel?.isVisible == true, !suspended else { return }
        collectionPage = min(max(0, page), max(0, (collectionItems.count - 1) / 20))
        clearBoxHover(); recordInteraction(); updateBoxContents()
    }

    private func updatePager(in frame: CGRect) {
        guard railPageCount > 1, !settings.isCollapsed, !suspended else { pagerPanel?.orderOut(nil); return }
        let cards = partition.visible.compactMap { cardPanels[$0]?.frame }
        guard !cards.isEmpty else { pagerPanel?.orderOut(nil); return }
        let rect = MagneticDesktopGeometry.pagerFrame(beside: cards, in: frame)
        let panel = pagerPanel ?? makePanel(frame: rect)
        pagerPanel = panel
        panel.level = .floating
        panel.contentView = MagneticPassiveHostingView(rootView: MagneticFanPagerView(
            first: queue.pageIndex * MagneticDesktopSettings.maximumCardsPerGroup + 1,
            last: queue.pageIndex * MagneticDesktopSettings.maximumCardsPerGroup + partition.visible.count,
            total: fanIDs.count,
            page: queue.pageIndex, pageCount: railPageCount,
            onPrevious: { [weak self] in self?.turnFanPage(-1) }, onNext: { [weak self] in self?.turnFanPage(1) }))
        panel.setFrame(rect, display: true); panel.orderFrontRegardless()
    }
}

private extension CGRect {
    var midpoint: CGPoint { CGPoint(x: midX, y: midY) }
}
