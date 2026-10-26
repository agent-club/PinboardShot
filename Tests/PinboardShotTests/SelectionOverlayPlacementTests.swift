import AppKit
import Testing
@testable import PinboardShot

private final class PlacementTestScreen: NSScreen {
    var testFrame = CGRect.zero
    override var frame: CGRect { testFrame }
    override var visibleFrame: CGRect { testFrame }
}

@Suite("Selection overlay screen placement", .serialized)
@MainActor
struct SelectionOverlayPlacementTests {
    @Test("首次创建及跨屏复用都使用屏幕全局原点", arguments: [
        CGRect(x: 1800, y: -100, width: 1200, height: 800),
        CGRect(x: -1440, y: 120, width: 1440, height: 900),
        CGRect(x: 200, y: 1100, width: 1200, height: 800),
        CGRect(x: -200, y: -1000, width: 1200, height: 800)
    ])
    func placement(screenFrame: CGRect) async throws {
        _ = NSApplication.shared
        let context = try #require(CGContext(data: nil, width: 8, height: 8,
            bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let controller = SelectionOverlayController()
        let initialWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        defer {
            for window in NSApp.windows where !initialWindows.contains(ObjectIdentifier(window)) {
                if window is SelectionOverlayWindow { window.close() }
            }
        }

        // 从副屏首次创建，再切换到主屏并切回，覆盖新建与复用两条路径。
        for frame in [screenFrame, CGRect(x: 0, y: 0, width: 1512, height: 982), screenFrame] {
            let screen = PlacementTestScreen()
            screen.testFrame = frame
            let snapshot = ScreenSnapshot(image: image, screenFrame: frame, pointSize: frame.size)
            let task = Task { await controller.selectRegion(snapshot: snapshot, on: screen) }
            var window: SelectionOverlayWindow?
            for _ in 0..<100 {
                await Task.yield()
                window = NSApp.windows.compactMap { $0 as? SelectionOverlayWindow }.first {
                    !initialWindows.contains(ObjectIdentifier($0)) && $0.isVisible
                }
                if window != nil { break }
            }
            let overlay = try #require(window)
            let view = try #require(overlay.contentView as? SelectionOverlayView)
            #expect(overlay.frame == frame)
            #expect(view.bounds == CGRect(origin: .zero, size: frame.size))
            let localSelection = CGRect(x: 40, y: 60, width: 180, height: 120)
            controller.selectionView(view, completed: localSelection, disposition: .copy)
            let selection = try #require(await task.value)
            #expect(selection.rect == localSelection.offsetBy(dx: frame.minX, dy: frame.minY))
            #expect(selection.screen === screen)
        }
    }
}
