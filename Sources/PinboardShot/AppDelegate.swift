import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct CapturePrivacyContext {
    let sourceApplicationBundleIdentifier: String?

    static let unknown = CapturePrivacyContext(sourceApplicationBundleIdentifier: nil)
}

private struct ScrollingCaptureResult {
    let image: NSImage
    let privacyContext: CapturePrivacyContext
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private static let firstLaunchDefaultsKey = "hasCompletedFirstLaunchOnboarding"
    private static let permissionDeferredDefaultsKey = "screenCapturePermissionDeferred"

    private let shortcutStore = ShortcutStore()
    private let hotKeyManager = HotKeyManager()
    private let captureService = ScreenCaptureService()
    private let overlayController = SelectionOverlayController()
    private let scrollCaptureController = ScrollCaptureController()
    private let pinManager = PinWindowManager()
    private let pinWorkspaceStore = PinWorkspaceStore()
    private let pinWorkspaceExporter = PinWorkspaceExporter()
    private let historyStore = HistoryStore()
    private let imageClipboard = ImageClipboard()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let localizationStore = LocalizationStore()
    private let updateManager = UpdateManager()
    private let watermarkService = InvisibleWatermarkService()
    private let annotationEditorController = AnnotationEditorController()
    private let pinMetadataEditorController = PinMetadataEditorController()
    private let captureResultOverlay = CaptureResultOverlayController()
    private let compositionStudioController = CompositionStudioController()
    private let preferencesNavigation = PreferencesNavigationModel()
    private let appHealth = AppHealthModel()

    private var statusItem: NSStatusItem?
    private let statusPopover = NSPopover()
    private var preferencesWindowController: NSWindowController?
    private var legalNoticesWindowController: NSWindowController?
    private var failedHotKeyBindings: [ShortcutBinding] = []
    private var capturePipeline = CapturePipelineState()
    private var activeTrayIconChoice: TrayIconChoice?
    private var trayIconAnimationFrame = 0
    private var trayIconAnimationTimer: Timer?
    private var statusPopoverOutsideClickMonitor: Any?
    private var pendingAutomationPin = false
    private var lastExternalApplicationBundleIdentifier: String?
    private var pinSessionRecoverySaveTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        localizationStore.onLanguageChanged = { [weak self] in
            guard let self else { return }
            self.refreshTrayPanel()
            self.updateStatusItemIcon(.current())
            self.preferencesWindowController?.window?.title = L10n.text("preferences.windowTitle")
        }
        updateManager.onUpdateStateChanged = { [weak self] in
            self?.refreshTrayPanel()
        }
        pinManager.onRequestSaveWorkspace = { [weak self] in
            self?.presentSavePinWorkspacePrompt()
        }
        pinManager.onRequestEditMetadata = { [weak self] id, metadata in
            guard let self else { return }
            self.pinMetadataEditorController.present(initial: metadata) { [weak self] updatedMetadata in
                self?.pinManager.updateMetadata(for: id, metadata: updatedMetadata)
            }
        }
        pinManager.onSessionChanged = { [weak self] in
            self?.schedulePinSessionRecoverySave()
        }
        configureStatusItem()
        restorePinSessionIfEnabled()
        hotKeyManager.onAction = { [weak self] action in self?.perform(action) }
        registerShortcuts()
        presentFirstLaunchOrRequestPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pinSessionRecoverySaveTimer?.invalidate()
        pinSessionRecoverySaveTimer = nil
        flushPinSessionRecovery()
        stopStatusItemIconAnimation()
        removeStatusPopoverOutsideClickMonitor()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        hotKeyManager.unregisterAll()
        if UserDefaults.standard.bool(forKey: "clearHistoryOnQuit") {
            try? historyStore.clear()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme?.lowercased() == "pinboardshot" {
                handleAutomationURL(url)
            } else {
                pinImageFile(at: url)
            }
        }
    }

    @objc private func frontmostApplicationDidChange(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        rememberExternalApplication(application)
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleIdentifier = application.bundleIdentifier,
              !bundleIdentifier.isEmpty else { return }
        lastExternalApplicationBundleIdentifier = bundleIdentifier
    }

    private func currentCapturePrivacyContext() -> CapturePrivacyContext {
        if let application = NSWorkspace.shared.frontmostApplication,
           application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           let bundleIdentifier = application.bundleIdentifier,
           !bundleIdentifier.isEmpty {
            return CapturePrivacyContext(sourceApplicationBundleIdentifier: bundleIdentifier)
        }
        return CapturePrivacyContext(
            sourceApplicationBundleIdentifier: lastExternalApplicationBundleIdentifier
        )
    }

    private func restorePinSessionIfEnabled() {
        guard PinSessionRecoverySettings().isEnabled else {
            try? pinWorkspaceStore.clearRecoverySession()
            return
        }
        guard let recovery = pinWorkspaceStore.loadRecoverySession() else { return }
        _ = pinManager.restoreWorkspace(recovery.entries)
        if !recovery.pinsAreVisible, pinManager.pinsAreVisible {
            pinManager.toggleAll()
        }
        schedulePinSessionRecoverySave()
    }

    private func schedulePinSessionRecoverySave() {
        pinSessionRecoverySaveTimer?.invalidate()
        pinSessionRecoverySaveTimer = nil
        guard PinSessionRecoverySettings().isEnabled else {
            try? pinWorkspaceStore.clearRecoverySession()
            return
        }
        // A stale snapshot must not survive while a newer pin state is waiting for its debounced save.
        do {
            try pinWorkspaceStore.invalidateRecoverySession()
        } catch {
            try? pinWorkspaceStore.clearRecoverySession()
        }
        pinSessionRecoverySaveTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) {
            [weak self] _ in
            Task { @MainActor in self?.flushPinSessionRecovery() }
        }
    }

    private func flushPinSessionRecovery() {
        pinSessionRecoverySaveTimer?.invalidate()
        pinSessionRecoverySaveTimer = nil
        guard PinSessionRecoverySettings().isEnabled else {
            try? pinWorkspaceStore.clearRecoverySession()
            return
        }
        do {
            _ = try pinWorkspaceStore.saveRecoverySession(
                captures: pinManager.sessionCaptures(),
                pinsAreVisible: pinManager.pinsAreVisible
            )
        } catch {
            try? pinWorkspaceStore.invalidateRecoverySession()
        }
    }

    private func setPinSessionRecoveryEnabled(_ enabled: Bool) {
        let settings = PinSessionRecoverySettings()
        settings.isEnabled = enabled
        if enabled {
            schedulePinSessionRecoverySave()
        } else {
            pinSessionRecoverySaveTimer?.invalidate()
            pinSessionRecoverySaveTimer = nil
            try? pinWorkspaceStore.clearRecoverySession()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(toggleStatusPopover(_:))
        statusPopover.behavior = .transient
        statusPopover.animates = false
        statusPopover.delegate = self
        refreshTrayPanel()
        updateStatusItemIcon(.current())
    }

    private func updateStatusItemIcon(_ choice: TrayIconChoice) {
        stopStatusItemIconAnimation()
        activeTrayIconChoice = choice
        trayIconAnimationFrame = 0
        statusItem?.button?.image = choice.statusBarImage()

        startStatusItemIconAnimationIfNeeded()
    }

    private func startStatusItemIconAnimationIfNeeded() {
        guard let activeTrayIconChoice,
              activeTrayIconChoice.isAnimated,
              !statusPopover.isShown,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let timer = Timer(
            timeInterval: TrayIconChoice.animationInterval,
            target: self,
            selector: #selector(advanceStatusItemIconAnimation),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        trayIconAnimationTimer = timer
    }

    @objc private func advanceStatusItemIconAnimation() {
        guard let activeTrayIconChoice, !statusPopover.isShown else { return }
        trayIconAnimationFrame += 1
        statusItem?.button?.image = activeTrayIconChoice.statusBarImage(frameIndex: trayIconAnimationFrame)
    }

    @objc private func accessibilityDisplayOptionsDidChange() {
        updateStatusItemIcon(.current())
    }

    private func stopStatusItemIconAnimation() {
        trayIconAnimationTimer?.invalidate()
        trayIconAnimationTimer = nil
    }

    private func refreshTrayPanel() {
        let permissionGranted = captureService.hasScreenCaptureAccess
        appHealth.screenCapturePermissionGranted = permissionGranted
        appHealth.failedHotKeyCount = failedHotKeyBindings.count
        let pinCount = pinManager.count
        let screenHeight = statusItem?.button?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? TrayPanelMetrics.fallbackHeight + TrayPanelMetrics.screenVerticalMargin

        func makePanel(height: CGFloat?) -> TrayPanelView {
            TrayPanelView(
                permissionGranted: permissionGranted,
                failedHotKeyCount: failedHotKeyBindings.count,
                canCheckForUpdates: updateManager.canCheckForUpdates,
                lastUpdateCheckDate: updateManager.lastUpdateCheckDate,
                updateNotice: updateManager.updateNotice,
                pinCount: pinCount,
                pinsAreVisible: pinCount > 0 && pinManager.pinsAreVisible,
                height: height,
                onPinShadowChanged: { [weak self] enabled in
                    self?.pinManager.setShadowsEnabled(enabled)
                },
                onDismissUpdateNotice: { [weak self] in
                    self?.updateManager.dismissUpdateNotice()
                },
                onCommand: { [weak self] command in
                    self?.runTrayCommand(command)
                }
            )
        }

        let sizingController = NSHostingController(rootView: makePanel(height: nil))
        let measuredHeight = sizingController.sizeThatFits(
            in: NSSize(
                width: TrayPanelMetrics.width,
                height: TrayPanelMetrics.measurementHeightLimit
            )
        ).height
        let preferredHeight = measuredHeight.isFinite && measuredHeight > 0
            ? measuredHeight
            : TrayPanelMetrics.fallbackHeight
        let panelHeight = TrayPanelMetrics.height(
            preferredHeight: preferredHeight,
            availableHeight: screenHeight
        )
        let panelSize = NSSize(
            width: TrayPanelMetrics.width,
            height: panelHeight
        )
        statusPopover.contentSize = panelSize
        statusPopover.contentViewController = NSHostingController(
            rootView: makePanel(height: panelHeight)
        )
    }

    @objc private func toggleStatusPopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if statusPopover.isShown {
            statusPopover.performClose(sender)
        } else {
            stopStatusItemIconAnimation()
            refreshTrayPanel()
            NSApp.activate(ignoringOtherApps: true)
            statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            button.isHighlighted = true
        }
    }

    func popoverDidShow(_ notification: Notification) {
        installStatusPopoverOutsideClickMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        removeStatusPopoverOutsideClickMonitor()
        statusItem?.button?.isHighlighted = false
        startStatusItemIconAnimationIfNeeded()
    }

    private func installStatusPopoverOutsideClickMonitor() {
        removeStatusPopoverOutsideClickMonitor()
        statusPopoverOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.statusPopover.isShown else { return }
                    self.statusPopover.performClose(nil)
                }
            }
        )
    }

    private func removeStatusPopoverOutsideClickMonitor() {
        guard let statusPopoverOutsideClickMonitor else { return }
        NSEvent.removeMonitor(statusPopoverOutsideClickMonitor)
        self.statusPopoverOutsideClickMonitor = nil
    }

    private func runTrayCommand(_ command: TrayPanelCommand) {
        statusPopover.performClose(nil)
        switch command {
        case .capture(let action): perform(action)
        case .closeAllPins: closeAllPins()
        case .restorePinInteraction: restoreAllPinInteraction()
        case .detectWatermark: detectInvisibleWatermark()
        case .requestScreenRecordingPermission: requestScreenRecordingPermission()
        case .showHotKeyFailures: showHotKeyFailures()
        case .showPreferences(let section): showPreferences(section: section)
        case .showQuickStart: showQuickStart()
        case .showLetterToUsers: showLetterToUsers()
        case .showLegalNotices: showLegalNotices()
        case .showAbout: showAbout()
        case .checkForUpdates: updateManager.checkForUpdates(nil)
        case .quit: NSApp.terminate(nil)
        }
    }

    private func registerShortcuts() {
        failedHotKeyBindings = hotKeyManager.register(bindings: shortcutStore.bindings)
        refreshTrayPanel()
    }

    private func presentFirstLaunchOrRequestPermission() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            if !UserDefaults.standard.bool(forKey: Self.firstLaunchDefaultsKey) {
                self.showFirstLaunchOnboarding()
            } else if !self.captureService.hasScreenCaptureAccess,
                      !UserDefaults.standard.bool(forKey: Self.permissionDeferredDefaultsKey) {
                _ = self.captureService.requestPermissionIfNeeded()
                self.refreshTrayPanel()
            }
        }
    }

    private func showFirstLaunchOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.text("onboarding.title")
        alert.informativeText = L10n.text("onboarding.message")
        alert.addButton(withTitle: L10n.text("onboarding.requestPermission"))
        alert.addButton(withTitle: L10n.text("onboarding.later"))
        UserDefaults.standard.set(true, forKey: Self.firstLaunchDefaultsKey)
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.set(false, forKey: Self.permissionDeferredDefaultsKey)
            requestScreenRecordingPermission()
        } else {
            UserDefaults.standard.set(true, forKey: Self.permissionDeferredDefaultsKey)
        }
        refreshTrayPanel()
    }

    @objc private func closeAllPins() { pinManager.closeAll() }
    @objc private func restoreAllPinInteraction() { pinManager.restoreInteraction() }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func requestScreenRecordingPermission() {
        UserDefaults.standard.set(false, forKey: Self.permissionDeferredDefaultsKey)
        if captureService.requestPermissionIfNeeded() {
            refreshTrayPanel()
        } else {
            present(error: PinboardShotError.permissionDenied)
        }
    }

    @objc private func showHotKeyFailures() {
        let names = failedHotKeyBindings.map {
            "• \($0.action.title) (\($0.shortcut.displayText))"
        }.joined(separator: "\n")
        let alert = NSAlert()
        alert.messageText = L10n.text("hotkey.failure.title")
        alert.informativeText = L10n.text("hotkey.failure.message", names)
        alert.runModal()
    }

    @objc private func showQuickStart() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.text("quickStart.title")
        alert.informativeText = L10n.text("quickStart.message")
        alert.addButton(withTitle: L10n.text("common.done"))
        alert.runModal()
    }

    @objc private func showLetterToUsers() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.text("letterToUsers.title")
        alert.informativeText = L10n.text("letterToUsers.message")
        alert.addButton(withTitle: L10n.text("common.done"))
        alert.runModal()
    }

    @objc private func showLegalNotices() {
        NSApp.activate(ignoringOtherApps: true)
        guard let noticeText = bundledLegalText(named: "NOTICE", fileExtension: "md"),
              let licenseText = bundledLegalText(named: "LICENSE", fileExtension: "txt") else {
            let alert = NSAlert()
            alert.messageText = L10n.text("legalNotices.missingTitle")
            alert.informativeText = L10n.text("legalNotices.missingMessage")
            alert.addButton(withTitle: L10n.text("common.done"))
            alert.runModal()
            return
        }

        let panelView = LegalNoticesPanelView(
            noticeText: noticeText,
            licenseText: licenseText,
            closeAction: { [weak self] in
                self?.legalNoticesWindowController?.close()
                self?.legalNoticesWindowController = nil
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("legalNotices.title")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: panelView)

        let controller = NSWindowController(window: window)
        legalNoticesWindowController = controller
        controller.showWindow(nil)
    }

    private func bundledLegalText(named name: String, fileExtension: String) -> String? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Legal"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func detectInvisibleWatermark() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.message = L10n.text("watermark.detect.panelMessage")
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }

        let alert = NSAlert()
        switch watermarkService.detect(in: data) {
        case .notFound:
            alert.messageText = L10n.text("watermark.detect.notFoundTitle")
            alert.informativeText = L10n.text("watermark.detect.notFoundMessage")
        case .recordMissing(let id):
            alert.messageText = L10n.text("watermark.detect.recordMissingTitle")
            alert.informativeText = L10n.text("watermark.detect.recordMissingMessage", id.uuidString)
        case .invalidRecord(let id):
            alert.messageText = L10n.text("watermark.detect.invalidTitle")
            alert.informativeText = L10n.text("watermark.detect.invalidMessage", id.uuidString)
        case .verified(let record, let exactImage):
            alert.messageText = L10n.text("watermark.detect.verifiedTitle")
            alert.informativeText = watermarkDetails(record: record, exactImage: exactImage)
        }
        alert.addButton(withTitle: L10n.text("common.done"))
        alert.runModal()
    }

    private func perform(_ action: CaptureAction) {
        switch action {
        case .region:
            Task { await captureRegion(pin: false) }
        case .delayedRegion:
            Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await captureRegion(pin: false)
            }
        case .repeatRegion:
            Task { await repeatLastRegion() }
        case .filePin:
            chooseImageFileToPin()
        case .scrollingRegion:
            Task { await captureScrollingRegion() }
        case .regionAndPin:
            Task { await captureRegion(pin: true) }
        case .display:
            Task { await captureDisplay() }
        case .window:
            Task { await captureWindow() }
        case .clipboardPin:
            pinClipboardImage()
        case .togglePins:
            pinManager.toggleAll()
        }
    }

    private func captureRegion(pin: Bool) async {
        guard capturePipeline.beginCapture() else { return }
        let privacyContext = currentCapturePrivacyContext()
        CaptureDiagnostics.begin()
        do {
            // 先冻结屏幕快照，再显示蒙版，避免 WindowServer 把蒙版合成进成品。
            let prepared = try await captureService.prepareRegionCapture()
            CaptureDiagnostics.recordPhase("snapshotPrepared")
            guard let selection = await overlayController.selectRegion(
                snapshot: prepared.snapshot,
                on: prepared.screen,
                showsToolbar: !pin,
                defaultDisposition: pin ? .pin : .copy
            ) else {
                capturePipeline.cancelCapture()
                CaptureDiagnostics.recordPhase("selectionCancelled")
                return
            }
            CaptureDiagnostics.recordPhase("selectionCompleted")
            LastCaptureRegionStore.save(
                selection: selection.rect,
                in: prepared.snapshot.screenFrame
            )
            if case .scrollingCapture = selection.disposition {
                guard let result = try await captureScrollingImage(for: selection) else {
                    capturePipeline.cancelCapture()
                    CaptureDiagnostics.recordPhase("scrollCaptureCancelled")
                    return
                }
                let shouldPin = capturePipeline.completeCapture(explicitPin: false)
                completeCapture(result.image, pin: shouldPin, privacyContext: result.privacyContext)
                CaptureDiagnostics.recordPhase("scrollCaptureCompleted")
                refreshTrayPanel()
                return
            }
            let nativeImage = try captureService.captureRegionNative(
                selection.rect,
                from: prepared.snapshot,
                annotations: selection.annotations
            )
            let image = try await captureService.scaleForExport(nativeImage)
            let shouldPin = capturePipeline.completeCapture(explicitPin: selection.disposition == .pin)
            completeCapture(image, pin: shouldPin, privacyContext: privacyContext)
            CaptureDiagnostics.recordPhase("completed")
        } catch {
            capturePipeline.cancelCapture()
            CaptureDiagnostics.recordError(error)
            refreshTrayPanel()
            present(error: error)
        }
    }

    private func repeatLastRegion() async {
        guard capturePipeline.beginCapture() else { return }
        let privacyContext = currentCapturePrivacyContext()
        CaptureDiagnostics.begin()
        do {
            let prepared = try await captureService.prepareRegionCapture()
            guard let selection = LastCaptureRegionStore.selection(in: prepared.snapshot.screenFrame) else {
                throw PinboardShotError.lastRegionUnavailable
            }
            let nativeImage = try captureService.captureRegionNative(selection, from: prepared.snapshot)
            let image = try await captureService.scaleForExport(nativeImage)
            let shouldPin = capturePipeline.completeCapture(explicitPin: false)
            completeCapture(image, pin: shouldPin, privacyContext: privacyContext)
            CaptureDiagnostics.recordPhase("repeatedRegionCompleted")
            refreshTrayPanel()
        } catch {
            capturePipeline.cancelCapture()
            CaptureDiagnostics.recordError(error)
            present(error: error)
        }
    }

    private func captureScrollingRegion() async {
        guard capturePipeline.beginCapture() else { return }
        CaptureDiagnostics.begin()
        do {
            let prepared = try await captureService.prepareRegionCapture()
            CaptureDiagnostics.recordPhase("scrollSelectionPrepared")
            guard let selection = await overlayController.selectRegion(
                snapshot: prepared.snapshot,
                on: prepared.screen,
                showsToolbar: false,
                defaultDisposition: .scrollingCapture,
                hintText: L10n.text("scrollCapture.selectionHint")
            ) else {
                capturePipeline.cancelCapture()
                CaptureDiagnostics.recordPhase("scrollSelectionCancelled")
                return
            }
            guard let result = try await captureScrollingImage(for: selection) else {
                capturePipeline.cancelCapture()
                CaptureDiagnostics.recordPhase("scrollCaptureCancelled")
                return
            }
            let shouldPin = capturePipeline.completeCapture(explicitPin: false)
            completeCapture(result.image, pin: shouldPin, privacyContext: result.privacyContext)
            CaptureDiagnostics.recordPhase("scrollCaptureCompleted")
            refreshTrayPanel()
        } catch {
            capturePipeline.cancelCapture()
            CaptureDiagnostics.recordError(error)
            refreshTrayPanel()
            present(error: error)
        }
    }

    private func captureScrollingImage(for selection: SelectedRegion) async throws -> ScrollingCaptureResult? {
        defer { overlayController.dismissRetainedOverlay() }
        let target = try await captureService.scrollCaptureTarget(for: selection)
        guard let image = try await scrollCaptureController.capture(target: target) else { return nil }
        return ScrollingCaptureResult(
            image: image,
            privacyContext: CapturePrivacyContext(
                sourceApplicationBundleIdentifier: target.sourceApplicationBundleIdentifier
            )
        )
    }

    private func captureDisplay() async {
        guard capturePipeline.beginCapture() else { return }
        let privacyContext = currentCapturePrivacyContext()
        CaptureDiagnostics.begin()
        do {
            let image = try await captureService.captureCurrentDisplay()
            CaptureDiagnostics.recordPhase("displayCaptured")
            let shouldPin = capturePipeline.completeCapture(explicitPin: false)
            completeCapture(image, pin: shouldPin, privacyContext: privacyContext)
            CaptureDiagnostics.recordPhase("displayCompleted")
            refreshTrayPanel()
        } catch {
            capturePipeline.cancelCapture()
            CaptureDiagnostics.recordError(error)
            present(error: error)
        }
    }

    private func captureWindow() async {
        guard capturePipeline.beginCapture() else { return }
        CaptureDiagnostics.begin()
        do {
            let result = try await captureService.captureWindowUnderPointer()
            CaptureDiagnostics.recordPhase("windowCaptured")
            let shouldPin = capturePipeline.completeCapture(explicitPin: false)
            completeCapture(
                result.image,
                pin: shouldPin,
                privacyContext: CapturePrivacyContext(
                    sourceApplicationBundleIdentifier: result.sourceApplicationBundleIdentifier
                )
            )
            CaptureDiagnostics.recordPhase("windowCompleted")
            refreshTrayPanel()
        } catch {
            capturePipeline.cancelCapture()
            CaptureDiagnostics.recordError(error)
            present(error: error)
        }
    }

    private func completeCapture(
        _ image: NSImage,
        pin: Bool,
        applyWatermark: Bool = true,
        privacyContext: CapturePrivacyContext = .unknown
    ) {
        // 所有路径只编码一次 PNG，再复用于剪贴板和历史，控制 4K/8K 峰值内存。
        let capture: WatermarkedCapture
        do {
            if applyWatermark {
                capture = try watermarkService.prepareCapture(image)
            } else if let pngData = image.pngData {
                capture = WatermarkedCapture(image: image, pngData: pngData)
            } else {
                throw PinboardShotError.imageEncodingFailed
            }
        } catch {
            present(error: error)
            return
        }
        if !imageClipboard.write(capture.image, pngData: capture.pngData) {
            present(error: PinboardShotError.imageEncodingFailed)
        }
        let historyItem: HistoryItem?
        do {
            historyItem = try historyStore.add(
                capture.image,
                pngData: capture.pngData,
                sourceApplicationBundleIdentifier: privacyContext.sourceApplicationBundleIdentifier
            )
        } catch {
            historyItem = nil
            present(error: error)
        }
        if let historyItem, HistorySettings.ocrIndexingEnabled() {
            indexHistoryText(for: historyItem, image: capture.image)
        }
        let shouldPin = pin || pendingAutomationPin
        pendingAutomationPin = false
        if shouldPin { pinManager.pin(image: capture.image) }
        presentQuickCaptureOverlay(capture.image, privacyContext: privacyContext)
    }

    private func indexHistoryText(for item: HistoryItem, image: NSImage) {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            try? historyStore.updateOCRStatus(itemID: item.id, status: .failed)
            return
        }
        guard let request = try? historyStore.beginOCRIndexing(itemID: item.id) else { return }
        let source = HistoryOCRSource(image: cgImage)
        Task { @MainActor [weak self] in
            let recognizedText = await Task.detached(priority: .utility) {
                try? TextRecognitionService.recognizeText(in: source.image)
            }.value
            guard let self else { return }
            guard HistorySettings.ocrIndexingEnabled() else {
                try? self.historyStore.cancelOCRIndexing(request)
                return
            }
            if let recognizedText {
                try? self.historyStore.completeOCRIndexing(
                    request,
                    status: recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .indexed,
                    text: recognizedText,
                    indexedAt: Date()
                )
            } else {
                try? self.historyStore.completeOCRIndexing(
                    request,
                    status: .failed,
                    indexedAt: Date()
                )
            }
        }
    }

    private func presentQuickCaptureOverlay(
        _ image: NSImage,
        privacyContext: CapturePrivacyContext
    ) {
        guard QuickCaptureOverlaySettings.isEnabled() else { return }
        captureResultOverlay.show(
            image: image,
            actions: QuickCaptureOverlayActions(
                copy: { [weak self] in
                    guard let self else { return }
                    if !self.imageClipboard.write(image) {
                        self.present(error: PinboardShotError.imageEncodingFailed)
                        return
                    }
                    self.captureResultOverlay.dismiss()
                },
                save: { [weak self] in
                    guard let self else { return }
                    do {
                        if try ImageFileExporter.save(image) {
                            self.captureResultOverlay.dismiss()
                        }
                    } catch {
                        self.present(error: error)
                    }
                },
                annotate: { [weak self] in
                    guard let self else { return }
                    self.captureResultOverlay.dismiss()
                    Task { @MainActor [weak self] in
                        guard let self,
                              let result = await self.annotationEditorController.edit(image: image) else { return }
                        self.completeCapture(
                            result.image,
                            pin: result.disposition == .pin,
                            applyWatermark: false,
                            privacyContext: privacyContext
                        )
                    }
                },
                pin: { [weak self] in
                    self?.pinManager.pin(image: image)
                    self?.captureResultOverlay.dismiss()
                    self?.refreshTrayPanel()
                },
                dismiss: { [weak self] in self?.captureResultOverlay.dismiss() }
            )
        )
    }

    private func pinClipboardImage() {
        // 截图尚未发布时先排队，完成后直接贴同一张图，避免剪贴板读写竞争。
        if capturePipeline.queuePinIfCapturing() { return }
        guard let image = imageClipboard.read() else {
            present(error: PinboardShotError.clipboardHasNoImage)
            return
        }
        pinManager.pin(image: image)
    }

    private func chooseImageFileToPin() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = L10n.text("fileImport.panelMessage")
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(pinImageFile(at:))
    }

    private func pinImageFile(at url: URL) {
        guard url.isFileURL, let image = NSImage(contentsOf: url) else {
            present(error: PinboardShotError.imageEncodingFailed)
            return
        }
        pinManager.pin(image: image)
        refreshTrayPanel()
    }

    private func handleAutomationURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { query[item.name] = value }
        }
        if query["after"]?.lowercased() == "pin" {
            pendingAutomationPin = true
        }
        switch (url.host?.lowercased(), query["mode"]?.lowercased()) {
        case ("capture", "region"): perform(.region)
        case ("capture", "delayed"): perform(.delayedRegion)
        case ("capture", "repeat"): perform(.repeatRegion)
        case ("capture", "scroll"): perform(.scrollingRegion)
        case ("capture", "display"): perform(.display)
        case ("capture", "window"): perform(.window)
        case ("pin", "clipboard"), ("pin-clipboard", _): perform(.clipboardPin)
        case ("toggle-pins", _): perform(.togglePins)
        case ("pin-file", _):
            if let path = query["path"] {
                pinImageFile(at: URL(fileURLWithPath: path))
            }
        default:
            pendingAutomationPin = false
        }
    }

    @objc private func showPreferences() {
        showPreferences(section: .shortcuts)
    }

    private func showPreferences(section: PreferencesSection) {
        preferencesNavigation.selectedSection = section
        if preferencesWindowController == nil {
            let view = PreferencesView(
                shortcutStore: shortcutStore,
                historyStore: historyStore,
                pinWorkspaceStore: pinWorkspaceStore,
                watermarkStore: watermarkService.store,
                launchAtLoginManager: launchAtLoginManager,
                localizationStore: localizationStore,
                updateManager: updateManager,
                navigation: preferencesNavigation,
                appHealth: appHealth,
                onShortcutsChanged: { [weak self] in self?.registerShortcuts() },
                onPinShadowChanged: { [weak self] enabled in
                    self?.pinManager.setShadowsEnabled(enabled)
                    self?.refreshTrayPanel()
                },
                onTrayIconChanged: { [weak self] choice in
                    self?.updateStatusItemIcon(choice)
                },
                onPinHistoryItem: { [weak self] item in
                    guard let self, let image = self.historyStore.image(for: item) else { return }
                    self.pinManager.pin(image: image)
                },
                onCopyHistoryItem: { [weak self] item in
                    guard let self, let image = self.historyStore.image(for: item) else { return }
                    let originalPNG = try? Data(contentsOf: self.historyStore.fileURL(for: item))
                    if !self.imageClipboard.write(image, pngData: originalPNG) {
                        self.present(error: PinboardShotError.imageEncodingFailed)
                    }
                },
                onSaveHistoryItem: { [weak self] item in
                    guard let self, let image = self.historyStore.image(for: item) else { return }
                    do {
                        _ = try ImageFileExporter.save(image)
                    } catch {
                        self.present(error: error)
                    }
                },
                onCreateBoard: { [weak self] in
                    guard let self else { return }
                    self.compositionStudioController.show(historyStore: self.historyStore) { [weak self] image in
                        self?.pinManager.pin(image: image)
                        self?.refreshTrayPanel()
                    }
                },
                onSavePinWorkspace: { [weak self] name in
                    guard let self else { throw PinWorkspaceStoreError.workspaceUnavailable }
                    return try self.saveCurrentPinWorkspace(named: name)
                },
                onRestorePinWorkspace: { [weak self] workspace in
                    guard let self else { throw PinWorkspaceStoreError.workspaceUnavailable }
                    return try self.restorePinWorkspace(workspace)
                },
                onRenamePinWorkspace: { [weak self] workspace, name in
                    guard let self else { throw PinWorkspaceStoreError.workspaceUnavailable }
                    return try self.pinWorkspaceStore.rename(workspace, to: name)
                },
                onDuplicatePinWorkspace: { [weak self] workspace, name in
                    guard let self else { throw PinWorkspaceStoreError.workspaceUnavailable }
                    return try self.pinWorkspaceStore.duplicate(workspace, name: name)
                },
                onExportPinWorkspace: { [weak self] workspace, format in
                    guard let self else { throw PinWorkspaceStoreError.workspaceUnavailable }
                    return try self.exportPinWorkspace(workspace, format: format)
                },
                onDeletePinWorkspace: { [weak self] workspace in
                    guard let self else { throw PinWorkspaceStoreError.workspaceUnavailable }
                    try self.pinWorkspaceStore.delete(workspace)
                },
                onPinSessionRecoveryChanged: { [weak self] enabled in
                    self?.setPinSessionRecoveryEnabled(enabled)
                },
                onReindexHistoryItem: { [weak self] item in
                    self?.reindexHistoryItem(item)
                },
                onRequestScreenCapturePermission: { [weak self] in self?.requestScreenRecordingPermission() },
                onOpenScreenCaptureSettings: { [weak self] in self?.openScreenRecordingSettings() }
            )
            let controller = NSWindowController(window: NSWindow(contentViewController: NSHostingController(rootView: view)))
            controller.window?.title = L10n.text("preferences.windowTitle")
            controller.window?.styleMask = [.titled, .closable, .miniaturizable]
            controller.window?.isReleasedWhenClosed = false
            preferencesWindowController = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindowController?.showWindow(nil)
        if let window = preferencesWindowController?.window {
            centerPreferencesWindow(window)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @discardableResult
    private func saveCurrentPinWorkspace(named name: String) throws -> PinWorkspaceSummary {
        try pinWorkspaceStore.save(name: name, captures: pinManager.workspaceCaptures())
    }

    private func restorePinWorkspace(_ workspace: PinWorkspaceSummary) throws -> PinWorkspaceRestoreReport {
        let loaded = try pinWorkspaceStore.load(workspace)
        let clearedBindings = pinManager.restoreWorkspace(loaded.entries)
        // Metadata recency is secondary; a failed timestamp update must not undo visible restored pins.
        _ = try? pinWorkspaceStore.markRestored(workspace)
        refreshTrayPanel()
        return PinWorkspaceRestoreReport(
            restoredPinCount: loaded.entries.count,
            skippedPinCount: loaded.skippedPinCount,
            clearedApplicationBindingCount: clearedBindings
        )
    }

    private func exportPinWorkspace(
        _ workspace: PinWorkspaceSummary,
        format: PinWorkspaceExportFormat
    ) throws -> PinWorkspaceExportReport? {
        let panel = NSOpenPanel()
        panel.title = L10n.text("pinWorkspace.export.chooseDirectory")
        panel.prompt = L10n.text("pinWorkspace.export.action")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let directory = panel.url else { return nil }
        return try pinWorkspaceExporter.export(
            pinWorkspaceStore.exportPlan(for: workspace),
            to: directory,
            format: format
        )
    }

    private func reindexHistoryItem(_ item: HistoryItem) {
        guard let image = historyStore.image(for: item) else { return }
        indexHistoryText(for: item, image: image)
    }

    private func presentSavePinWorkspacePrompt() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.text("pinWorkspace.savePromptTitle")
        alert.informativeText = L10n.text("pinWorkspace.savePromptMessage")
        alert.addButton(withTitle: L10n.text("pinWorkspace.save"))
        alert.addButton(withTitle: L10n.text("common.cancel"))
        let nameField = NSTextField(string: "")
        nameField.placeholderString = L10n.text("pinWorkspace.namePlaceholder")
        nameField.frame = CGRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = nameField
        alert.window.initialFirstResponder = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let workspace = try saveCurrentPinWorkspace(named: nameField.stringValue)
            let confirmation = NSAlert()
            confirmation.messageText = L10n.text("pinWorkspace.savedTitle")
            confirmation.informativeText = L10n.text(
                "pinWorkspace.savedMessage",
                workspace.name,
                workspace.pinCount
            )
            confirmation.addButton(withTitle: L10n.text("common.done"))
            confirmation.runModal()
        } catch {
            presentPinWorkspaceError(error)
        }
    }

    private func presentPinWorkspaceError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("pinWorkspace.errorTitle")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.text("common.done"))
        alert.runModal()
    }

    private func centerPreferencesWindow(_ window: NSWindow) {
        guard let screen = statusItem?.button?.window?.screen ?? NSScreen.main else {
            window.setContentSize(NSSize(width: PreferencesWindowMetrics.width, height: PreferencesWindowMetrics.height))
            window.center()
            return
        }
        let contentSize = NSSize(width: PreferencesWindowMetrics.width, height: PreferencesWindowMetrics.height)
        let frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize))
        window.setFrame(
            CGRect(
                origin: PreferencesWindowMetrics.centeredOrigin(
                    windowSize: frame.size,
                    in: screen.visibleFrame
                ),
                size: frame.size
            ),
            display: true
        )
    }

    private func present(error: Error) {
        let alert = NSAlert(error: error)
        if case PinboardShotError.permissionDenied = error {
            alert.addButton(withTitle: L10n.text("permission.openSettings"))
            alert.addButton(withTitle: L10n.text("common.cancel"))
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.runModal()
        }
    }

    private func watermarkDetails(record: InvisibleWatermarkRecord, exactImage: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let emptyValue = L10n.text("watermark.detect.emptyValue")
        return [
            L10n.text("watermark.detect.id", record.id.uuidString),
            L10n.text("watermark.detect.createdAt", formatter.string(from: record.createdAt)),
            L10n.text("watermark.detect.project", record.project.isEmpty ? emptyValue : record.project),
            L10n.text("watermark.detect.recipient", record.recipient.isEmpty ? emptyValue : record.recipient),
            L10n.text("watermark.detect.customText", record.customText.isEmpty ? emptyValue : record.customText),
            exactImage ? L10n.text("watermark.detect.exactImage") : L10n.text("watermark.detect.transformedImage")
        ].joined(separator: "\n")
    }
}

private struct HistoryOCRSource: @unchecked Sendable {
    let image: CGImage
}

private enum LegalNoticesSection: String, CaseIterable, Identifiable {
    case notices
    case license

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notices: L10n.text("legalNotices.noticesTab")
        case .license: L10n.text("legalNotices.licenseTab")
        }
    }
}

private struct LegalNoticesPanelView: View {
    let noticeText: String
    let licenseText: String
    let closeAction: () -> Void

    @State private var selectedSection: LegalNoticesSection = .notices

    private var selectedText: String {
        switch selectedSection {
        case .notices: noticeText
        case .license: licenseText
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 14) {
                Picker("", selection: $selectedSection) {
                    ForEach(LegalNoticesSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)

                ScrollView {
                    Text(selectedText.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                        .lineSpacing(3)
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(18)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.8)
                }
            }
            .padding(18)

            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("legalNotices.title"))
                    .font(.system(size: 18, weight: .semibold))
                Text(L10n.text("legalNotices.message"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selectedText, forType: .string)
            } label: {
                Label(L10n.text("common.copy"), systemImage: "doc.on.doc")
            }
            Button(L10n.text("common.done")) {
                closeAction()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }
}
