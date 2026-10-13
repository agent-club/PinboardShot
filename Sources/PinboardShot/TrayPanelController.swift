import AppKit

enum TrayPanelPlacement {
    static func menuBarAnchor(buttonSize: NSSize, pointer: NSPoint, screenFrame: NSRect) -> NSRect {
        NSRect(
            x: pointer.x - buttonSize.width / 2,
            y: screenFrame.maxY - buttonSize.height,
            width: buttonSize.width,
            height: buttonSize.height
        )
    }

    static func frame(anchor: NSRect, size: NSSize, visibleFrame: NSRect) -> NSRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        return NSRect(
            x: min(max(anchor.midX - width / 2, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(anchor.minY - 6 - height, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }
}

@MainActor
final class TrayPanelController: NSObject {
    private let panel: TrayPanelWindow
    private weak var anchorButton: NSStatusBarButton?
    private var contentSize = NSSize.zero
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var onStatusButtonPressed: ((NSStatusBarButton) -> Void)?
    var onClose: (() -> Void)?

    var isShown: Bool { panel.isVisible }

    override init() {
        panel = TrayPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "PinboardShot"
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        super.init()
    }

    func bind(to button: NSStatusBarButton, onPress: @escaping (NSStatusBarButton) -> Void) {
        onStatusButtonPressed = onPress
        button.target = self
        button.action = #selector(statusButtonPressed(_:))
        // Toggle on the first mouse-down, before menu-bar tracking can change focus.
        // Exclude mouse-up so one physical click cannot toggle twice.
        button.sendAction(on: .leftMouseDown)
    }

    @objc private func statusButtonPressed(_ sender: NSStatusBarButton) {
        onStatusButtonPressed?(sender)
    }

    func update(contentViewController: NSViewController, size: NSSize) {
        contentSize = size
        panel.contentViewController = contentViewController
        // Hosting attachment can change the window size; restore the measured tray size afterward.
        panel.setContentSize(size)
        if isShown { positionPanel() }
    }

    func show(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        guard positionPanel() else { return }
        installMonitors()
        panel.makeKeyAndOrderFront(nil)
        button.isHighlighted = true
    }

    func resizeContent(to size: NSSize) {
        guard contentSize != size else { return }
        contentSize = size
        panel.setContentSize(size)
        if isShown { positionPanel() }
    }

    func close() {
        let wasShown = isShown
        panel.orderOut(nil)
        anchorButton?.isHighlighted = false
        removeMonitors()
        if wasShown { onClose?() }
    }

    @discardableResult
    private func positionPanel() -> Bool {
        guard let button = anchorButton, let window = button.window else {
            return false
        }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        // Menu-bar tracking can temporarily detach its window from a screen, especially
        // when an auto-hidden fullscreen menu bar is appearing or disappearing.
        let anchorScreen = buttonFrame.width > 0 && buttonFrame.height > 0
            ? window.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(buttonFrame) })
            : nil
        guard let screen = anchorScreen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else {
            return false
        }
        // A detached status window has placeholder coordinates below the screen. Position
        // under the clicked menu-bar location instead of clamping that placeholder to the bottom.
        let anchor = anchorScreen == nil
            ? TrayPanelPlacement.menuBarAnchor(
                buttonSize: NSSize(
                    width: max(button.bounds.width, NSStatusBar.system.thickness),
                    height: max(button.bounds.height, NSStatusBar.system.thickness)
                ),
                pointer: NSEvent.mouseLocation, screenFrame: screen.frame
            )
            : buttonFrame
        panel.setFrame(
            TrayPanelPlacement.frame(anchor: anchor, size: contentSize, visibleFrame: screen.visibleFrame),
            display: true
        )
        return true
    }

    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard isShown else { return event }
        if event.type == .keyDown {
            if event.keyCode == 53 {
                close()
                return nil
            }
            return event
        }
        guard [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) else { return event }
        if event.window === panel { return event }
        if let button = anchorButton, event.window === button.window,
           button.convert(button.bounds, to: nil).contains(event.locationInWindow) {
            // The status button owns this mouse-down; closing here would reopen in its action.
            return event
        }
        close()
        return event
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            let forwardsEvent = MainActor.assumeIsolated {
                guard let self else { return true }
                return self.handleLocalEvent(event) != nil
            }
            return forwardsEvent ? event : nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // AppKit invokes event monitors on the main thread. Close synchronously so an old
            // outside click cannot dismiss a panel opened by a later status-button click.
            MainActor.assumeIsolated {
                guard let self else { return }
                if let button = self.anchorButton, let window = button.window {
                    let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
                    if anchor.contains(NSEvent.mouseLocation) { return }
                }
                self.close()
            }
        }
        // Fullscreen menu-bar reveal can change activation without a click. Only explicit
        // mouse-down/Escape events dismiss this nonactivating panel.
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}

private final class TrayPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
