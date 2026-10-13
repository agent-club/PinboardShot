import AppKit
import SwiftUI

extension View {
    func clickCursor() -> some View {
        modifier(ClickCursorModifier())
    }
}

private struct ClickCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isEnabled ? .link : .default)
        } else {
            content.modifier(LegacyClickCursorModifier())
        }
    }
}

struct LegacyClickCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.background {
            // Inactive tool pages stay mounted; they must not register cursor regions over the active page.
            if isEnabled {
                ClickCursorRegion()
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct ClickCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> ClickCursorView {
        ClickCursorView(frame: .zero)
    }

    func updateNSView(_ view: ClickCursorView, context: Context) {}
}

class ClickCursorView: NSView {
    // Let AppKit own cursor lifetime; a passive background must never consume a button click.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(visibleRect, cursor: .pointingHand)
    }
}

class ActionButton: NSButton {
    override var isEnabled: Bool {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
    }
}

final class ActionPopUpButton: NSPopUpButton {
    override var isEnabled: Bool {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
    }
}

final class ActionSegmentedControl: NSSegmentedControl {
    override var isEnabled: Bool {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
    }
}
