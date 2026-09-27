import AppKit
import BrowserCaptureBridge

@MainActor
final class BrowserCaptureControlController: NSObject {
    private let store = BrowserCaptureControlStore()
    private let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 100),
                                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let pauseButton = NSButton(title: "", target: nil, action: nil)
    private let stopButton = NSButton(title: "", target: nil, action: nil)
    private var timer: Timer?
    private var captureID: UUID?
    private var startedAt = Date.distantPast
    private var desiredPaused = false
    private var stopRequested = false
    var onUnavailable: (() -> Void)?
    var isActive: Bool { timer != nil }

    override init() {
        super.init()
        panel.title = L10n.text("browserExtension.title")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.alignment = .center
        statusLabel.preferredMaxLayoutWidth = 368
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        stopButton.target = self
        stopButton.action = #selector(stopCapture)
        for button in [pauseButton, stopButton] { button.bezelStyle = .rounded }
        let buttons = NSStackView(views: [pauseButton, stopButton])
        buttons.spacing = 12
        let stack = NSStackView(views: [statusLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16)
            ])
        }
    }

    func show() {
        close()
        startedAt = .now
        captureID = nil
        desiredPaused = false
        stopRequested = false
        pauseButton.title = L10n.text("scrollCapture.auto.pause")
        stopButton.title = L10n.text("scrollCapture.stop")
        pauseButton.isEnabled = false
        stopButton.isEnabled = false
        statusLabel.stringValue = L10n.text("browserExtension.controlWaiting")
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - panel.frame.width - 24,
                                         y: screen.visibleFrame.maxY - panel.frame.height - 24))
        }
        // This App panel is outside captureVisibleTab pixels and must never steal
        // Chrome focus or participate in the page's captured coordinates.
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        captureID = nil
        panel.orderOut(nil)
    }

    private func refresh() {
        do {
            if captureID == nil {
                let states = try store.activeStates(since: startedAt)
                // Never control an unrelated or ambiguous native session.
                if states.count == 1 { captureID = states[0].id }
            }
            guard let captureID else {
                if Date.now.timeIntervalSince(startedAt) > 10 {
                    close()
                    onUnavailable?()
                }
                return
            }
            let state = try store.state(id: captureID)
            if state.status == .complete { close(); return }
            guard Date.now.timeIntervalSince(state.updatedAt) < 10 else {
                pauseButton.isEnabled = false
                // A stalled worker can still consume the durable Stop request
                // when it catches up; do not remove the user's way to end it.
                let pending = try store.request(id: captureID)
                stopRequested = pending.stopped
                stopButton.isEnabled = !stopRequested
                statusLabel.stringValue = L10n.text(stopRequested ? "scrollCapture.stopping" : "browserExtension.controlUnavailable")
                return
            }
            let pending = try store.request(id: captureID)
            desiredPaused = pending.paused
            stopRequested = pending.stopped
            pauseButton.title = L10n.text(state.status == .paused ? "scrollCapture.auto.resume" : "scrollCapture.auto.pause")
            pauseButton.isEnabled = !stopRequested && (state.status == .paused || state.status == .capturing) &&
                (state.status == .paused) == desiredPaused
            stopButton.isEnabled = !stopRequested && state.status != .cancelling
            if stopRequested { statusLabel.stringValue = L10n.text("scrollCapture.stopping") }
            else if desiredPaused && state.status != .paused { statusLabel.stringValue = L10n.text("scrollCapture.pausing") }
            else if state.status == .paused { statusLabel.stringValue = L10n.text("scrollCapture.paused") }
            else { statusLabel.stringValue = "\(L10n.text("scrollCapture.status.capturing")) \(state.progress)%" }
        } catch {
            // Native cancellation removes its UUID directory; do not retain stale controls.
            if captureID != nil { close() }
        }
    }

    @objc private func togglePause() {
        guard let captureID, !stopRequested else { return }
        do {
            try store.setRequest(id: captureID, paused: !desiredPaused, stopped: false)
            refresh()
        } catch { close() }
    }

    @objc private func stopCapture() {
        guard let captureID else { return }
        do {
            try store.setRequest(id: captureID, paused: false, stopped: true)
            refresh()
        } catch { close() }
    }
}
