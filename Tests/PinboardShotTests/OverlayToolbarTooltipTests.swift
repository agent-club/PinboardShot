import AppKit
import Testing
@testable import PinboardShot

@Suite("Fast toolbar tooltips", .serialized)
@MainActor
struct OverlayToolbarTooltipTests {
    // 与生产覆盖层一样保留窗口，避免测试结束后 AppKit 仍处理窗口事件时释放它。
    private static let testWindow: NSWindow = {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 400, height: 240),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }()

    @Test("Hover shows the text promptly without intercepting clicks")
    func showsPromptly() async throws {
        let (window, container, button) = makeFixture()
        defer { window.orderOut(nil) }
        #expect(OverlayToolbarButton.tooltipDelay == .milliseconds(16))
        let clock = ContinuousClock()
        let start = clock.now
        button.mouseEntered(with: hoverEvent(.mouseEntered, window: window))
        #expect(container.subviews.compactMap { $0 as? OverlayToolbarTooltipView }.isEmpty)
        try await Task.sleep(for: .milliseconds(80))
        let tooltip = try #require(container.subviews.compactMap { $0 as? OverlayToolbarTooltipView }.first)
        #expect(tooltip.subviews.compactMap { $0 as? NSTextField }.first?.stringValue == "文字识别")
        #expect(tooltip.hitTest(CGPoint(x: 2, y: 2)) == nil)
        #expect(container.bounds.contains(tooltip.frame))
        #expect(!tooltip.frame.intersects(button.frame))
        #expect(clock.now - start < .seconds(1))
        button.mouseExited(with: hoverEvent(.mouseExited, window: window))
        #expect(tooltip.superview == nil)
    }

    @Test("Leaving before the delay cancels pending display")
    func cancelsOnExit() async throws {
        let (window, container, button) = makeFixture()
        defer { window.orderOut(nil) }
        button.mouseEntered(with: hoverEvent(.mouseEntered, window: window))
        button.mouseExited(with: hoverEvent(.mouseExited, window: window))
        try await Task.sleep(for: .milliseconds(80))
        #expect(container.subviews.compactMap { $0 as? OverlayToolbarTooltipView }.isEmpty)
    }

    @Test("Fast re-entry displays only the current tooltip")
    func cancelsStaleText() async throws {
        let (window, container, button) = makeFixture()
        defer { window.orderOut(nil) }
        button.mouseEntered(with: hoverEvent(.mouseEntered, window: window))
        button.mouseExited(with: hoverEvent(.mouseExited, window: window))
        button.toolTip = "马赛克"
        button.mouseEntered(with: hoverEvent(.mouseEntered, window: window))
        try await Task.sleep(for: .milliseconds(80))
        let tooltips = container.subviews.compactMap { $0 as? OverlayToolbarTooltipView }
        #expect(tooltips.count == 1)
        #expect(tooltips.first?.subviews.compactMap { $0 as? NSTextField }.first?.stringValue == "马赛克")
        let target = TooltipUpdatingTarget()
        button.target = target
        button.action = #selector(TooltipUpdatingTarget.updateTooltip(_:))
        button.performClick(nil)
        #expect(tooltips.first?.superview == nil)
        try await Task.sleep(for: .milliseconds(80))
        #expect(!container.subviews.contains { $0 is OverlayToolbarTooltipView })
    }

    @Test("Hiding an ancestor or removing a button clears the tooltip")
    func cancelsWhenHiddenOrRemoved() async throws {
        let (window, container, button) = makeFixture()
        defer { window.orderOut(nil) }
        let parent = NSView(frame: container.bounds)
        container.addSubview(parent)
        button.removeFromSuperview()
        parent.addSubview(button)
        button.mouseEntered(with: hoverEvent(.mouseEntered, window: window))
        try await Task.sleep(for: .milliseconds(80))
        #expect(container.subviews.contains { $0 is OverlayToolbarTooltipView })
        parent.isHidden = true
        #expect(!container.subviews.contains { $0 is OverlayToolbarTooltipView })
        parent.isHidden = false
        button.mouseEntered(with: hoverEvent(.mouseEntered, window: window))
        button.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(80))
        #expect(!container.subviews.contains { $0 is OverlayToolbarTooltipView })
    }

    @Test("Window dismissal clears pending and visible tooltips")
    func cancelsWhenWindowDismisses() async throws {
        let (window, container, button) = makeFixture()
        defer { window.orderOut(nil) }
        button.mouseEntered(with: hoverEvent(.mouseEntered, window: window))
        try await Task.sleep(for: .milliseconds(80))
        #expect(container.subviews.contains { $0 is OverlayToolbarTooltipView })
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(!container.subviews.contains { $0 is OverlayToolbarTooltipView })
        button.mouseEntered(with: hoverEvent(.mouseEntered, window: window))
        window.orderOut(nil)
        try await Task.sleep(for: .milliseconds(80))
        #expect(!container.subviews.contains { $0 is OverlayToolbarTooltipView })
    }

    private func makeFixture() -> (NSWindow, NSView, OverlayToolbarButton) {
        let window = Self.testWindow
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 240))
        window.contentView = container
        let button = OverlayToolbarButton(frame: CGRect(x: 12, y: 12, width: 27, height: 32))
        button.toolTip = "文字识别"
        container.addSubview(button)
        window.orderFront(nil)
        return (window, container, button)
    }

    private func hoverEvent(_ type: NSEvent.EventType, window: NSWindow) -> NSEvent {
        NSEvent.enterExitEvent(
            with: type, location: CGPoint(x: 20, y: 20), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil
        )!
    }
}

@MainActor
private final class TooltipUpdatingTarget: NSObject {
    @objc func updateTooltip(_ button: NSButton) {
        button.toolTip = "Updated by action"
    }
}
