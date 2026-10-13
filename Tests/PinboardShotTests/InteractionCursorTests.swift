import AppKit
import SwiftUI
import Testing
@testable import PinboardShot

@Suite("Interaction cursors", .serialized)
@MainActor
struct InteractionCursorTests {
    private static let window: NSWindow = {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 320, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }()

    @Test("Legacy SwiftUI cursor regions leave hit testing to controls and unregister inactive pages")
    func swiftUIControlState() throws {
        let hosting = NSHostingView(rootView: CursorFixture(disabled: false))
        Self.window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let region = try #require(cursorRegions(in: hosting).first)
        #expect(region.hitTest(CGPoint(x: region.bounds.midX, y: region.bounds.midY)) == nil)
        #expect(region.bounds.width > 0 && region.bounds.height > 0)
        #expect(cursorRegions(in: hosting).count == 1)

        hosting.rootView = CursorFixture(disabled: true)
        hosting.layoutSubtreeIfNeeded()
        #expect(cursorRegions(in: hosting).isEmpty)
        hosting.rootView = CursorFixture(disabled: false)
        hosting.layoutSubtreeIfNeeded()
        #expect(cursorRegions(in: hosting).count == 1)
    }

    @Test("AppKit action buttons switch between pointing hand and arrow")
    func appKitControlState() {
        let button = RecordingActionButton(frame: CGRect(x: 0, y: 0, width: 80, height: 30))
        button.resetCursorRects()
        #expect(button.recordedCursor === NSCursor.pointingHand)
        button.isEnabled = false
        button.resetCursorRects()
        #expect(button.recordedCursor === NSCursor.arrow)
        button.isEnabled = true
        button.resetCursorRects()
        #expect(button.recordedCursor === NSCursor.pointingHand)
    }

    private func cursorRegions(in view: NSView) -> [ClickCursorView] {
        (view as? ClickCursorView).map { [$0] } ?? view.subviews.flatMap { cursorRegions(in: $0) }
    }
}

private struct CursorFixture: View {
    let disabled: Bool
    var body: some View {
        VStack {
            Text("Passive content")
            Button("Action") {}.modifier(LegacyClickCursorModifier())
        }
        .disabled(disabled)
    }
}

@MainActor
private final class RecordingActionButton: ActionButton {
    var recordedCursor: NSCursor?
    override func addCursorRect(_ aRect: NSRect, cursor anObj: NSCursor) {
        recordedCursor = anObj
    }
}
