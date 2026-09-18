import AppKit
import Testing
@testable import PinboardShot

@Suite("Capture result overlay", .serialized)
@MainActor
struct CaptureResultOverlayTests {
    @Test("Preview stays fully visible after hosting layout and disappears on dismissal", arguments: [
        CGSize(width: 1600, height: 900),
        CGSize(width: 900, height: 2400),
        CGSize(width: 40, height: 40)
    ])
    func previewStaysOnScreen(imageSize: CGSize) async throws {
        _ = NSApplication.shared
        let controller = CaptureResultOverlayController()
        defer { controller.dismiss() }
        let existingWindows = Set(NSApp.windows.map(\.windowNumber))
        let image = NSImage(size: imageSize)
        controller.show(
            image: image,
            actions: QuickCaptureOverlayActions(copy: {}, save: {}, annotate: {}, pin: {}, dismiss: {})
        )
        let panel = try #require(NSApp.windows.first { !existingWindows.contains($0.windowNumber) && $0 is NSPanel })
        let screen = try #require(NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)
        #expect(panel.frame.size == CGSize(width: 360, height: 112))
        #expect(screen.visibleFrame.contains(panel.frame))
        try await Task.sleep(for: .milliseconds(250))
        #expect(panel.frame.size == CGSize(width: 360, height: 112))
        #expect(screen.visibleFrame.contains(panel.frame))
        #expect(abs(panel.frame.maxX - (screen.visibleFrame.maxX - 20)) < 1)
        #expect(abs(panel.frame.minY - (screen.visibleFrame.minY + 20)) < 1)
        controller.dismiss()
        #expect(!panel.isVisible)
    }

    @Test("Replacing a preview closes the old panel and the new panel dismisses automatically")
    func replacementAndAutomaticDismissal() async throws {
        _ = NSApplication.shared
        let controller = CaptureResultOverlayController()
        defer { controller.dismiss() }
        let existingWindows = Set(NSApp.windows.map(\.windowNumber))
        let actions = QuickCaptureOverlayActions(copy: {}, save: {}, annotate: {}, pin: {}, dismiss: {})
        let image = NSImage(size: CGSize(width: 1600, height: 900))
        controller.show(image: image, actions: actions)
        let first = try #require(NSApp.windows.first { !existingWindows.contains($0.windowNumber) && $0 is NSPanel })
        controller.show(image: image, actions: actions)
        let second = try #require(NSApp.windows.first {
            !existingWindows.contains($0.windowNumber) && $0 !== first && $0 is NSPanel
        })
        #expect(!first.isVisible)
        try await Task.sleep(for: .milliseconds(250))
        #expect(second.isVisible)
        #expect(NSScreen.screens.contains { $0.visibleFrame.contains(second.frame) })
        try await Task.sleep(for: .milliseconds(5100))
        #expect(!second.isVisible)
    }
}
