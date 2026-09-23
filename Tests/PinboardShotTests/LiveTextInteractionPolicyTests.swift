import AppKit
import Testing
@testable import PinboardShot

@Suite("Live Text interaction routing")
struct LiveTextInteractionPolicyTests {
    @Test("短拖动会收敛到单个识别字符")
    func shortDragSelectsSingleCharacter() throws {
        let layout = LiveTextCharacterLayout(lines: [
            LiveTextRecognizedLine(
                text: "Pin",
                characterRects: [
                    CGRect(x: 0.10, y: 0.20, width: 0.10, height: 0.30),
                    CGRect(x: 0.20, y: 0.20, width: 0.08, height: 0.30),
                    CGRect(x: 0.28, y: 0.20, width: 0.12, height: 0.30)
                ]
            )
        ])
        let transcript = "Pin"
        let range = try #require(layout.selectionRange(
            in: transcript,
            from: CGPoint(x: 11, y: 30),
            to: CGPoint(x: 18, y: 30),
            contentBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        ))

        #expect(String(transcript[range]) == "P")
    }

    @Test("同一行拖动仍可跨多个字符")
    func dragSelectsMultipleCharacters() throws {
        let layout = LiveTextCharacterLayout(lines: [
            LiveTextRecognizedLine(
                text: "Pin",
                characterRects: [
                    CGRect(x: 0.10, y: 0.20, width: 0.10, height: 0.30),
                    CGRect(x: 0.20, y: 0.20, width: 0.08, height: 0.30),
                    CGRect(x: 0.28, y: 0.20, width: 0.12, height: 0.30)
                ]
            )
        ])
        let transcript = "Pin"
        let range = try #require(layout.selectionRange(
            in: transcript,
            from: CGPoint(x: 21, y: 30),
            to: CGPoint(x: 37, y: 30),
            contentBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        ))

        #expect(String(transcript[range]) == "in")
    }

    @Test("字符几何可独立判断文字命中")
    func characterGeometryProvidesTextHitTesting() {
        let layout = LiveTextCharacterLayout(lines: [
            LiveTextRecognizedLine(
                text: "Pin",
                characterRects: [
                    CGRect(x: 0.10, y: 0.20, width: 0.10, height: 0.30),
                    CGRect(x: 0.20, y: 0.20, width: 0.08, height: 0.30),
                    CGRect(x: 0.28, y: 0.20, width: 0.12, height: 0.30)
                ]
            )
        ])
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        #expect(layout.containsCharacter(at: CGPoint(x: 15, y: 30), contentBounds: bounds))
        #expect(!layout.containsCharacter(at: CGPoint(x: 80, y: 80), contentBounds: bounds))
    }

    @Test("Recognized text receives pointer interaction")
    func recognizedTextWins() {
        #expect(LiveTextInteractionPolicy.routesToText(
            hasInteractiveItem: true,
            hasActiveSelection: false,
            isResizeInteraction: false
        ))
    }

    @Test("Active selection keeps receiving clicks so it can be cleared")
    func activeSelectionWins() {
        #expect(LiveTextInteractionPolicy.routesToText(
            hasInteractiveItem: false,
            hasActiveSelection: true,
            isResizeInteraction: false
        ))
    }

    @Test("Blank image area remains available to move the image")
    func blankAreaFallsThrough() {
        #expect(!LiveTextInteractionPolicy.routesToText(
            hasInteractiveItem: false,
            hasActiveSelection: false,
            isResizeInteraction: false
        ))
    }

    @Test("Resize handles take precedence over recognized text")
    func resizeHandleWins() {
        #expect(!LiveTextInteractionPolicy.routesToText(
            hasInteractiveItem: true,
            hasActiveSelection: true,
            isResizeInteraction: true
        ))
    }

    @Test("贴图交互按缩放、强制移动、文字、空白移动的顺序判定")
    func pinInteractionPriorityIsDeterministic() {
        #expect(PinWindowInteractionPolicy.intent(
            isResizeInteraction: true,
            isForcedMove: true,
            isMoveHandle: true,
            hasTextAtPoint: true
        ) == .resize)
        #expect(PinWindowInteractionPolicy.intent(
            isResizeInteraction: false,
            isForcedMove: true,
            isMoveHandle: false,
            hasTextAtPoint: true
        ) == .move)
        #expect(PinWindowInteractionPolicy.intent(
            isResizeInteraction: false,
            isForcedMove: false,
            isMoveHandle: true,
            hasTextAtPoint: true
        ) == .move)
        #expect(PinWindowInteractionPolicy.intent(
            isResizeInteraction: false,
            isForcedMove: false,
            isMoveHandle: false,
            hasTextAtPoint: true
        ) == .textSelection)
        #expect(PinWindowInteractionPolicy.intent(
            isResizeInteraction: false,
            isForcedMove: false,
            isMoveHandle: false,
            hasTextAtPoint: false
        ) == .move)
    }

    @Test("贴图移动超过四点后才启动")
    func pinMovementUsesActivationDistance() {
        let origin = CGPoint(x: 100, y: 100)
        #expect(!PinWindowDragGeometry.hasActivated(
            from: origin,
            to: CGPoint(x: 103, y: 102)
        ))
        #expect(PinWindowDragGeometry.hasActivated(
            from: origin,
            to: CGPoint(x: 104, y: 100)
        ))
    }

    @Test("贴图视图接收实际鼠标事件后会移动窗口")
    @MainActor
    func pinImageViewMovesItsWindow() throws {
        _ = NSApplication.shared
        let controller = PinWindowController(
            id: UUID(),
            image: NSImage(size: CGSize(width: 320, height: 180)),
            hasShadow: true,
            onClose: { _ in }
        )
        defer { controller.close() }
        controller.show(near: CGPoint(x: 400, y: 400))

        let window = try #require(controller.window)
        _ = try #require(window.contentView as? PinImageView)
        let initialOrigin = window.frame.origin
        let start = CGPoint(x: 120, y: 90)
        let end = CGPoint(x: 150, y: 110)
        window.sendEvent(try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: start,
            modifierFlags: [],
            timestamp: 1,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )))
        window.sendEvent(try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: end,
            modifierFlags: [],
            timestamp: 1.1,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        )))

        #expect(window.frame.origin == CGPoint(
            x: initialOrigin.x + end.x - start.x,
            y: initialOrigin.y + end.y - start.y
        ))
    }

    @Test("贴图窗口直接接管右键菜单事件")
    @MainActor
    func pinPanelRoutesRightClickToContextMenu() throws {
        _ = NSApplication.shared
        let controller = PinWindowController(
            id: UUID(),
            image: NSImage(size: CGSize(width: 320, height: 180)),
            hasShadow: true,
            onClose: { _ in }
        )
        defer { controller.close() }
        controller.show(near: CGPoint(x: 400, y: 400))

        let window = try #require(controller.window as? PinPanel)
        var requestCount = 0
        window.onContextMenuRequested = { _ in requestCount += 1 }
        window.sendEvent(try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: CGPoint(x: 120, y: 90),
            modifierFlags: [],
            timestamp: 1,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )))

        #expect(requestCount == 1)
    }

    @Test("顶部拖动把手避开缩放边缘并提供更大的命中区")
    func pinMoveHandleHasSafeHitArea() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        let handle = PinWindowMoveHandleGeometry.handleRect(in: bounds)
        let hitRect = PinWindowMoveHandleGeometry.hitRect(in: bounds)

        #expect(handle.midX == bounds.midX)
        #expect(handle.maxY < bounds.maxY - PinWindowResizeGeometry.hitSlop)
        #expect(hitRect.contains(handle))
        #expect(hitRect.width > handle.width)
        #expect(hitRect.height > handle.height)
    }
}
