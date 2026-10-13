import AppKit
import Testing
@testable import PinboardShot

@Suite("Tray panel", .serialized)
@MainActor
struct TrayPanelControllerTests {
    @Test("Every status-button click toggles once, including consecutive double-click events")
    func statusButtonDoesNotDismissEarly() throws {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try #require(item.button)
        let window = try #require(button.window)
        let controller = TrayPanelController()
        defer { controller.close() }
        controller.update(contentViewController: NSViewController(), size: NSSize(width: 340, height: 400))
        var closeCount = 0
        var pressCount = 0
        controller.onClose = { closeCount += 1 }
        controller.bind(to: button) { sender in
            pressCount += 1
            if controller.isShown { controller.close() }
            else { controller.show(relativeTo: sender) }
        }
        // Read back the production action mask; retain it for the native tracking test.
        #expect(button.sendAction(on: .leftMouseDown) == Int(NSEvent.EventTypeMask.leftMouseDown.rawValue))
        let rect = button.convert(button.bounds, to: nil)
        for index in 0..<6 {
            let count = index % 2 + 1
            let location = NSPoint(x: rect.midX, y: rect.midY)
            let down = try #require(NSEvent.mouseEvent(
                with: .leftMouseDown, location: location, modifierFlags: [], timestamp: Double(index),
                windowNumber: window.windowNumber, context: nil, eventNumber: index * 2,
                clickCount: count, pressure: 1
            ))
            let up = try #require(NSEvent.mouseEvent(
                with: .leftMouseUp, location: location, modifierFlags: [], timestamp: Double(index) + 0.01,
                windowNumber: window.windowNumber, context: nil, eventNumber: index * 2 + 1,
                clickCount: count, pressure: 0
            ))
            #expect(controller.handleLocalEvent(down) === down)
            // Dispatch through the production button target/action. Native mouse tracking
            // requires a running NSApplication loop, which the Swift Testing host lacks.
            #expect(button.sendAction(button.action, to: button.target))
            #expect(pressCount == index + 1)
            #expect(controller.isShown == (index % 2 == 0))
            #expect(controller.handleLocalEvent(up) === up)
            #expect(pressCount == index + 1)
            #expect(controller.isShown == (index % 2 == 0))
        }
        #expect(closeCount == 3)
        controller.close()
        #expect(closeCount == 3)
    }

    @Test("Panel clicks stay open; outside clicks and Escape dismiss")
    func dismissal() throws {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try #require(item.button)
        let controller = TrayPanelController()
        defer { controller.close() }
        let content = NSViewController()
        controller.update(contentViewController: content, size: NSSize(width: 340, height: 400))
        controller.show(relativeTo: button)
        let panel = try #require(content.view.window)
        #expect(panel is NSPanel)
        #expect(!panel.styleMask.contains(.titled))
        #expect(button.window?.screen?.visibleFrame.contains(panel.frame) == true)
        let inside = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
        #expect(controller.handleLocalEvent(inside) === inside)
        #expect(controller.isShown)
        let outside = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        #expect(controller.handleLocalEvent(outside) === outside)
        #expect(!controller.isShown)
        controller.show(relativeTo: button)
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
        #expect(controller.handleLocalEvent(escape) == nil)
        #expect(!controller.isShown)
        controller.show(relativeTo: button)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(controller.isShown)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!panel.hidesOnDeactivate)
        let hover = try #require(NSEvent.mouseEvent(
            with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
        #expect(controller.handleLocalEvent(hover) === hover)
        #expect(controller.isShown)
        controller.close()
    }

    @Test("Placement stays on the anchor's screen, including negative screen coordinates", arguments: [
        NSRect(x: 0, y: 0, width: 1440, height: 875),
        NSRect(x: -1920, y: -300, width: 1920, height: 1055)
    ])
    func screenEdges(visibleFrame: NSRect) {
        for x in [visibleFrame.minX, visibleFrame.midX, visibleFrame.maxX - 24] {
            let anchor = NSRect(x: x, y: visibleFrame.maxY, width: 24, height: 25)
            let frame = TrayPanelPlacement.frame(
                anchor: anchor, size: NSSize(width: 340, height: 628), visibleFrame: visibleFrame
            )
            #expect(visibleFrame.contains(frame))
            #expect(frame.size == NSSize(width: 340, height: 628))
            #expect(frame.maxY == anchor.minY - 6)
        }
    }

    @Test("Expanding and hiding content resize the open panel without replacing its view or leaving its screen")
    func contentResizeKeepsAnchorAndView() throws {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try #require(item.button)
        let controller = TrayPanelController()
        defer { controller.close() }
        let content = NSViewController()
        controller.update(contentViewController: content, size: NSSize(width: 340, height: 300))
        controller.show(relativeTo: button)
        let panel = try #require(content.view.window)
        let visibleFrame = try #require(button.window?.screen?.visibleFrame)
        for height: CGFloat in [450, 300] {
            controller.resizeContent(to: NSSize(width: 340, height: height))
            #expect(controller.isShown)
            #expect(panel.contentViewController === content)
            #expect(panel.frame.height == height)
            #expect(visibleFrame.contains(panel.frame))
        }
    }

    @Test("A detached fullscreen menu-bar button opens below the clicked display's top edge")
    func detachedMenuBarAnchor() {
        let screen = NSRect(x: -1920, y: -300, width: 1920, height: 1080)
        let pointer = NSPoint(x: -120, y: screen.maxY - 12)
        let anchor = TrayPanelPlacement.menuBarAnchor(
            buttonSize: NSSize(width: 25, height: 33), pointer: pointer, screenFrame: screen
        )
        let frame = TrayPanelPlacement.frame(
            anchor: anchor, size: NSSize(width: 340, height: 628), visibleFrame: screen
        )
        #expect(anchor.midX == pointer.x)
        #expect(frame.maxY == screen.maxY - 33 - 6)
        #expect(screen.contains(frame))
    }
}
