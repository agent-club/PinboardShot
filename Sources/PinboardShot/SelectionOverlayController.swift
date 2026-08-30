import AppKit
import Carbon.HIToolbox

enum OverlaySafetyPolicy {
    static let timeout: Duration = .seconds(12)
    static let warningLead: Duration = .seconds(3)
    static let actionTimeout: Duration = .seconds(300)
    static let activityRenewalThrottle: TimeInterval = 0.75
    static let windowLevel: NSWindow.Level = .floating
    static let selectingDimAlpha: CGFloat = 0.48
    // 圈选完成后仍保留明确的外围暗化，避免深色桌面上蒙版视觉消失。
    static let awaitingActionDimAlpha: CGFloat = 0.44
    static let entranceAnimationDuration: TimeInterval = 0.18
    static let animationDefaultsKey = "captureEntranceAnimation"

    static func shouldAnimate(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: animationDefaultsKey) == nil { return true }
        return defaults.bool(forKey: animationDefaultsKey)
    }
}

struct SelectionOverlayLifecycle<Window: AnyObject> {
    private(set) var retainedWindow: Window?
    private(set) var isActive = false

    mutating func begin(makeWindow: () -> Window) -> (window: Window, reused: Bool)? {
        guard !isActive else { return nil }
        isActive = true
        if let retainedWindow { return (retainedWindow, true) }

        let created = makeWindow()
        retainedWindow = created
        return (created, false)
    }

    mutating func finish() -> Window? {
        guard isActive, let retainedWindow else { return nil }
        isActive = false
        return retainedWindow
    }
}

enum SelectionDisposition: Sendable {
    case copy
    case pin
    case edit
    case scrollingCapture
}

enum SelectionToolbarAction: String, CaseIterable, Sendable {
    case annotate
    case scrollingCapture
    case pickColor
    case selectionSize
    case copy
    case pin
    case cancel

    private static let defaultsPrefix = "selectionToolbar.icon."

    var iconDefaultsKey: String { Self.defaultsPrefix + rawValue }

    var defaultSymbolName: String {
        switch self {
        case .annotate: "square.and.pencil"
        case .scrollingCapture: "scroll"
        case .pickColor: "eyedropper"
        case .selectionSize: "aspectratio"
        case .copy: "doc.on.doc"
        case .pin: "pin"
        case .cancel: "xmark"
        }
    }

    var presetSymbolNames: [String] {
        switch self {
        case .annotate: ["square.and.pencil", "pencil.tip.crop.circle", "pencil.line", "paintbrush"]
        case .scrollingCapture: ["scroll", "arrow.down.doc", "arrow.down.to.line.compact", "text.line.first.and.arrowtriangle.forward"]
        case .pickColor: ["eyedropper", "paintpalette", "drop", "circle.lefthalf.filled"]
        case .selectionSize: ["aspectratio", "rectangle", "arrow.up.left.and.arrow.down.right", "rectangle.dashed"]
        case .copy: ["doc.on.doc", "doc", "doc.on.clipboard", "square.on.square"]
        case .pin: ["pin", "pin.fill", "pin.circle", "mappin"]
        case .cancel: ["xmark", "xmark.circle", "xmark.square", "escape"]
        }
    }

    var titleKey: String {
        switch self {
        case .annotate: "preferences.selectionToolbar.annotationTools"
        case .scrollingCapture: "action.scrollingRegion"
        case .pickColor: "overlay.pickColor"
        case .selectionSize: "overlay.editSelectionSize"
        case .copy: "common.copy"
        case .pin: "overlay.pin"
        case .cancel: "common.cancel"
        }
    }

    func symbolName(defaults: UserDefaults = .standard) -> String {
        guard let stored = defaults.string(forKey: iconDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !stored.isEmpty else {
            return defaultSymbolName
        }
        return stored
    }

    static let configurableActions: [SelectionToolbarAction] = [
        .annotate, .scrollingCapture, .pickColor, .selectionSize, .copy, .pin, .cancel
    ]

    static let requiredActions: Set<SelectionToolbarAction> = [.copy, .cancel]
    static let defaultVisibleActions: Set<SelectionToolbarAction> = [.annotate, .copy, .pin, .cancel]
}

/// 独立判断选区双击，避免无边框覆盖窗口中的 AppKit clickCount 不稳定。
struct SelectionDoubleClickTracker: Sendable {
    private var previousClick: (timestamp: TimeInterval, point: CGPoint)?

    mutating func registerClick(
        timestamp: TimeInterval,
        point: CGPoint,
        maximumInterval: TimeInterval = NSEvent.doubleClickInterval,
        maximumDistance: CGFloat = 6
    ) -> Bool {
        guard let previousClick,
              timestamp - previousClick.timestamp <= maximumInterval,
              hypot(point.x - previousClick.point.x, point.y - previousClick.point.y) <= maximumDistance else {
            self.previousClick = (timestamp, point)
            return false
        }
        self.previousClick = nil
        return true
    }

    mutating func reset() {
        previousClick = nil
    }
}

enum SelectionResizeHandle: CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

enum SelectionCursorKind: Equatable, Sendable {
    case crosshair
    case move
    case horizontalResize
    case verticalResize
    case diagonalNorthWestSouthEast
    case diagonalNorthEastSouthWest
}

enum SelectionDimension: Sendable {
    case width
    case height
}

enum SelectionAspectRatioPreset: Int, CaseIterable, Sendable {
    case free
    case current
    case square
    case fourThree
    case threeTwo
    case sixteenNine
    case nineSixteen

    func ratio(currentRatio: CGFloat) -> CGFloat? {
        switch self {
        case .free: nil
        case .current: currentRatio
        case .square: 1
        case .fourThree: 4 / 3
        case .threeTwo: 3 / 2
        case .sixteenNine: 16 / 9
        case .nineSixteen: 9 / 16
        }
    }

    var titleKey: String {
        switch self {
        case .free: "overlay.aspect.free"
        case .current: "overlay.aspect.current"
        case .square: "overlay.aspect.square"
        case .fourThree: "overlay.aspect.fourThree"
        case .threeTwo: "overlay.aspect.threeTwo"
        case .sixteenNine: "overlay.aspect.sixteenNine"
        case .nineSixteen: "overlay.aspect.nineSixteen"
        }
    }
}

struct SelectionSizeGeometry {
    static func constrainedSize(
        width: CGFloat,
        height: CGFloat,
        aspectRatio: CGFloat?,
        editedDimension: SelectionDimension,
        maximumSize: CGSize
    ) -> CGSize {
        var size = CGSize(width: max(3, width), height: max(3, height))
        if let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 {
            switch editedDimension {
            case .width: size.height = size.width / aspectRatio
            case .height: size.width = size.height * aspectRatio
            }
        }
        let scale = min(1, maximumSize.width / size.width, maximumSize.height / size.height)
        return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
    }

    static func centeredRect(size: CGSize, around rect: CGRect, constrainedTo bounds: CGRect) -> CGRect {
        let width = min(max(3, size.width), bounds.width)
        let height = min(max(3, size.height), bounds.height)
        let origin = CGPoint(
            x: min(max(rect.midX - width / 2, bounds.minX), bounds.maxX - width),
            y: min(max(rect.midY - height / 2, bounds.minY), bounds.maxY - height)
        )
        return CGRect(origin: origin, size: CGSize(width: width, height: height)).integral
    }

    static func aspectLockedEndpoint(
        from anchor: CGPoint,
        to proposed: CGPoint,
        aspectRatio: CGFloat,
        constrainedTo bounds: CGRect
    ) -> CGPoint {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return proposed }
        let delta = CGPoint(x: proposed.x - anchor.x, y: proposed.y - anchor.y)
        let horizontalSign: CGFloat = delta.x < 0 ? -1 : 1
        let verticalSign: CGFloat = delta.y < 0 ? -1 : 1
        var width = abs(delta.x)
        var height = abs(delta.y)
        if abs(width / aspectRatio - height) <= abs(height * aspectRatio - width) {
            height = width / aspectRatio
        } else {
            width = height * aspectRatio
        }
        let maximumWidth = horizontalSign > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let maximumHeight = verticalSign > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        let scale = min(1, maximumWidth / max(width, 1), maximumHeight / max(height, 1))
        return CGPoint(
            x: anchor.x + horizontalSign * width * scale,
            y: anchor.y + verticalSign * height * scale
        )
    }
}

struct SelectionResizeGeometry {
    static let minimumDimension: CGFloat = 24
    static let hitSlop: CGFloat = 10

    static func handle(at point: CGPoint, in rect: CGRect) -> SelectionResizeHandle? {
        guard rect.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point) else { return nil }
        let nearLeft = abs(point.x - rect.minX) <= hitSlop
        let nearRight = abs(point.x - rect.maxX) <= hitSlop
        let nearBottom = abs(point.y - rect.minY) <= hitSlop
        let nearTop = abs(point.y - rect.maxY) <= hitSlop

        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearRight && nearBottom { return .bottomRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearTop, point.x >= rect.minX, point.x <= rect.maxX { return .top }
        if nearRight, point.y >= rect.minY, point.y <= rect.maxY { return .right }
        if nearBottom, point.x >= rect.minX, point.x <= rect.maxX { return .bottom }
        if nearLeft, point.y >= rect.minY, point.y <= rect.maxY { return .left }
        return nil
    }

    static func resizedRect(
        _ rect: CGRect,
        using handle: SelectionResizeHandle,
        translation: CGPoint,
        constrainedTo bounds: CGRect,
        aspectRatio: CGFloat? = nil
    ) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .topLeft, .left, .bottomLeft:
            minX = min(max(rect.minX + translation.x, bounds.minX), maxX - minimumDimension)
        default:
            break
        }
        switch handle {
        case .topRight, .right, .bottomRight:
            maxX = max(min(rect.maxX + translation.x, bounds.maxX), minX + minimumDimension)
        default:
            break
        }
        switch handle {
        case .bottomLeft, .bottom, .bottomRight:
            minY = min(max(rect.minY + translation.y, bounds.minY), maxY - minimumDimension)
        default:
            break
        }
        switch handle {
        case .topLeft, .top, .topRight:
            maxY = max(min(rect.maxY + translation.y, bounds.maxY), minY + minimumDimension)
        default:
            break
        }

        let proposed = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else { return proposed }
        return aspectLockedRect(rect, proposed: proposed, handle: handle, ratio: aspectRatio, bounds: bounds)
    }

    private static func aspectLockedRect(
        _ original: CGRect,
        proposed: CGRect,
        handle: SelectionResizeHandle,
        ratio: CGFloat,
        bounds: CGRect
    ) -> CGRect {
        var width: CGFloat
        var height: CGFloat
        switch handle {
        case .left, .right:
            width = proposed.width
            height = width / ratio
        case .top, .bottom:
            height = proposed.height
            width = height * ratio
        default:
            let heightFromWidth = proposed.width / ratio
            let widthFromHeight = proposed.height * ratio
            if abs(heightFromWidth - proposed.height) <= abs(widthFromHeight - proposed.width) {
                width = proposed.width
                height = heightFromWidth
            } else {
                width = widthFromHeight
                height = proposed.height
            }
        }

        let minimumWidth = max(minimumDimension, minimumDimension * ratio)
        width = max(width, minimumWidth)
        height = width / ratio

        let anchor: CGPoint
        switch handle {
        case .topLeft: anchor = CGPoint(x: original.maxX, y: original.minY)
        case .topRight: anchor = CGPoint(x: original.minX, y: original.minY)
        case .bottomRight: anchor = CGPoint(x: original.minX, y: original.maxY)
        case .bottomLeft: anchor = CGPoint(x: original.maxX, y: original.maxY)
        case .left: anchor = CGPoint(x: original.maxX, y: original.midY)
        case .right: anchor = CGPoint(x: original.minX, y: original.midY)
        case .top: anchor = CGPoint(x: original.midX, y: original.minY)
        case .bottom: anchor = CGPoint(x: original.midX, y: original.maxY)
        }

        let maximumWidth: CGFloat
        let maximumHeight: CGFloat
        switch handle {
        case .topLeft:
            maximumWidth = anchor.x - bounds.minX
            maximumHeight = bounds.maxY - anchor.y
        case .topRight:
            maximumWidth = bounds.maxX - anchor.x
            maximumHeight = bounds.maxY - anchor.y
        case .bottomRight:
            maximumWidth = bounds.maxX - anchor.x
            maximumHeight = anchor.y - bounds.minY
        case .bottomLeft:
            maximumWidth = anchor.x - bounds.minX
            maximumHeight = anchor.y - bounds.minY
        case .left:
            maximumWidth = anchor.x - bounds.minX
            maximumHeight = bounds.height
        case .right:
            maximumWidth = bounds.maxX - anchor.x
            maximumHeight = bounds.height
        case .top:
            maximumWidth = bounds.width
            maximumHeight = bounds.maxY - anchor.y
        case .bottom:
            maximumWidth = bounds.width
            maximumHeight = anchor.y - bounds.minY
        }
        let scale = min(1, maximumWidth / width, maximumHeight / height)
        width *= scale
        height *= scale

        let origin: CGPoint
        switch handle {
        case .topLeft: origin = CGPoint(x: anchor.x - width, y: anchor.y)
        case .topRight: origin = anchor
        case .bottomRight: origin = CGPoint(x: anchor.x, y: anchor.y - height)
        case .bottomLeft: origin = CGPoint(x: anchor.x - width, y: anchor.y - height)
        case .left:
            origin = CGPoint(x: anchor.x - width, y: min(max(anchor.y - height / 2, bounds.minY), bounds.maxY - height))
        case .right:
            origin = CGPoint(x: anchor.x, y: min(max(anchor.y - height / 2, bounds.minY), bounds.maxY - height))
        case .top:
            origin = CGPoint(x: min(max(anchor.x - width / 2, bounds.minX), bounds.maxX - width), y: anchor.y)
        case .bottom:
            origin = CGPoint(x: min(max(anchor.x - width / 2, bounds.minX), bounds.maxX - width), y: anchor.y - height)
        }
        return CGRect(origin: origin, size: CGSize(width: width, height: height)).integral
    }

    static func movedRect(
        _ rect: CGRect,
        translation: CGPoint,
        constrainedTo bounds: CGRect
    ) -> CGRect {
        let x = min(max(rect.minX + translation.x, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + translation.y, bounds.minY), bounds.maxY - rect.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: rect.size)
    }

    static func cursorKind(at point: CGPoint, in rect: CGRect) -> SelectionCursorKind {
        switch handle(at: point, in: rect) {
        case .left?, .right?:
            return .horizontalResize
        case .top?, .bottom?:
            return .verticalResize
        case .topLeft?, .bottomRight?:
            return .diagonalNorthWestSouthEast
        case .topRight?, .bottomLeft?:
            return .diagonalNorthEastSouthWest
        case nil:
            return rect.contains(point) ? .move : .crosshair
        }
    }

    static func cursorRect(for handle: SelectionResizeHandle, in rect: CGRect) -> CGRect {
        let edgeInset = hitSlop
        switch handle {
        case .topLeft:
            return CGRect(x: rect.minX - hitSlop, y: rect.maxY - hitSlop, width: hitSlop * 2, height: hitSlop * 2)
        case .top:
            return CGRect(x: rect.minX + edgeInset, y: rect.maxY - hitSlop, width: max(0, rect.width - edgeInset * 2), height: hitSlop * 2)
        case .topRight:
            return CGRect(x: rect.maxX - hitSlop, y: rect.maxY - hitSlop, width: hitSlop * 2, height: hitSlop * 2)
        case .right:
            return CGRect(x: rect.maxX - hitSlop, y: rect.minY + edgeInset, width: hitSlop * 2, height: max(0, rect.height - edgeInset * 2))
        case .bottomRight:
            return CGRect(x: rect.maxX - hitSlop, y: rect.minY - hitSlop, width: hitSlop * 2, height: hitSlop * 2)
        case .bottom:
            return CGRect(x: rect.minX + edgeInset, y: rect.minY - hitSlop, width: max(0, rect.width - edgeInset * 2), height: hitSlop * 2)
        case .bottomLeft:
            return CGRect(x: rect.minX - hitSlop, y: rect.minY - hitSlop, width: hitSlop * 2, height: hitSlop * 2)
        case .left:
            return CGRect(x: rect.minX - hitSlop, y: rect.minY + edgeInset, width: hitSlop * 2, height: max(0, rect.height - edgeInset * 2))
        }
    }

    static func controlPoints(in rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY)
        ]
    }
}

struct SelectedRegion: @unchecked Sendable {
    let rect: CGRect
    let screen: NSScreen
    let disposition: SelectionDisposition
    let annotations: [AnnotationStroke]
}

@MainActor
final class SelectionOverlayController: NSObject, SelectionOverlayViewDelegate {
    private var lifecycle = SelectionOverlayLifecycle<SelectionOverlayWindow>()
    private var continuation: CheckedContinuation<SelectedRegion?, Never>?
    private var escapeMonitor: Any?
    private var timeoutTask: Task<Void, Never>?
    private var timeoutGeneration = 0
    private var currentSafetyTimeout = OverlaySafetyPolicy.timeout
    private var currentWarningLead: Duration? = OverlaySafetyPolicy.warningLead
    private var lastTimeoutRenewalUptime: TimeInterval = 0
    private var cursorIsPushed = false
    private var activeScreen: NSScreen?

    func selectRegion(
        snapshot: ScreenSnapshot,
        on preferredScreen: NSScreen? = nil,
        showsToolbar: Bool = true,
        defaultDisposition: SelectionDisposition = .copy,
        hintText: String? = nil
    ) async -> SelectedRegion? {
        guard continuation == nil else { return nil }
        let mouse = NSEvent.mouseLocation
        guard let screen = preferredScreen
            ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main else {
            return nil
        }

        guard let overlayState = lifecycle.begin(makeWindow: {
            SelectionOverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
        }) else { return nil }
        let overlay = overlayState.window
        overlay.restoreSelectionCaptureMode()
        if overlayState.reused {
            overlay.setFrame(screen.frame, display: false)
        } else {
            // 窗口必须保持不透明，亮区由冻结快照重绘；透明挖洞会把点击穿透到真实桌面。
            overlay.level = OverlaySafetyPolicy.windowLevel
            overlay.backgroundColor = .black
            overlay.isOpaque = true
            overlay.hasShadow = false
            overlay.isReleasedWhenClosed = false
            overlay.animationBehavior = .none
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            overlay.acceptsMouseMovedEvents = true
        }

        let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.delegate = self
        view.previewImage = NSImage(cgImage: snapshot.image, size: snapshot.pointSize)
        view.previewSourceImage = snapshot.image
        view.showsToolbar = showsToolbar
        view.defaultDisposition = defaultDisposition
        view.hintText = hintText
        overlay.contentView = view
        overlay.onUserActivity = { [weak self] eventType in
            self?.handleUserActivity(eventType)
        }
        activeScreen = screen

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSCursor.crosshair.push()
            cursorIsPushed = true
            installEscapeMonitor()
            installSafetyTimeout()
            NSApp.activate(ignoringOtherApps: true)
            overlay.makeKeyAndOrderFront(nil)
            guard lifecycle.isActive else { return }
            overlay.makeFirstResponder(view)
            let pointerInWindow = overlay.convertPoint(fromScreen: NSEvent.mouseLocation)
            view.playEntranceAnimation(at: view.convert(pointerInWindow, from: nil))
        }
    }

    func selectionView(
        _ view: SelectionOverlayView,
        completed rect: CGRect?,
        disposition: SelectionDisposition
    ) {
        guard lifecycle.isActive,
              let window = lifecycle.retainedWindow,
              window.contentView === view,
              let screen = activeScreen else { return }
        let globalRect = rect.map { window.convertToScreen($0) }
        let keepsSelectionVisible = rect != nil && disposition == .scrollingCapture
        if keepsSelectionVisible {
            view.presentScrollingCaptureOutline()
            window.showTransparentSelectionOutline()
        }
        finish(with: globalRect.map {
            SelectedRegion(
                rect: $0,
                screen: screen,
                disposition: disposition,
                annotations: view.annotations
            )
        }, ordersWindowOut: !keepsSelectionVisible)
    }

    func selectionViewDidPrepareActions(_ view: SelectionOverlayView) {
        guard lifecycle.isActive,
              lifecycle.retainedWindow?.contentView === view else { return }
        installSafetyTimeout(after: OverlaySafetyPolicy.actionTimeout, warningLead: nil)
    }

    func dismissRetainedOverlay() {
        guard !lifecycle.isActive,
              let window = lifecycle.retainedWindow else { return }
        window.restoreSelectionCaptureMode()
        window.orderOut(nil)
    }

    private func finish(with result: SelectedRegion?, ordersWindowOut: Bool = true) {
        guard let pending = continuation, let activeWindow = lifecycle.finish() else { return }
        continuation = nil
        activeScreen = nil
        // 所有退出路径统一经过这里，确保遮罩、监听器、光标栈和异步等待一次性收口。
        timeoutGeneration &+= 1
        timeoutTask?.cancel()
        timeoutTask = nil
        activeWindow.onUserActivity = nil
        (activeWindow.contentView as? SelectionOverlayView)?.safetyWarningText = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        if ordersWindowOut {
            activeWindow.orderOut(nil)
        }
        if cursorIsPushed {
            NSCursor.pop()
            cursorIsPushed = false
        }
        // 保留并复用隐藏窗口，避免 AppKit 事件和自动释放池尚未结束时销毁内容视图。
        pending.resume(returning: result)
    }

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            self?.finish(with: nil)
            return nil
        }
    }

    private func handleUserActivity(_ eventType: NSEvent.EventType) {
        guard lifecycle.isActive, continuation != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let isHighFrequencyEvent = eventType == .mouseMoved || eventType == .leftMouseDragged
        if isHighFrequencyEvent,
           now - lastTimeoutRenewalUptime < OverlaySafetyPolicy.activityRenewalThrottle {
            return
        }
        installSafetyTimeout(after: currentSafetyTimeout, warningLead: currentWarningLead)
    }

    private func installSafetyTimeout(
        after duration: Duration = OverlaySafetyPolicy.timeout,
        warningLead: Duration? = OverlaySafetyPolicy.warningLead
    ) {
        currentSafetyTimeout = duration
        currentWarningLead = warningLead
        lastTimeoutRenewalUptime = ProcessInfo.processInfo.systemUptime
        (lifecycle.retainedWindow?.contentView as? SelectionOverlayView)?.safetyWarningText = nil

        timeoutGeneration &+= 1
        let generation = timeoutGeneration
        timeoutTask?.cancel()
        // 框选阶段使用可续期的空闲上限；进入工具操作阶段后切换为较长但仍有限的兜底。
        timeoutTask = Task { [weak self] in
            if let warningLead,
               warningLead > .zero,
               warningLead < duration {
                try? await Task.sleep(for: duration - warningLead)
                guard let self,
                      !Task.isCancelled,
                      self.timeoutGeneration == generation,
                      self.lifecycle.isActive else { return }
                (self.lifecycle.retainedWindow?.contentView as? SelectionOverlayView)?.safetyWarningText =
                    L10n.text("overlay.timeoutWarning")
                try? await Task.sleep(for: warningLead)
            } else {
                try? await Task.sleep(for: duration)
            }
            guard let self,
                  !Task.isCancelled,
                  self.timeoutGeneration == generation,
                  self.lifecycle.isActive else { return }
            self.finish(with: nil)
        }
    }
}

final class SelectionOverlayWindow: NSWindow {
    var onUserActivity: ((NSEvent.EventType) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func restoreSelectionCaptureMode() {
        ignoresMouseEvents = false
        backgroundColor = .black
        isOpaque = true
    }

    func showTransparentSelectionOutline() {
        ignoresMouseEvents = true
        backgroundColor = .clear
        isOpaque = false
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved,
             .leftMouseDown, .leftMouseDragged, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .scrollWheel, .keyDown, .flagsChanged:
            onUserActivity?(event.type)
        default:
            break
        }
        super.sendEvent(event)
    }
}

@MainActor
protocol SelectionOverlayViewDelegate: AnyObject {
    func selectionViewDidPrepareActions(_ view: SelectionOverlayView)
    func selectionView(
        _ view: SelectionOverlayView,
        completed rect: CGRect?,
        disposition: SelectionDisposition
    )
}

extension SelectionOverlayViewDelegate {
    func selectionViewDidPrepareActions(_ view: SelectionOverlayView) {}
}

final class OverlayToolbarButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    var accentColor: NSColor = .controlAccentColor {
        didSet { updateBackground() }
    }
    var isSelectedStyle = false {
        didSet { updateBackground() }
    }
    var isPrimaryActionStyle = false {
        didSet { updateBackground() }
    }
    var isDestructiveStyle = false {
        didSet { updateBackground() }
    }
    override var isEnabled: Bool {
        didSet { updateBackground() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateBackground()
        super.mouseDown(with: event)
        isPressed = false
        updateBackground()
    }

    func setSymbol(_ symbolName: String, accessibilityLabel: String) {
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        ) ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: accessibilityLabel)
        self.image = image?.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
    }

    private func updateBackground() {
        if !isEnabled {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
            contentTintColor = .tertiaryLabelColor
            return
        }
        if isPrimaryActionStyle {
            let alpha: CGFloat = isPressed ? 0.74 : (isHovered ? 0.92 : 0.86)
            layer?.backgroundColor = accentColor.withAlphaComponent(alpha).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(isHovered ? 0.28 : 0.16).cgColor
            contentTintColor = .white
            return
        }
        if isSelectedStyle {
            layer?.backgroundColor = accentColor.withAlphaComponent(isPressed ? 0.34 : 0.24).cgColor
            layer?.borderColor = accentColor.withAlphaComponent(0.52).cgColor
            contentTintColor = .white
            return
        }
        if isDestructiveStyle, isHovered || isPressed {
            layer?.backgroundColor = accentColor.withAlphaComponent(isPressed ? 0.18 : 0.10).cgColor
            layer?.borderColor = accentColor.withAlphaComponent(isPressed ? 0.38 : 0.24).cgColor
            contentTintColor = accentColor
            return
        }
        let backgroundAlpha: CGFloat = isPressed ? 0.14 : (isHovered ? 0.085 : 0.025)
        let borderAlpha: CGFloat = isPressed ? 0.20 : (isHovered ? 0.14 : 0.08)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(backgroundAlpha).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
        contentTintColor = .labelColor
    }
}

enum OverlayToolbarIconPalette {
    static let history = NSColor.controlAccentColor
    static let scrollingCapture = NSColor.controlAccentColor
    static let colorPicker = NSColor.controlAccentColor
    static let selectionSize = NSColor.controlAccentColor
    static let copy = NSColor.controlAccentColor
    static let pin = NSColor.controlAccentColor
    static let destructive = NSColor.systemRed

    static func color(for _: AnnotationTool) -> NSColor {
        .controlAccentColor
    }
}

final class OverlayToolbarSeparator: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        widthAnchor.constraint(equalToConstant: 1).isActive = true
        heightAnchor.constraint(equalToConstant: 18).isActive = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class OverlayToolbarView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 工具栏空隙和阴影范围只负责隔离事件，不能把拖拽继续交给选区视图。
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

final class OverlayToolbarDragHandleView: NSView {
    private var dragStartPoint: CGPoint?
    private let glyphView: NSImageView
    var onDrag: ((CGPoint) -> Void)?
    private var containerView: NSView? { superview?.superview?.superview }

    override init(frame frameRect: NSRect) {
        let image = NSImage(
            systemSymbolName: "circle.grid.3x3.fill",
            accessibilityDescription: L10n.text("overlay.dragToolbar")
        )?.withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        glyphView = NSImageView(image: image ?? NSImage())
        super.init(frame: frameRect)
        widthAnchor.constraint(equalToConstant: 16).isActive = true
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        glyphView.contentTintColor = .secondaryLabelColor
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.setAccessibilityElement(false)
        addSubview(glyphView)
        NSLayoutConstraint.activate([
            glyphView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: 10),
            glyphView.heightAnchor.constraint(equalToConstant: 16)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel(L10n.text("overlay.dragToolbar"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = containerView?.convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let previous = dragStartPoint,
              let point = containerView?.convert(event.locationInWindow, from: nil) else { return }
        onDrag?(CGPoint(x: point.x - previous.x, y: point.y - previous.y))
        dragStartPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
        NSCursor.openHand.set()
    }

}

final class ColorPickerPreviewView: NSVisualEffectView {
    private let swatchView = NSView(frame: .zero)
    private let valueField = NSTextField(labelWithString: "")
    let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    var displayedValue: String { valueField.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func update(color: NSColor, value: String, format: ColorSampleFormat) {
        swatchView.layer?.backgroundColor = color.cgColor
        valueField.stringValue = value
        formatPopup.selectItem(withTag: format.menuTag)
    }

    private func configure() {
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.34
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -5)

        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 8
        swatchView.layer?.cornerCurve = .continuous
        swatchView.layer?.borderWidth = 1
        swatchView.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        swatchView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        swatchView.heightAnchor.constraint(equalToConstant: 34).isActive = true

        valueField.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        valueField.textColor = .labelColor
        valueField.lineBreakMode = .byTruncatingMiddle
        valueField.maximumNumberOfLines = 1
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        formatPopup.controlSize = .small
        formatPopup.font = .systemFont(ofSize: 11.5, weight: .semibold)
        formatPopup.toolTip = L10n.text("colorPicker.format")
        formatPopup.setAccessibilityLabel(L10n.text("colorPicker.format"))
        formatPopup.widthAnchor.constraint(equalToConstant: 86).isActive = true
        for format in ColorSampleFormat.allCases {
            formatPopup.addItem(withTitle: L10n.text(format.titleKey))
            formatPopup.lastItem?.tag = format.menuTag
        }

        let textStack = NSStackView(views: [valueField, formatPopup])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let stack = NSStackView(views: [swatchView, textStack])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
    }
}

final class OverlayWidthControl: NSControl {
    var minimumValue: CGFloat = AnnotationStyleSettings.minimumBrushPixelWidth
    var maximumValue: CGFloat = AnnotationStyleSettings.maximumBrushPixelWidth
    var value: CGFloat = AnnotationStyleSettings.defaultBrushPixelWidth(for: .mosaic) {
        didSet {
            value = min(max(value, minimumValue), maximumValue)
            needsDisplay = true
        }
    }

    private let horizontalInset: CGFloat = 10

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = L10n.text("annotation.width")
        setAccessibilityLabel(L10n.text("annotation.width"))
        setAccessibilityRole(.slider)
        widthAnchor.constraint(equalToConstant: 68).isActive = true
        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        updateValue(with: event, sendsAction: true)
    }

    override func mouseDragged(with event: NSEvent) {
        updateValue(with: event, sendsAction: true)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        adjustValue(by: delta > 0 ? 1 : -1)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case UInt16(kVK_LeftArrow), UInt16(kVK_DownArrow):
            adjustValue(by: -1)
        case UInt16(kVK_RightArrow), UInt16(kVK_UpArrow):
            adjustValue(by: 1)
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = trackRect
        let trackPath = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        trackPath.fill()

        let thumbX = thumbCenterX
        let activeTrack = CGRect(
            x: track.minX,
            y: track.minY,
            width: max(2, thumbX - track.minX),
            height: track.height
        )
        NSColor.controlAccentColor.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: activeTrack, xRadius: track.height / 2, yRadius: track.height / 2).fill()

        let previewDiameter = min(max(value / 3.6, 2.5), 10)
        NSColor.labelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: CGRect(
            x: bounds.minX + 2,
            y: bounds.midY - previewDiameter / 2,
            width: previewDiameter,
            height: previewDiameter
        )).fill()

        let thumbRect = CGRect(x: thumbX - 4, y: bounds.midY - 4, width: 8, height: 8)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(ovalIn: thumbRect).fill()
        NSColor.controlAccentColor.setStroke()
        let thumbBorder = NSBezierPath(ovalIn: thumbRect.insetBy(dx: 0.5, dy: 0.5))
        thumbBorder.lineWidth = 1
        thumbBorder.stroke()
    }

    private var trackRect: CGRect {
        CGRect(x: bounds.minX + horizontalInset + 8, y: bounds.midY - 1, width: bounds.width - horizontalInset * 2 - 8, height: 2)
    }

    private var thumbCenterX: CGFloat {
        let progress = (value - minimumValue) / (maximumValue - minimumValue)
        return trackRect.minX + trackRect.width * progress
    }

    private func updateValue(with event: NSEvent, sendsAction: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let progress = min(max((point.x - trackRect.minX) / trackRect.width, 0), 1)
        value = minimumValue + (maximumValue - minimumValue) * progress
        if sendsAction { _ = sendAction(action, to: target) }
    }

    private func adjustValue(by step: CGFloat) {
        value += step
        _ = sendAction(action, to: target)
    }
}

@MainActor
final class SelectionSizeEditorCoordinator: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let widthField: NSTextField
    let heightField: NSTextField
    let ratioControl: NSSegmentedControl
    let controlsView: NSView
    private let currentRatio: CGFloat
    private let maximumSize: CGSize
    private var isSynchronizing = false
    private(set) var editedDimension: SelectionDimension = .width
    private var modalResult: (size: CGSize, aspectRatio: CGFloat?)?
    private weak var errorLabel: NSTextField?
    private var applyHandler: ((CGSize, CGFloat?) -> Void)?
    private var cancelHandler: (() -> Void)?

    init(size: CGSize, currentRatio: CGFloat, lockedRatio: CGFloat?, maximumSize: CGSize) {
        self.currentRatio = currentRatio
        self.maximumSize = maximumSize
        widthField = NSTextField(string: String(Int(size.width.rounded())))
        heightField = NSTextField(string: String(Int(size.height.rounded())))
        ratioControl = NSSegmentedControl(
            labels: SelectionAspectRatioPreset.allCases.map { preset in
                if preset == .current {
                    return L10n.text("overlay.aspect.currentValue", String(format: "%.2f:1", currentRatio))
                }
                return L10n.text(preset.titleKey)
            },
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )

        let widthLabel = NSTextField(labelWithString: L10n.text("overlay.selectionWidth"))
        widthLabel.font = .systemFont(ofSize: 11, weight: .medium)
        widthLabel.textColor = .secondaryLabelColor
        let heightLabel = NSTextField(labelWithString: L10n.text("overlay.selectionHeight"))
        heightLabel.font = widthLabel.font
        heightLabel.textColor = .secondaryLabelColor
        widthField.alignment = .right
        heightField.alignment = .right
        widthField.setAccessibilityLabel(L10n.text("overlay.selectionWidth"))
        heightField.setAccessibilityLabel(L10n.text("overlay.selectionHeight"))
        widthField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        heightField.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let widthStack = NSStackView(views: [widthLabel, widthField])
        widthStack.orientation = .vertical
        widthStack.alignment = .leading
        widthStack.spacing = 5
        let heightStack = NSStackView(views: [heightLabel, heightField])
        heightStack.orientation = .vertical
        heightStack.alignment = .leading
        heightStack.spacing = 5
        let link = NSImageView(image: NSImage(systemSymbolName: "link", accessibilityDescription: L10n.text("overlay.lockAspectRatio"))!)
        link.contentTintColor = .secondaryLabelColor
        let dimensions = NSStackView(views: [widthStack, link, heightStack])
        dimensions.orientation = .horizontal
        dimensions.alignment = .bottom
        dimensions.spacing = 12

        let ratioLabel = NSTextField(labelWithString: L10n.text("overlay.aspectRatio"))
        ratioLabel.font = .systemFont(ofSize: 11, weight: .medium)
        ratioLabel.textColor = .secondaryLabelColor
        ratioControl.segmentStyle = .rounded
        ratioControl.controlSize = .small
        ratioControl.selectedSegment = Self.segment(for: lockedRatio, currentRatio: currentRatio)
        ratioControl.setAccessibilityLabel(L10n.text("overlay.aspectRatio"))

        let help = NSTextField(wrappingLabelWithString: L10n.text("overlay.aspectHelp"))
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        help.maximumNumberOfLines = 2
        let root = NSStackView(views: [dimensions, ratioLabel, ratioControl, help])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 2, right: 0)
        controlsView = root
        super.init()

        widthField.delegate = self
        heightField.delegate = self
        ratioControl.target = self
        ratioControl.action = #selector(ratioChanged)
    }

    func makePanel(relativeTo parent: NSWindow? = nil) -> NSPanel {
        let panelSize = CGSize(width: 620, height: 390)
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.text("overlay.editSelectionSize")
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let content = NSView(frame: CGRect(origin: .zero, size: panelSize))
        let title = NSTextField(labelWithString: L10n.text("overlay.editSelectionSize"))
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: L10n.text("overlay.editSelectionSizeHelp"))
        explanation.font = .systemFont(ofSize: 13)
        explanation.textColor = .secondaryLabelColor
        explanation.maximumNumberOfLines = 2
        let error = NSTextField(wrappingLabelWithString: "")
        error.font = .systemFont(ofSize: 12, weight: .medium)
        error.textColor = .systemRed
        error.isHidden = true
        errorLabel = error

        let cancelButton = NSButton(
            title: L10n.text("common.cancel"),
            target: self,
            action: #selector(cancelPanel)
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let applyButton = NSButton(
            title: L10n.text("common.apply"),
            target: self,
            action: #selector(applyPanel)
        )
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [cancelButton, applyButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        [title, explanation, controlsView, error, buttonRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }
        panel.contentView = content
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            title.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -28),

            explanation.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            explanation.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            explanation.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            controlsView.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 18),
            controlsView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            controlsView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            ratioControl.widthAnchor.constraint(equalTo: controlsView.widthAnchor),

            error.topAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: 10),
            error.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            error.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            buttonRow.topAnchor.constraint(greaterThanOrEqualTo: error.bottomAnchor, constant: 14)
        ])

        if let parent {
            let origin = CGPoint(
                x: parent.frame.midX - panelSize.width / 2,
                y: parent.frame.midY - panelSize.height / 2
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }
        return panel
    }

    func makePopoverContent(
        onApply: @escaping (CGSize, CGFloat?) -> Void,
        onCancel: @escaping () -> Void
    ) -> NSView {
        applyHandler = onApply
        cancelHandler = onCancel
        let size = CGSize(width: 440, height: 292)
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        let title = NSTextField(labelWithString: L10n.text("overlay.editSelectionSize"))
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        let error = NSTextField(wrappingLabelWithString: "")
        error.font = .systemFont(ofSize: 11, weight: .medium)
        error.textColor = .systemRed
        error.isHidden = true
        errorLabel = error

        let cancelButton = NSButton(
            title: L10n.text("common.cancel"),
            target: self,
            action: #selector(cancelPanel)
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let applyButton = NSButton(
            title: L10n.text("common.apply"),
            target: self,
            action: #selector(applyPanel)
        )
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [cancelButton, applyButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        [title, controlsView, error, buttonRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),

            controlsView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            controlsView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            controlsView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            ratioControl.widthAnchor.constraint(equalTo: controlsView.widthAnchor),

            error.topAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: 6),
            error.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            error.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            buttonRow.topAnchor.constraint(greaterThanOrEqualTo: error.bottomAnchor, constant: 8)
        ])
        return content
    }

    func runModal(
        relativeTo parent: NSWindow?,
        onPresented: (() -> Void)? = nil
    ) -> (size: CGSize, aspectRatio: CGFloat?)? {
        modalResult = nil
        let panel = makePanel(relativeTo: parent)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(widthField)
        widthField.selectText(nil)
        NSApp.activate(ignoringOtherApps: true)
        onPresented?()
        _ = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return modalResult
    }

    var selectedAspectRatio: CGFloat? {
        guard let preset = SelectionAspectRatioPreset(rawValue: ratioControl.selectedSegment) else { return nil }
        return preset.ratio(currentRatio: currentRatio)
    }

    func resultSize() -> CGSize? {
        guard let width = Double(widthField.stringValue), width > 0,
              let height = Double(heightField.stringValue), height > 0 else { return nil }
        return SelectionSizeGeometry.constrainedSize(
            width: width,
            height: height,
            aspectRatio: selectedAspectRatio,
            editedDimension: editedDimension,
            maximumSize: maximumSize
        )
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isSynchronizing else { return }
        guard let field = notification.object as? NSTextField else { return }
        if field === widthField {
            editedDimension = .width
        } else if field === heightField {
            editedDimension = .height
        }
        synchronizeLinkedDimension(updatesEditedField: false)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        if NSApp.modalWindow === closingWindow {
            NSApp.stopModal(withCode: .cancel)
        }
    }

    @objc private func ratioChanged() {
        editedDimension = .width
        synchronizeLinkedDimension(updatesEditedField: true)
    }

    @objc func applyPanel() {
        guard let size = resultSize() else {
            errorLabel?.stringValue = L10n.text("overlay.invalidSelectionSize")
            errorLabel?.isHidden = false
            NSSound.beep()
            return
        }
        if let applyHandler {
            applyHandler(size, selectedAspectRatio)
        } else {
            modalResult = (size, selectedAspectRatio)
            NSApp.stopModal(withCode: .OK)
        }
    }

    @objc func cancelPanel() {
        if let cancelHandler {
            cancelHandler()
        } else {
            NSApp.stopModal(withCode: .cancel)
        }
    }

    private func synchronizeLinkedDimension(updatesEditedField: Bool) {
        guard let ratio = selectedAspectRatio,
              let width = Double(widthField.stringValue), width > 0,
              let height = Double(heightField.stringValue), height > 0 else { return }
        isSynchronizing = true
        switch editedDimension {
        case .width:
            if updatesEditedField {
                let size = SelectionSizeGeometry.constrainedSize(
                    width: width,
                    height: height,
                    aspectRatio: ratio,
                    editedDimension: .width,
                    maximumSize: maximumSize
                )
                widthField.stringValue = String(Int(size.width.rounded()))
                heightField.stringValue = String(Int(size.height.rounded()))
            } else {
                heightField.stringValue = String(Int((width / ratio).rounded()))
            }
        case .height:
            if updatesEditedField {
                let size = SelectionSizeGeometry.constrainedSize(
                    width: width,
                    height: height,
                    aspectRatio: ratio,
                    editedDimension: .height,
                    maximumSize: maximumSize
                )
                widthField.stringValue = String(Int(size.width.rounded()))
                heightField.stringValue = String(Int(size.height.rounded()))
            } else {
                widthField.stringValue = String(Int((height * ratio).rounded()))
            }
        }
        isSynchronizing = false
    }

    private static func segment(for lockedRatio: CGFloat?, currentRatio: CGFloat) -> Int {
        guard let lockedRatio else { return SelectionAspectRatioPreset.free.rawValue }
        for preset in SelectionAspectRatioPreset.allCases where preset != .free && preset != .current {
            if let ratio = preset.ratio(currentRatio: currentRatio), abs(ratio - lockedRatio) < 0.0001 {
                return preset.rawValue
            }
        }
        return SelectionAspectRatioPreset.current.rawValue
    }
}

final class SelectionOverlayView: NSView {
    weak var delegate: SelectionOverlayViewDelegate?
    // 与最终裁图共用同一次冻结画面，既保持视觉一致，也隔离下层应用交互。
    var previewImage: NSImage?
    var previewSourceImage: CGImage?
    var showsToolbar = true
    var defaultDisposition: SelectionDisposition = .copy
    var hintText: String?
    var safetyWarningText: String? {
        didSet { needsDisplay = true }
    }
    var annotations: [AnnotationStroke] { annotationCanvas?.strokes ?? [] }

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    // 保留选区内的首次单击，避免双击的第一下把已有选区重置成新框选。
    private var pendingSelectionClick: CGPoint?
    private var toolbar: NSVisualEffectView!
    private var toolbarStack: NSStackView!
    private var toolbarDragHandle: OverlayToolbarDragHandleView!
    private var toolbarActionViews: [SelectionToolbarAction: NSView] = [:]
    private var annotationToolbarViews: [NSView] = []
    private var annotationSeparator: OverlayToolbarSeparator!
    private var exitSeparator: OverlayToolbarSeparator!
    private var toolbarActionOrder: [SelectionToolbarAction] = []
    private var colorPreview: ColorPickerPreviewView!
    private var colorPickerButton: OverlayToolbarButton!
    private var annotationToolButtons: [OverlayToolbarButton] = []
    private weak var annotationUndoButton: NSButton?
    private weak var annotationRedoButton: NSButton?
    private weak var annotationClearButton: NSButton?
    private weak var annotationColorWell: NSColorWell?
    private weak var annotationWidthControl: OverlayWidthControl?
    private weak var colorFormatPopup: NSPopUpButton?
    private weak var selectionSizeButton: OverlayToolbarButton?
    private var selectionSizePopover: NSPopover?
    private var selectionSizeEditor: SelectionSizeEditorCoordinator?
    private var lockedAspectRatio: CGFloat?
    private var isSelectionAspectLocked: Bool { lockedAspectRatio != nil }
    var annotationStyleDefaults: UserDefaults = .standard {
        didSet {
            selectedAnnotationWidth = AnnotationStyleSettings.brushPixelWidth(
                for: selectedAnnotationTool,
                defaults: annotationStyleDefaults
            )
            annotationWidthControl?.value = selectedAnnotationWidth
            annotationCanvas?.brushPixelWidth = selectedAnnotationWidth
        }
    }
    var colorPickerDefaults: UserDefaults = .standard {
        didSet {
            selectedColorSampleFormat = ColorSampleFormat.current(defaults: colorPickerDefaults)
            colorFormatPopup?.selectItem(withTag: selectedColorSampleFormat.menuTag)
            updateColorPickerControls()
        }
    }
    var toolbarConfigurationDefaults: UserDefaults = .standard {
        didSet { reloadToolbarConfiguration() }
    }
    var colorPasteboard: NSPasteboard = .general
    private var selectedAnnotationColor: NSColor = .systemRed
    private var selectedAnnotationTool: AnnotationTool = .mosaic
    private var selectedAnnotationWidth: CGFloat = AnnotationStyleSettings.defaultBrushPixelWidth(for: .mosaic)
    private var selectedColorSampleFormat: ColorSampleFormat = .hex
    private var hoveredColorSample: (point: CGPoint, color: NSColor)?
    private var isColorPickerFrozen = false
    private var isAwaitingAction = false
    private var isAnnotationMode = false
    private var isColorPickerMode = false
    private var isScrollingCaptureOutline = false
    private var annotationCanvas: AnnotationCanvasView?
    private var annotationPreviewImage: NSImage?
    private var doubleClickTracker = SelectionDoubleClickTracker()
    private var focusLayer: CAShapeLayer?
    private var didManuallyPositionToolbar = false
    // 缩放和整体移动都以按下时的矩形为基准，避免贴边后逐帧累加产生位置漂移。
    private var activeResizeHandle: SelectionResizeHandle?
    private var resizeStartRect: CGRect?
    private var resizeStartPoint: CGPoint?
    private var moveStartRect: CGRect?
    private var moveStartPoint: CGPoint?
    private var isSuppressingToolbarGesture = false

    var isPresentingScrollingCaptureOutline: Bool { isScrollingCaptureOutline }

    private static let diagonalNorthWestSouthEastCursor = diagonalCursor(
        symbolName: "arrow.up.left.and.arrow.down.right"
    )
    private static let diagonalNorthEastSouthWestCursor = diagonalCursor(
        symbolName: "arrow.up.right.and.arrow.down.left"
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        selectedAnnotationWidth = AnnotationStyleSettings.brushPixelWidth(
            for: selectedAnnotationTool,
            defaults: annotationStyleDefaults
        )
        selectedColorSampleFormat = ColorSampleFormat.current(defaults: colorPickerDefaults)
        configureToolbar()
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        selectedAnnotationWidth = AnnotationStyleSettings.brushPixelWidth(
            for: selectedAnnotationTool,
            defaults: annotationStyleDefaults
        )
        selectedColorSampleFormat = ColorSampleFormat.current(defaults: colorPickerDefaults)
        configureToolbar()
        configureAccessibility()
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if !toolbar.isHidden, toolbar.frame.contains(point) {
            return super.hitTest(point)
        }
        if !colorPreview.isHidden, colorPreview.frame.contains(point) {
            return super.hitTest(point)
        }
        if isAnnotationMode,
           let annotationCanvas,
           !annotationCanvas.isHidden,
           annotationCanvas.frame.contains(point) {
            return super.hitTest(point)
        }
        return self
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
        guard !isColorPickerMode else { return }
        guard isAwaitingAction, !isAnnotationMode, isSelectionValid else { return }

        let interior = selectionRect.insetBy(
            dx: SelectionResizeGeometry.hitSlop,
            dy: SelectionResizeGeometry.hitSlop
        ).intersection(bounds)
        if !interior.isNull, !interior.isEmpty {
            addCursorRect(interior, cursor: .openHand)
        }
        for handle in SelectionResizeHandle.allCases {
            let rect = SelectionResizeGeometry.cursorRect(for: handle, in: selectionRect).intersection(bounds)
            if !rect.isNull, !rect.isEmpty {
                addCursorRect(rect, cursor: resizeCursor(for: handle))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isPointInToolbarInteractionArea(point) {
            isSuppressingToolbarGesture = true
            return
        }
        if isPointInColorPreview(point) {
            isSuppressingToolbarGesture = true
            return
        }
        guard !isAnnotationMode else { return }
        if isColorPickerMode {
            handleColorPickerClick(at: point, clickCount: event.clickCount)
            return
        }
        if isSelectionValid {
            if let handle = SelectionResizeGeometry.handle(at: point, in: selectionRect) {
                activeResizeHandle = handle
                resizeStartRect = selectionRect
                resizeStartPoint = point
                moveStartRect = nil
                moveStartPoint = nil
                pendingSelectionClick = nil
                isAwaitingAction = false
                setColorPickerMode(false)
                doubleClickTracker.reset()
                toolbar.isHidden = true
                colorPreview.isHidden = true
                annotationCanvas?.isHidden = true
                resizeCursor(for: handle).set()
                invalidateSelectionCursorRects()
                needsDisplay = true
                return
            }
            if selectionRect.contains(point) {
                // 第二次按下即确认，确保截图区域内的双击直接进入复制完成链路。
                if event.clickCount >= 2 ||
                    doubleClickTracker.registerClick(timestamp: event.timestamp, point: point) {
                    pendingSelectionClick = nil
                    moveStartRect = nil
                    moveStartPoint = nil
                    doubleClickTracker.reset()
                    complete(with: .copy)
                    return
                }
                pendingSelectionClick = point
                moveStartRect = selectionRect
                moveStartPoint = point
                NSCursor.closedHand.set()
                return
            }
        }

        pendingSelectionClick = nil
        moveStartRect = nil
        moveStartPoint = nil
        startPoint = point
        currentPoint = point
        isAwaitingAction = false
        setColorPickerMode(false)
        doubleClickTracker.reset()
        toolbar.isHidden = true
        colorPreview.isHidden = true
        invalidateSelectionCursorRects()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard isColorPickerMode else {
            super.mouseMoved(with: event)
            return
        }
        guard !isColorPickerFrozen else { return }
        updateColorPreview(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        if isSuppressingToolbarGesture { return }
        guard !isAnnotationMode else { return }
        let point = convert(event.locationInWindow, from: nil)
        if isColorPickerMode {
            if !isColorPickerFrozen { updateColorPreview(at: point) }
            return
        }
        if let activeResizeHandle, let resizeStartRect, let resizeStartPoint {
            let resized = SelectionResizeGeometry.resizedRect(
                resizeStartRect,
                using: activeResizeHandle,
                translation: CGPoint(x: point.x - resizeStartPoint.x, y: point.y - resizeStartPoint.y),
                constrainedTo: bounds,
                aspectRatio: lockedAspectRatio
            )
            startPoint = resized.origin
            currentPoint = CGPoint(x: resized.maxX, y: resized.maxY)
            resizeCursor(for: activeResizeHandle).set()
            invalidateSelectionCursorRects()
            needsDisplay = true
            return
        }
        if let moveStartRect, let moveStartPoint {
            if pendingSelectionClick != nil {
                pendingSelectionClick = nil
                toolbar.isHidden = true
                colorPreview.isHidden = true
                annotationCanvas?.isHidden = true
                isAwaitingAction = false
                doubleClickTracker.reset()
            }
            let moved = SelectionResizeGeometry.movedRect(
                moveStartRect,
                translation: CGPoint(x: point.x - moveStartPoint.x, y: point.y - moveStartPoint.y),
                constrainedTo: bounds
            )
            startPoint = moved.origin
            currentPoint = CGPoint(x: moved.maxX, y: moved.maxY)
            toolbar.isHidden = true
            colorPreview.isHidden = true
            NSCursor.closedHand.set()
            invalidateSelectionCursorRects()
            needsDisplay = true
            return
        }
        if let startPoint, let lockedAspectRatio {
            currentPoint = SelectionSizeGeometry.aspectLockedEndpoint(
                from: startPoint,
                to: point,
                aspectRatio: lockedAspectRatio,
                constrainedTo: bounds
            )
        } else {
            currentPoint = point
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isSuppressingToolbarGesture {
            isSuppressingToolbarGesture = false
            return
        }
        guard !isAnnotationMode else { return }
        if isColorPickerMode { return }
        if activeResizeHandle != nil {
            activeResizeHandle = nil
            resizeStartRect = nil
            resizeStartPoint = nil
            refreshAnnotationCanvasForSelection()
            presentActionsOrComplete()
            return
        }
        if moveStartRect != nil {
            let didMove = pendingSelectionClick == nil
            pendingSelectionClick = nil
            moveStartRect = nil
            moveStartPoint = nil
            if didMove {
                refreshAnnotationCanvasForSelection()
                presentActionsOrComplete()
            } else {
                NSCursor.openHand.set()
                invalidateSelectionCursorRects()
            }
            return
        }
        currentPoint = convert(event.locationInWindow, from: nil)
        guard isSelectionValid else {
            startPoint = nil
            currentPoint = nil
            toolbar.isHidden = true
            colorPreview.isHidden = true
            needsDisplay = true
            return
        }

        refreshAnnotationCanvasForSelection()
        presentActionsOrComplete()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            delegate?.selectionView(self, completed: nil, disposition: .copy)
        } else if event.keyCode == UInt16(kVK_Return), isSelectionValid {
            complete(with: .copy)
        } else if event.charactersIgnoringModifiers?.lowercased() == "p", isSelectionValid {
            complete(with: .pin)
        } else if handleSelectionArrowKey(event) {
            return
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if isColorPickerMode {
            copyColorAndExit(at: convert(event.locationInWindow, from: nil))
            return
        }
        // 右键只由覆盖层消费，退出截图统一保留给 Esc，且不能把事件传到底层桌面。
    }

    override func draw(_ dirtyRect: NSRect) {
        if isScrollingCaptureOutline {
            dirtyRect.fill(using: .clear)
            drawScrollingCaptureOutline()
            return
        }

        if let previewImage {
            previewImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        } else {
            NSColor.black.setFill()
            bounds.fill()
        }

        let dimAlpha = isAwaitingAction
            ? OverlaySafetyPolicy.awaitingActionDimAlpha
            : OverlaySafetyPolicy.selectingDimAlpha
        let dimColor = isColorPickerMode ? NSColor.gray : NSColor.black
        dimColor.withAlphaComponent(dimAlpha).setFill()
        bounds.fill()

        let rect = selectionRect
        if isColorPickerMode {
            drawSafetyWarning()
            return
        }
        guard !rect.isEmpty else {
            drawHint()
            drawSafetyWarning()
            return
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        if let previewImage {
            previewImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        if !isAnnotationMode,
           moveStartRect == nil,
           activeResizeHandle == nil,
           !annotations.isEmpty,
           let annotationPreviewImage {
            annotationPreviewImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        }

        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1.5
        path.stroke()
        if isAwaitingAction, !isAnnotationMode { drawResizeHandles(for: rect) }
        drawSizeLabel(for: rect)
        drawSafetyWarning()
    }

    private var selectionRect: CGRect {
        guard let startPoint, let currentPoint else { return .zero }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private var isSelectionValid: Bool {
        selectionRect.width >= 3 && selectionRect.height >= 3
    }

    private func configureToolbar() {
        let effect = OverlayToolbarView(frame: CGRect(x: 0, y: 0, width: 680, height: 48))
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 13
        effect.layer?.cornerCurve = .continuous
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        effect.layer?.shadowColor = NSColor.black.cgColor
        effect.layer?.shadowOpacity = 0.32
        effect.layer?.shadowRadius = 12
        effect.layer?.shadowOffset = CGSize(width: 0, height: -4)
        effect.isHidden = true

        let dragHandle = OverlayToolbarDragHandleView(frame: .zero)
        dragHandle.onDrag = { [weak self] translation in
            self?.moveToolbar(by: translation)
        }

        let toolButtons = AnnotationTool.selectionTools.enumerated().map { index, tool in
            let button = toolbarButton(
                symbolName: tool.symbolName,
                accessibilityLabel: L10n.text(tool.titleKey),
                title: nil,
                width: 27,
                accentColor: OverlayToolbarIconPalette.color(for: tool),
                action: #selector(annotationToolChanged(_:))
            )
            button.tag = index
            return button
        }
        annotationToolButtons = toolButtons

        let colorWell = AnchoredColorWell(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(annotationColorChanged(_:))
        colorWell.toolTip = L10n.text("annotation.color")
        colorWell.setAccessibilityLabel(L10n.text("annotation.color"))
        colorWell.widthAnchor.constraint(equalToConstant: 24).isActive = true
        annotationColorWell = colorWell

        let widthControl = OverlayWidthControl(frame: .zero)
        widthControl.value = selectedAnnotationWidth
        widthControl.target = self
        widthControl.action = #selector(annotationWidthChanged(_:))
        annotationWidthControl = widthControl

        let undoButton = toolbarButton(
            symbolName: "arrow.uturn.backward",
            accessibilityLabel: L10n.text("annotation.undo"),
            accentColor: OverlayToolbarIconPalette.history,
            action: #selector(undoAnnotation)
        )
        let redoButton = toolbarButton(
            symbolName: "arrow.uturn.forward",
            accessibilityLabel: L10n.text("annotation.redo"),
            accentColor: OverlayToolbarIconPalette.history,
            action: #selector(redoAnnotation)
        )
        let clearButton = toolbarButton(
            symbolName: "trash",
            accessibilityLabel: L10n.text("annotation.clear"),
            accentColor: OverlayToolbarIconPalette.destructive,
            isDestructive: true,
            action: #selector(clearAnnotations)
        )
        undoButton.isEnabled = false
        redoButton.isEnabled = false
        clearButton.isEnabled = false
        annotationUndoButton = undoButton
        annotationRedoButton = redoButton
        annotationClearButton = clearButton

        let annotationControls = toolButtons.prefix(2).map { $0 as NSView }
            + [colorWell, widthControl]
            + toolButtons.dropFirst(2).map { $0 as NSView }
            + [undoButton, redoButton, clearButton]

        let copyButton = toolbarButton(
            symbolName: SelectionToolbarAction.copy.symbolName(),
            accessibilityLabel: L10n.text("common.copy"),
            toolTip: L10n.text("overlay.copyTooltip"),
            accentColor: OverlayToolbarIconPalette.copy,
            action: #selector(copySelection)
        )
        copyButton.isPrimaryActionStyle = true
        let scrollingCaptureButton = toolbarButton(
            symbolName: SelectionToolbarAction.scrollingCapture.symbolName(),
            accessibilityLabel: L10n.text("action.scrollingRegion"),
            accentColor: OverlayToolbarIconPalette.scrollingCapture,
            action: #selector(captureScrollingSelection)
        )
        let colorPickerButton = toolbarButton(
            symbolName: SelectionToolbarAction.pickColor.symbolName(),
            accessibilityLabel: L10n.text("overlay.pickColor"),
            accentColor: OverlayToolbarIconPalette.colorPicker,
            action: #selector(toggleColorPickerMode)
        )
        self.colorPickerButton = colorPickerButton
        let colorFormatPopup = makeColorFormatPopup()
        self.colorFormatPopup = colorFormatPopup
        let sizeButton = toolbarButton(
            symbolName: SelectionToolbarAction.selectionSize.symbolName(),
            accessibilityLabel: L10n.text("overlay.editSelectionSize"),
            width: 28,
            accentColor: OverlayToolbarIconPalette.selectionSize,
            action: #selector(showSelectionSizeEditor)
        )
        selectionSizeButton = sizeButton
        let pinButton = toolbarButton(
            symbolName: SelectionToolbarAction.pin.symbolName(),
            accessibilityLabel: L10n.text("overlay.pin"),
            toolTip: L10n.text("overlay.pinTooltip"),
            accentColor: OverlayToolbarIconPalette.pin,
            action: #selector(pinSelection)
        )
        let cancelButton = toolbarButton(
            symbolName: SelectionToolbarAction.cancel.symbolName(),
            accessibilityLabel: L10n.text("common.cancel"),
            toolTip: L10n.text("overlay.cancelTooltip"),
            accentColor: OverlayToolbarIconPalette.destructive,
            isDestructive: true,
            action: #selector(cancelSelection)
        )
        let outputSeparator = OverlayToolbarSeparator(frame: .zero)
        let exitSeparator = OverlayToolbarSeparator(frame: .zero)
        let stack = NSStackView(views: [dragHandle])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .equalSpacing
        stack.spacing = 3
        stack.frame = effect.bounds.insetBy(dx: 6, dy: 8)
        stack.autoresizingMask = [.width, .height]
        effect.addSubview(stack)
        addSubview(effect)
        toolbar = effect
        toolbarStack = stack
        toolbarDragHandle = dragHandle
        toolbarActionViews = [
            .scrollingCapture: scrollingCaptureButton,
            .pickColor: colorPickerButton,
            .selectionSize: sizeButton,
            .copy: copyButton,
            .pin: pinButton,
            .cancel: cancelButton
        ]
        annotationToolbarViews = annotationControls
        annotationSeparator = outputSeparator
        self.exitSeparator = exitSeparator
        reloadToolbarConfiguration()
        configureColorPreview()
        updateColorPickerControls()
    }

    private func reloadToolbarConfiguration() {
        toolbarActionOrder = SelectionToolbarConfiguration.orderedVisibleActions(
            defaults: toolbarConfigurationDefaults
        )
        applyToolbarConfiguration()
    }

    private func applyToolbarConfiguration() {
        guard toolbarStack != nil, toolbarDragHandle != nil else { return }
        let configuredActions = Set(toolbarActionOrder)
        let hiddenActions = SelectionToolbarAction.configurableActions.filter { !configuredActions.contains($0) }
        let separatorViews: [NSView] = [annotationSeparator, exitSeparator].compactMap { $0 }
        let accessoryViews: [NSView] = [colorFormatPopup].compactMap { $0 }
        let managedViews = Array(toolbarActionViews.values)
            + annotationToolbarViews
            + separatorViews
            + accessoryViews
        managedViews.forEach { $0.isHidden = true }
        toolbarDragHandle.isHidden = false

        var views: [NSView] = [toolbarDragHandle]
        var appended = Set<ObjectIdentifier>([ObjectIdentifier(toolbarDragHandle)])
        func append(_ view: NSView, visible: Bool) {
            guard appended.insert(ObjectIdentifier(view)).inserted else { return }
            view.isHidden = !visible
            views.append(view)
        }

        for (index, action) in toolbarActionOrder.enumerated() {
            if action == .annotate {
                annotationToolbarViews.forEach { view in
                    let isDirectTool = annotationToolButtons.contains { $0 === view }
                    append(view, visible: isDirectTool || isAnnotationMode)
                }
                if toolbarActionOrder.dropFirst(index + 1).contains(where: { $0 != .annotate }) {
                    append(annotationSeparator, visible: true)
                }
                continue
            }
            guard let view = toolbarActionViews[action] else { continue }
            if action == .cancel, views.count > 1, !(views.last is OverlayToolbarSeparator) {
                append(exitSeparator, visible: true)
            }
            append(view, visible: true)
            if action == .pickColor, isColorPickerMode, let colorFormatPopup {
                append(colorFormatPopup, visible: true)
            }
        }

        hiddenActions.compactMap { toolbarActionViews[$0] }.forEach { append($0, visible: false) }
        if let colorFormatPopup { append(colorFormatPopup, visible: false) }
        annotationToolbarViews.forEach { append($0, visible: false) }
        append(annotationSeparator, visible: false)
        append(exitSeparator, visible: exitSeparator.isHidden == false)

        toolbarStack.setViews(views, in: .leading)
        updateToolbarLayout()
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L10n.text("overlay.accessibility.selectionCanvas"))
    }

    private func configureColorPreview() {
        let preview = ColorPickerPreviewView(frame: CGRect(x: 0, y: 0, width: 236, height: 68))
        preview.isHidden = true
        preview.formatPopup.target = self
        preview.formatPopup.action = #selector(colorFormatChanged(_:))
        addSubview(preview)
        colorPreview = preview
    }

    private func makeColorFormatPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11.5, weight: .semibold)
        popup.target = self
        popup.action = #selector(colorFormatChanged(_:))
        popup.toolTip = L10n.text("colorPicker.format")
        popup.setAccessibilityLabel(L10n.text("colorPicker.format"))
        popup.widthAnchor.constraint(equalToConstant: 70).isActive = true
        popup.heightAnchor.constraint(equalToConstant: 32).isActive = true
        for format in ColorSampleFormat.allCases {
            popup.addItem(withTitle: L10n.text(format.titleKey))
            popup.lastItem?.tag = format.menuTag
        }
        popup.selectItem(withTag: selectedColorSampleFormat.menuTag)
        return popup
    }

    private func toolbarButton(
        symbolName: String,
        accessibilityLabel: String,
        toolTip: String? = nil,
        title: String? = nil,
        width: CGFloat = 30,
        accentColor: NSColor,
        isDestructive: Bool = false,
        action: Selector
    ) -> OverlayToolbarButton {
        let button = OverlayToolbarButton(frame: .zero)
        button.target = self
        button.action = action
        button.title = title ?? ""
        button.setSymbol(symbolName, accessibilityLabel: accessibilityLabel)
        button.imagePosition = title == nil ? .imageOnly : .imageLeading
        button.font = .systemFont(ofSize: 11.5, weight: .semibold)
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.toolTip = toolTip ?? accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.layer?.cornerCurve = .continuous
        button.layer?.borderWidth = 0.75
        button.focusRingType = .default
        button.isDestructiveStyle = isDestructive
        button.accentColor = accentColor
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func positionToolbar(around rect: CGRect) {
        if didManuallyPositionToolbar {
            clampToolbarIntoBounds()
            return
        }
        let screenMargin: CGFloat = 12
        let selectionSpacing: CGFloat = 10
        let x = min(
            max(rect.midX - toolbar.frame.width / 2, screenMargin),
            bounds.maxX - toolbar.frame.width - screenMargin
        )
        let below = rect.minY - toolbar.frame.height - selectionSpacing
        let above = rect.maxY + selectionSpacing
        let y: CGFloat
        if below >= screenMargin {
            y = below
        } else if above + toolbar.frame.height <= bounds.maxY - screenMargin {
            y = above
        } else {
            y = screenMargin
        }
        toolbar.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func moveToolbar(by translation: CGPoint) {
        guard !toolbar.isHidden else { return }
        toolbar.setFrameOrigin(CGPoint(
            x: toolbar.frame.minX + translation.x,
            y: toolbar.frame.minY + translation.y
        ))
        didManuallyPositionToolbar = true
        clampToolbarIntoBounds()
    }

    private func clampToolbarIntoBounds() {
        let margin: CGFloat = 8
        let x = min(
            max(toolbar.frame.minX, bounds.minX + margin),
            max(bounds.minX + margin, bounds.maxX - toolbar.frame.width - margin)
        )
        let y = min(
            max(toolbar.frame.minY, bounds.minY + margin),
            max(bounds.minY + margin, bounds.maxY - toolbar.frame.height - margin)
        )
        toolbar.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func isPointInToolbarInteractionArea(_ point: CGPoint) -> Bool {
        !toolbar.isHidden && toolbar.frame.insetBy(dx: -6, dy: -6).contains(point)
    }

    private func isPointInColorPreview(_ point: CGPoint) -> Bool {
        !colorPreview.isHidden && colorPreview.frame.insetBy(dx: -6, dy: -6).contains(point)
    }

    private func presentActionsOrComplete() {
        if showsToolbar {
            isAwaitingAction = true
            setColorPickerMode(false)
            delegate?.selectionViewDidPrepareActions(self)
            annotationCanvas?.isHidden = !isAnnotationMode
            updateToolbarLayout()
            syncSelectionDimensionFields()
            positionToolbar(around: selectionRect)
            toolbar.isHidden = false
            invalidateSelectionCursorRects()
            needsDisplay = true
        } else {
            complete(with: defaultDisposition)
        }
    }

    @objc private func showSelectionSizeEditor() {
        guard isSelectionValid else { return }
        if selectionSizePopover?.isShown == true {
            closeSelectionSizePopover()
            return
        }
        recordToolbarUsage(.selectionSize)

        let currentRatio = selectionRect.width / max(selectionRect.height, 1)
        let editor = SelectionSizeEditorCoordinator(
            size: selectionRect.size,
            currentRatio: currentRatio,
            lockedRatio: lockedAspectRatio,
            maximumSize: bounds.size
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = CGSize(width: 440, height: 292)

        let contentController = NSViewController()
        contentController.view = editor.makePopoverContent(
            onApply: { [weak self] size, aspectRatio in
                guard let self else { return }
                lockedAspectRatio = aspectRatio
                applyKeyboardSelection(
                    SelectionSizeGeometry.centeredRect(size: size, around: selectionRect, constrainedTo: bounds)
                )
                closeSelectionSizePopover()
            },
            onCancel: { [weak self] in
                self?.closeSelectionSizePopover()
            }
        )
        popover.contentViewController = contentController
        selectionSizeEditor = editor
        selectionSizePopover = popover

        guard let selectionSizeButton else {
            closeSelectionSizePopover()
            return
        }
        popover.show(relativeTo: selectionSizeButton.bounds, of: selectionSizeButton, preferredEdge: .maxY)
        editor.widthField.window?.makeFirstResponder(editor.widthField)
        editor.widthField.selectText(nil)
    }

    private func closeSelectionSizePopover() {
        selectionSizePopover?.close()
        selectionSizePopover = nil
        selectionSizeEditor = nil
    }

    private func syncSelectionDimensionFields() {
        guard isSelectionValid else { return }
        let value = L10n.text(
            "overlay.accessibility.selectionValue",
            Int(selectionRect.width.rounded()),
            Int(selectionRect.height.rounded())
        )
        let ratioStatus = lockedAspectRatio.map { String(format: "%.2f:1", $0) }
        selectionSizeButton?.toolTip = [value, ratioStatus].compactMap { $0 }.joined(separator: " · ")
        selectionSizeButton?.setAccessibilityValue(value)
        selectionSizeButton?.isSelectedStyle = isSelectionAspectLocked
        setAccessibilityValue(
            value
        )
    }

    private func handleSelectionArrowKey(_ event: NSEvent) -> Bool {
        let direction: CGPoint
        switch Int(event.keyCode) {
        case kVK_LeftArrow: direction = CGPoint(x: -1, y: 0)
        case kVK_RightArrow: direction = CGPoint(x: 1, y: 0)
        case kVK_DownArrow: direction = CGPoint(x: 0, y: -1)
        case kVK_UpArrow: direction = CGPoint(x: 0, y: 1)
        default: return false
        }

        if !isSelectionValid {
            let size = CGSize(width: min(320, bounds.width), height: min(180, bounds.height))
            applyKeyboardSelection(CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            ))
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let step: CGFloat = flags.contains(.shift) ? 10 : 1
        var rect = selectionRect
        if flags.contains(.option) {
            rect.size.width = max(3, rect.width + direction.x * step)
            rect.size.height = max(3, rect.height + direction.y * step)
            if let lockedAspectRatio {
                if direction.x != 0 { rect.size.height = rect.width / lockedAspectRatio }
                if direction.y != 0 { rect.size.width = rect.height * lockedAspectRatio }
            }
        } else {
            rect = rect.offsetBy(dx: direction.x * step, dy: direction.y * step)
        }
        applyKeyboardSelection(rect)
        return true
    }

    private func applyKeyboardSelection(_ proposed: CGRect) {
        let size = SelectionSizeGeometry.constrainedSize(
            width: proposed.width,
            height: proposed.height,
            aspectRatio: lockedAspectRatio,
            editedDimension: .width,
            maximumSize: bounds.size
        )
        let width = size.width
        let height = size.height
        let origin = CGPoint(
            x: min(max(proposed.minX, bounds.minX), bounds.maxX - width),
            y: min(max(proposed.minY, bounds.minY), bounds.maxY - height)
        )
        let rect = CGRect(origin: origin, size: CGSize(width: width, height: height)).integral
        startPoint = rect.origin
        currentPoint = CGPoint(x: rect.maxX, y: rect.maxY)
        refreshAnnotationCanvasForSelection()
        presentActionsOrComplete()
        needsDisplay = true
    }

    private func updateToolbarLayout() {
        let visibleViews = toolbarStack.arrangedSubviews.filter { !$0.isHidden }
        let contentWidth = visibleViews.reduce(CGFloat.zero) { partial, view in
            partial + view.fittingSize.width
        }
        let spacingWidth = CGFloat(max(visibleViews.count - 1, 0)) * toolbarStack.spacing
        let preferredWidth = ceil(contentWidth + spacingWidth + 16)
        let availableWidth = max(bounds.width - 24, 0)
        toolbar.setFrameSize(CGSize(width: min(preferredWidth, availableWidth), height: 48))
        toolbarStack.frame = toolbar.bounds.insetBy(dx: 6, dy: 8)
        toolbarStack.layoutSubtreeIfNeeded()
        toolbar.layoutSubtreeIfNeeded()
    }

    private func invalidateSelectionCursorRects() {
        window?.invalidateCursorRects(for: self)
    }

    private func resizeCursor(for handle: SelectionResizeHandle) -> NSCursor {
        if #available(macOS 15.0, *) {
            switch handle {
            case .topLeft: return .frameResize(position: .topLeft, directions: .all)
            case .top: return .frameResize(position: .top, directions: .all)
            case .topRight: return .frameResize(position: .topRight, directions: .all)
            case .right: return .frameResize(position: .right, directions: .all)
            case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
            case .bottom: return .frameResize(position: .bottom, directions: .all)
            case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
            case .left: return .frameResize(position: .left, directions: .all)
            }
        }
        switch handle {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return Self.diagonalNorthWestSouthEastCursor
        case .topRight, .bottomLeft:
            return Self.diagonalNorthEastSouthWestCursor
        }
    }

    private static func diagonalCursor(symbolName: String) -> NSCursor {
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium)) else {
            return .crosshair
        }
        return NSCursor(
            image: image,
            hotSpot: CGPoint(x: image.size.width / 2, y: image.size.height / 2)
        )
    }

    private func drawResizeHandles(for rect: CGRect) {
        let diameter: CGFloat = 9
        for point in SelectionResizeGeometry.controlPoints(in: rect) {
            let handle = NSBezierPath(ovalIn: CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            ))
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            handle.lineWidth = 1.5
            handle.stroke()
        }
    }

    private func complete(with disposition: SelectionDisposition) {
        guard isSelectionValid else { return }
        closeSelectionSizePopover()
        annotationCanvas?.commitPendingText()
        delegate?.selectionView(self, completed: selectionRect, disposition: disposition)
    }

    func presentScrollingCaptureOutline() {
        closeSelectionSizePopover()
        isScrollingCaptureOutline = true
        isAwaitingAction = false
        isAnnotationMode = false
        setColorPickerMode(false)
        toolbar.isHidden = true
        colorPreview.isHidden = true
        annotationCanvas?.isHidden = true
        safetyWarningText = nil
        needsDisplay = true
    }

    private func drawScrollingCaptureOutline() {
        let rect = selectionRect
        guard !rect.isEmpty else { return }
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        path.stroke()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let innerPath = NSBezierPath(rect: rect.insetBy(dx: 3, dy: 3))
        innerPath.lineWidth = 1
        innerPath.stroke()
    }

    @objc private func copySelection() {
        recordToolbarUsage(.copy)
        complete(with: .copy)
    }

    @objc private func captureScrollingSelection() {
        recordToolbarUsage(.scrollingCapture)
        complete(with: .scrollingCapture)
    }

    @objc private func toggleColorPickerMode() {
        if !isColorPickerMode { recordToolbarUsage(.pickColor) }
        setColorPickerMode(!isColorPickerMode)
    }

    @objc private func colorFormatChanged(_ sender: NSPopUpButton) {
        guard let format = ColorSampleFormat.format(for: sender.selectedTag()) else { return }
        selectedColorSampleFormat = format
        ColorSampleFormat.set(format, defaults: colorPickerDefaults)
        setColorPickerMode(true)
        updateColorPickerControls()
    }

    @objc private func pinSelection() {
        recordToolbarUsage(.pin)
        complete(with: .pin)
    }

    private func recordToolbarUsage(_ action: SelectionToolbarAction) {
        SelectionToolbarConfiguration.recordUsage(of: action, defaults: toolbarConfigurationDefaults)
    }

    private func setColorPickerMode(_ enabled: Bool) {
        guard isColorPickerMode != enabled else {
            updateColorPickerControls()
            return
        }
        isColorPickerMode = enabled
        if enabled, isAnnotationMode {
            setAnnotationMode(false)
        }
        colorPreview.isHidden = !enabled
        if enabled {
            isColorPickerFrozen = false
            let point = window.map { convert($0.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil) }
                ?? CGPoint(x: selectionRect.midX, y: selectionRect.midY)
            updateColorPreview(at: point)
        } else {
            hoveredColorSample = nil
            isColorPickerFrozen = false
        }
        updateColorPickerControls()
        applyToolbarConfiguration()
        if isSelectionValid { positionToolbar(around: selectionRect) }
        invalidateSelectionCursorRects()
        needsDisplay = true
    }

    private func updateColorPickerControls() {
        let formatTitle = L10n.text(selectedColorSampleFormat.titleKey)
        colorPickerButton?.isSelectedStyle = isColorPickerMode
        colorPickerButton?.toolTip = L10n.text("overlay.pickColorTooltip", formatTitle)
        colorPickerButton?.setAccessibilityLabel(L10n.text("overlay.pickColor"))
        colorFormatPopup?.toolTip = L10n.text("colorPicker.format")
        colorFormatPopup?.selectItem(withTag: selectedColorSampleFormat.menuTag)
        colorPreview?.formatPopup.selectItem(withTag: selectedColorSampleFormat.menuTag)
        if let sample = hoveredColorSample {
            colorPreview.update(
                color: sample.color,
                value: selectedColorSampleFormat.string(for: sample.color),
                format: selectedColorSampleFormat
            )
        }
    }

    private func handleColorPickerClick(at point: CGPoint, clickCount: Int) {
        if clickCount >= 2 {
            copyColorAndExit(at: point)
            return
        }
        if isColorPickerFrozen {
            isColorPickerFrozen = false
            updateColorPreview(at: point)
        } else {
            updateColorPreview(at: point)
            isColorPickerFrozen = hoveredColorSample != nil
        }
    }

    private func copyColorAndExit(at point: CGPoint) {
        guard let color = colorForCommit(at: point) else { return }
        let string = selectedColorSampleFormat.string(for: color)
        guard ColorClipboard(pasteboard: colorPasteboard).write(string) else { return }
        delegate?.selectionView(self, completed: nil, disposition: .copy)
    }

    private func colorForCommit(at point: CGPoint) -> NSColor? {
        if isColorPickerFrozen, let sample = hoveredColorSample {
            return sample.color
        }
        return sampledColor(at: point)
    }

    private func updateColorPreview(at point: CGPoint) {
        guard isColorPickerMode,
              let color = sampledColor(at: point) else {
            colorPreview.isHidden = true
            return
        }
        hoveredColorSample = (point, color)
        colorPreview.isHidden = false
        colorPreview.update(
            color: color,
            value: selectedColorSampleFormat.string(for: color),
            format: selectedColorSampleFormat
        )
        positionColorPreview(near: point)
    }

    private func sampledColor(at point: CGPoint) -> NSColor? {
        guard let previewSourceImage else { return nil }
        return ScreenColorSampler.color(in: previewSourceImage, bounds: bounds, at: point)
    }

    private func positionColorPreview(near point: CGPoint) {
        let offset = CGPoint(x: 18, y: -18 - colorPreview.frame.height)
        var origin = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
        if origin.x + colorPreview.frame.width > bounds.maxX - 10 {
            origin.x = point.x - colorPreview.frame.width - 18
        }
        if origin.y < bounds.minY + 10 {
            origin.y = point.y + 18
        }
        origin.x = min(max(origin.x, bounds.minX + 10), bounds.maxX - colorPreview.frame.width - 10)
        origin.y = min(max(origin.y, bounds.minY + 10), bounds.maxY - colorPreview.frame.height - 10)
        colorPreview.setFrameOrigin(origin)
    }

    private func setAnnotationMode(_ enabled: Bool) {
        guard isSelectionValid else { return }
        if enabled { setColorPickerMode(false) }
        if enabled, annotationCanvas == nil {
            configureAnnotationCanvas()
        }
        guard annotationCanvas != nil else { return }
        isAnnotationMode = enabled
        // 用户只选择具体工具；这个内部状态仅用于在绘制和调整选区之间分配鼠标事件。
        for (index, button) in annotationToolButtons.enumerated() {
            let isActiveTool = isAnnotationMode && AnnotationTool.selectionTools[index] == selectedAnnotationTool
            button.isSelectedStyle = isActiveTool
            button.state = isActiveTool ? .on : .off
        }
        annotationCanvas?.isHidden = !isAnnotationMode
        if isAnnotationMode {
            window?.makeFirstResponder(annotationCanvas)
        } else {
            window?.makeFirstResponder(self)
        }
        applyToolbarConfiguration()
        positionToolbar(around: selectionRect)
        needsDisplay = true
    }

    @objc private func annotationToolChanged(_ sender: OverlayToolbarButton) {
        guard AnnotationTool.selectionTools.indices.contains(sender.tag) else { return }
        let selectedTool = AnnotationTool.selectionTools[sender.tag]
        if isAnnotationMode, selectedTool == selectedAnnotationTool {
            setAnnotationMode(false)
            return
        }
        if !isAnnotationMode { recordToolbarUsage(.annotate) }
        if selectedTool != selectedAnnotationTool {
            selectedAnnotationWidth = AnnotationStyleSettings.brushPixelWidth(
                for: selectedTool,
                defaults: annotationStyleDefaults
            )
        }
        selectedAnnotationTool = selectedTool
        annotationWidthControl?.value = selectedAnnotationWidth
        setAnnotationMode(true)
        guard isAnnotationMode else { return }
        annotationCanvas?.tool = selectedTool
        annotationCanvas?.brushPixelWidth = selectedAnnotationWidth
    }

    @objc private func annotationColorChanged(_ sender: NSColorWell) {
        selectedAnnotationColor = sender.color
        annotationCanvas?.annotationColor = sender.color
    }

    @objc private func annotationWidthChanged(_ sender: OverlayWidthControl) {
        selectedAnnotationWidth = sender.value
        AnnotationStyleSettings.setBrushPixelWidth(
            selectedAnnotationWidth,
            for: selectedAnnotationTool,
            defaults: annotationStyleDefaults
        )
        annotationCanvas?.brushPixelWidth = selectedAnnotationWidth
    }

    @objc private func undoAnnotation() { annotationCanvas?.undo() }
    @objc private func redoAnnotation() { annotationCanvas?.redo() }
    @objc private func clearAnnotations() { annotationCanvas?.clear() }
    @objc private func cancelSelection() {
        closeSelectionSizePopover()
        delegate?.selectionView(self, completed: nil, disposition: .copy)
    }

    private func configureAnnotationCanvas() {
        guard let cropped = croppedPreviewSource(for: selectionRect) else { return }
        let canvas = AnnotationCanvasView(
            sourceImage: cropped,
            logicalSize: selectionRect.size,
            contentInset: 0
        )
        canvas.frame = selectionRect
        canvas.layer?.cornerRadius = 0
        canvas.layer?.borderWidth = 1.5
        canvas.layer?.borderColor = NSColor.controlAccentColor.cgColor
        canvas.tool = selectedAnnotationTool
        canvas.annotationColor = selectedAnnotationColor
        canvas.brushPixelWidth = selectedAnnotationWidth
        canvas.onHistoryChanged = { [weak self, weak canvas] canUndo, canRedo in
            // 非标注态由父视图绘制缓存结果，避免画布子视图遮住边缘控制点。
            self?.annotationUndoButton?.isEnabled = canUndo
            self?.annotationRedoButton?.isEnabled = canRedo
            self?.annotationClearButton?.isEnabled = canUndo || canRedo
            self?.annotationPreviewImage = canvas?.currentRenderedImage
            self?.needsDisplay = true
        }
        canvas.onDoubleClick = { [weak self] in
            self?.complete(with: .copy)
        }
        canvas.onSelectedTextStyleChanged = { [weak self] color, width in
            self?.selectedAnnotationColor = color
            self?.selectedAnnotationWidth = width
            self?.annotationColorWell?.color = color
            self?.annotationWidthControl?.value = width
        }
        addSubview(canvas, positioned: .below, relativeTo: toolbar)
        annotationCanvas = canvas
        annotationPreviewImage = canvas.currentRenderedImage
    }

    private func refreshAnnotationCanvasForSelection() {
        guard let annotationCanvas,
              let cropped = croppedPreviewSource(for: selectionRect) else { return }
        annotationCanvas.frame = selectionRect
        annotationCanvas.updateSourceImage(cropped, logicalSize: selectionRect.size)
        annotationCanvas.isHidden = !isAnnotationMode
        annotationPreviewImage = annotationCanvas.currentRenderedImage
    }

    private func croppedPreviewSource(for rect: CGRect) -> CGImage? {
        guard let previewSourceImage, bounds.width > 0, bounds.height > 0 else { return nil }
        let scaleX = CGFloat(previewSourceImage.width) / bounds.width
        let scaleY = CGFloat(previewSourceImage.height) / bounds.height
        let crop = CGRect(
            x: rect.minX * scaleX,
            y: (bounds.maxY - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral.intersection(CGRect(
            x: 0,
            y: 0,
            width: previewSourceImage.width,
            height: previewSourceImage.height
        ))
        guard !crop.isNull, crop.width > 0, crop.height > 0 else { return nil }
        return previewSourceImage.cropping(to: crop)
    }

    private func drawHint() {
        let text = (hintText ?? L10n.text("overlay.hint")) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY), withAttributes: attributes)
    }

    private func drawSafetyWarning() {
        guard let safetyWarningText else { return }
        let text = safetyWarningText as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 7
        let pillRect = CGRect(
            x: bounds.midX - textSize.width / 2 - horizontalPadding,
            y: bounds.maxY - textSize.height - verticalPadding * 2 - 20,
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + verticalPadding * 2
        )
        NSColor.black.withAlphaComponent(0.84).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 10, yRadius: 10).fill()
        NSColor.systemOrange.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        border.lineWidth = 1
        border.stroke()
        text.draw(
            at: CGPoint(x: pillRect.minX + horizontalPadding, y: pillRect.minY + verticalPadding),
            withAttributes: attributes
        )
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.72)
        ]
        let size = text.size(withAttributes: attributes)
        let x = min(max(rect.minX, 8), bounds.maxX - size.width - 12)
        let y = max(rect.minY - size.height - 8, 8)
        text.draw(at: CGPoint(x: x + 4, y: y + 2), withAttributes: attributes)
    }

    func playEntranceAnimation(at point: CGPoint) {
        guard OverlaySafetyPolicy.shouldAnimate(),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        wantsLayer = true
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlaySafetyPolicy.entranceAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        focusLayer?.removeFromSuperlayer()
        let focus = CAShapeLayer()
        focus.frame = bounds
        focus.fillColor = NSColor.clear.cgColor
        focus.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        focus.lineWidth = 2
        focus.path = CGPath(ellipseIn: CGRect(x: point.x - 18, y: point.y - 18, width: 36, height: 36), transform: nil)
        layer?.addSublayer(focus)
        focusLayer = focus
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.35
        scale.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = OverlaySafetyPolicy.entranceAnimationDuration * 1.8
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        focus.add(group, forKey: "entrance")
        DispatchQueue.main.asyncAfter(deadline: .now() + group.duration) { [weak self, weak focus] in
            focus?.removeFromSuperlayer()
            if self?.focusLayer === focus { self?.focusLayer = nil }
        }
    }
}
