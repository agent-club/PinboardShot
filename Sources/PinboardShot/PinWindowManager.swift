import AppKit
import Carbon.HIToolbox
import ImageIO
import UniformTypeIdentifiers

enum PinImageSaveFormat: CaseIterable {
    case png
    case jpeg
    case tiff
    case heic
    case gif
    case bmp

    static let defaultFormat: PinImageSaveFormat = .png

    static var allowedContentTypes: [UTType] {
        allCases.map(\.contentType)
    }

    static func format(for url: URL) -> PinImageSaveFormat {
        let pathExtension = url.pathExtension.lowercased()
        return allCases.first { $0.pathExtensions.contains(pathExtension) } ?? defaultFormat
    }

    var pathExtension: String { pathExtensions[0] }

    var pathExtensions: [String] {
        switch self {
        case .png: ["png"]
        case .jpeg: ["jpg", "jpeg"]
        case .tiff: ["tiff", "tif"]
        case .heic: ["heic", "heif"]
        case .gif: ["gif"]
        case .bmp: ["bmp"]
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .tiff: .tiff
        case .heic: .heic
        case .gif: .gif
        case .bmp: .bmp
        }
    }

    func encodedData(for image: NSImage) -> Data? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            contentType.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let options = encodingOptions.map { $0 as CFDictionary }
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private var encodingOptions: [CFString: Any]? {
        switch self {
        case .jpeg, .heic:
            [kCGImageDestinationLossyCompressionQuality: 0.92]
        default:
            nil
        }
    }
}

struct PinWindowDragGeometry {
    static func origin(
        initialWindowOrigin: CGPoint,
        initialMouseLocation: CGPoint,
        currentMouseLocation: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: initialWindowOrigin.x + currentMouseLocation.x - initialMouseLocation.x,
            y: initialWindowOrigin.y + currentMouseLocation.y - initialMouseLocation.y
        )
    }
}

struct PinWindowCascade {
    static func offset(for index: Int) -> CGFloat {
        CGFloat(index % 8) * 24
    }
}

enum PinComparisonDiscoveryPolicy {
    static let shownDefaultsKey = "pinComparisonDiscoveryHintShown-v1"

    static func shouldShow(pinCount: Int, defaults: UserDefaults = .standard) -> Bool {
        pinCount == 2 && !defaults.bool(forKey: shownDefaultsKey)
    }

    static func markShown(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: shownDefaultsKey)
    }
}

struct PinWindowVisibleGeometry {
    static func constrainedFrame(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard frame.width > 0, frame.height > 0, !visibleFrames.isEmpty else { return frame }

        let target = visibleFrames.max { lhs, rhs in
            let lhsArea = intersectionArea(frame, lhs)
            let rhsArea = intersectionArea(frame, rhs)
            if lhsArea != rhsArea { return lhsArea < rhsArea }
            return centerDistanceSquared(frame, lhs) > centerDistanceSquared(frame, rhs)
        } ?? visibleFrames[0]

        let scale = min(target.width / frame.width, target.height / frame.height, 1)
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        return CGRect(
            x: min(max(frame.minX, target.minX), target.maxX - size.width),
            y: min(max(frame.minY, target.minY), target.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private static func centerDistanceSquared(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let dx = lhs.midX - rhs.midX
        let dy = lhs.midY - rhs.midY
        return dx * dx + dy * dy
    }
}

struct PinWindowScaleGeometry {
    static func scaledFrame(
        _ frame: CGRect,
        by requestedFactor: CGFloat,
        around anchor: CGPoint,
        minimumSize: CGSize
    ) -> CGRect {
        guard frame.width > 0, frame.height > 0, requestedFactor.isFinite, requestedFactor > 0 else {
            return frame
        }

        let minimumFactor = max(minimumSize.width / frame.width, minimumSize.height / frame.height)
        let factor = max(requestedFactor, minimumFactor)
        let anchorX = (anchor.x - frame.minX) / frame.width
        let anchorY = (anchor.y - frame.minY) / frame.height
        let size = CGSize(width: frame.width * factor, height: frame.height * factor)

        return CGRect(
            x: anchor.x - size.width * anchorX,
            y: anchor.y - size.height * anchorY,
            width: size.width,
            height: size.height
        )
    }
}

enum PinWindowResizeHandle: CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

struct PinWindowResizeGeometry {
    static let hitSlop: CGFloat = 12

    static func handle(at point: CGPoint, in bounds: CGRect) -> PinWindowResizeHandle? {
        guard bounds.contains(point) else { return nil }
        let nearLeft = point.x - bounds.minX <= hitSlop
        let nearRight = bounds.maxX - point.x <= hitSlop
        let nearBottom = point.y - bounds.minY <= hitSlop
        let nearTop = bounds.maxY - point.y <= hitSlop

        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearRight && nearBottom { return .bottomRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearTop { return .top }
        if nearRight { return .right }
        if nearBottom { return .bottom }
        if nearLeft { return .left }
        return nil
    }

    static func resizedFrame(
        _ frame: CGRect,
        using handle: PinWindowResizeHandle,
        from initialMouseLocation: CGPoint,
        to mouseLocation: CGPoint,
        minimumSize: CGSize
    ) -> CGRect {
        let anchor = anchor(for: handle, in: frame)
        let translation = CGPoint(
            x: mouseLocation.x - initialMouseLocation.x,
            y: mouseLocation.y - initialMouseLocation.y
        )
        let horizontalFactor: CGFloat
        let verticalFactor: CGFloat

        switch handle {
        case .topLeft, .left, .bottomLeft:
            horizontalFactor = 1 - translation.x / frame.width
        default:
            horizontalFactor = 1 + translation.x / frame.width
        }
        switch handle {
        case .bottomLeft, .bottom, .bottomRight:
            verticalFactor = 1 - translation.y / frame.height
        default:
            verticalFactor = 1 + translation.y / frame.height
        }

        let requestedFactor: CGFloat
        switch handle {
        case .left, .right:
            requestedFactor = horizontalFactor
        case .top, .bottom:
            requestedFactor = verticalFactor
        default:
            requestedFactor = abs(horizontalFactor - 1) >= abs(verticalFactor - 1)
                ? horizontalFactor
                : verticalFactor
        }

        return PinWindowScaleGeometry.scaledFrame(
            frame,
            by: max(requestedFactor, .leastNonzeroMagnitude),
            around: anchor,
            minimumSize: minimumSize
        )
    }

    static func cursorRect(for handle: PinWindowResizeHandle, in bounds: CGRect) -> CGRect {
        switch handle {
        case .topLeft:
            return CGRect(x: bounds.minX, y: bounds.maxY - hitSlop, width: hitSlop, height: hitSlop)
        case .top:
            return CGRect(x: bounds.minX + hitSlop, y: bounds.maxY - hitSlop, width: max(0, bounds.width - hitSlop * 2), height: hitSlop)
        case .topRight:
            return CGRect(x: bounds.maxX - hitSlop, y: bounds.maxY - hitSlop, width: hitSlop, height: hitSlop)
        case .right:
            return CGRect(x: bounds.maxX - hitSlop, y: bounds.minY + hitSlop, width: hitSlop, height: max(0, bounds.height - hitSlop * 2))
        case .bottomRight:
            return CGRect(x: bounds.maxX - hitSlop, y: bounds.minY, width: hitSlop, height: hitSlop)
        case .bottom:
            return CGRect(x: bounds.minX + hitSlop, y: bounds.minY, width: max(0, bounds.width - hitSlop * 2), height: hitSlop)
        case .bottomLeft:
            return CGRect(x: bounds.minX, y: bounds.minY, width: hitSlop, height: hitSlop)
        case .left:
            return CGRect(x: bounds.minX, y: bounds.minY + hitSlop, width: hitSlop, height: max(0, bounds.height - hitSlop * 2))
        }
    }

    private static func anchor(for handle: PinWindowResizeHandle, in frame: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: frame.maxX, y: frame.minY)
        case .top: return CGPoint(x: frame.midX, y: frame.minY)
        case .topRight: return CGPoint(x: frame.minX, y: frame.minY)
        case .right: return CGPoint(x: frame.minX, y: frame.midY)
        case .bottomRight: return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY)
        case .bottomLeft: return CGPoint(x: frame.maxX, y: frame.maxY)
        case .left: return CGPoint(x: frame.maxX, y: frame.midY)
        }
    }
}

struct PinWindowResizeChromeGeometry {
    static let revealDistance: CGFloat = 24

    static func isNearEdge(_ point: CGPoint, in bounds: CGRect) -> Bool {
        guard bounds.contains(point) else { return false }
        return min(
            point.x - bounds.minX,
            bounds.maxX - point.x,
            point.y - bounds.minY,
            bounds.maxY - point.y
        ) <= revealDistance
    }

    static func handleRect(for handle: PinWindowResizeHandle, in bounds: CGRect) -> CGRect {
        let cornerSize = CGSize(width: 8, height: 8)
        let horizontalSize = CGSize(width: 14, height: 5)
        let verticalSize = CGSize(width: 5, height: 14)
        let inset: CGFloat = 2

        switch handle {
        case .topLeft:
            return CGRect(
                x: bounds.minX + inset,
                y: bounds.maxY - inset - cornerSize.height,
                width: cornerSize.width,
                height: cornerSize.height
            )
        case .top:
            return CGRect(
                x: bounds.midX - horizontalSize.width / 2,
                y: bounds.maxY - inset - horizontalSize.height,
                width: horizontalSize.width,
                height: horizontalSize.height
            )
        case .topRight:
            return CGRect(
                x: bounds.maxX - inset - cornerSize.width,
                y: bounds.maxY - inset - cornerSize.height,
                width: cornerSize.width,
                height: cornerSize.height
            )
        case .right:
            return CGRect(
                x: bounds.maxX - inset - verticalSize.width,
                y: bounds.midY - verticalSize.height / 2,
                width: verticalSize.width,
                height: verticalSize.height
            )
        case .bottomRight:
            return CGRect(
                x: bounds.maxX - inset - cornerSize.width,
                y: bounds.minY + inset,
                width: cornerSize.width,
                height: cornerSize.height
            )
        case .bottom:
            return CGRect(
                x: bounds.midX - horizontalSize.width / 2,
                y: bounds.minY + inset,
                width: horizontalSize.width,
                height: horizontalSize.height
            )
        case .bottomLeft:
            return CGRect(
                x: bounds.minX + inset,
                y: bounds.minY + inset,
                width: cornerSize.width,
                height: cornerSize.height
            )
        case .left:
            return CGRect(
                x: bounds.minX + inset,
                y: bounds.midY - verticalSize.height / 2,
                width: verticalSize.width,
                height: verticalSize.height
            )
        }
    }
}

@MainActor
final class PinPanel: NSPanel {
    var onCloseShortcut: (() -> Void)?
    var onCopyShortcut: (() -> Void)?
    var onSaveShortcut: (() -> Void)?
    var onScaleShortcut: ((CGFloat) -> Void)?
    var onRestoreShortcut: (() -> Void)?
    var onNudge: ((CGPoint) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown, flags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch Int(event.keyCode) {
        case kVK_ANSI_W: onCloseShortcut?()
        case kVK_ANSI_C: onCopyShortcut?()
        case kVK_ANSI_S: onSaveShortcut?()
        case kVK_ANSI_Equal: onScaleShortcut?(1.1)
        case kVK_ANSI_Minus: onScaleShortcut?(1 / 1.1)
        case kVK_ANSI_0: onRestoreShortcut?()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch Int(event.keyCode) {
        case kVK_LeftArrow: onNudge?(CGPoint(x: -step, y: 0)); return
        case kVK_RightArrow: onNudge?(CGPoint(x: step, y: 0)); return
        case kVK_DownArrow: onNudge?(CGPoint(x: 0, y: -step)); return
        case kVK_UpArrow: onNudge?(CGPoint(x: 0, y: step)); return
        default: break
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class PinWindowManager: NSObject {
    static let shadowDefaultsKey = "pinWindowShadow"
    // NSWindowController 必须被强引用；字典同时承担多贴图生命周期和逐张关闭索引。
    private var controllers: [UUID: PinWindowController] = [:]
    private(set) var pinsAreVisible = true
    private var cascadeIndex = 0
    private var trackpadMagnificationMonitor: PinTrackpadMagnificationMonitor?
    private var comparisonReferenceID: UUID?
    private var comparisonWindowController: PinComparisonWindowController?
    private let comparisonDiscoveryTipController = PinComparisonDiscoveryTipController()

    var onRequestSaveWorkspace: (() -> Void)?
    var onRequestEditMetadata: ((UUID, PinMetadata) -> Void)?
    var onSessionChanged: (() -> Void)?

    var count: Int { controllers.count }
    var shadowsEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.shadowDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.shadowDefaultsKey)
    }

    func pin(image: NSImage, near point: CGPoint? = nil) {
        let controller = makeController(image: image)
        if !pinsAreVisible {
            controllers.values.forEach { $0.showWithoutActivating() }
        }
        controllers[controller.id] = controller
        startTrackpadMagnificationMonitoringIfNeeded()
        let anchor = point ?? NSEvent.mouseLocation
        let cascadeOffset = PinWindowCascade.offset(for: cascadeIndex)
        controller.show(near: CGPoint(x: anchor.x + cascadeOffset, y: anchor.y - cascadeOffset))
        cascadeIndex += 1
        pinsAreVisible = true
        showComparisonDiscoveryTipIfNeeded(near: controller.window?.frame)
        onSessionChanged?()
    }

    func workspaceCaptures() -> [PinWorkspaceCapture] {
        orderedControllersBackToFront().map(\.workspaceCapture)
    }

    func sessionCaptures() -> [PinSessionCapture] {
        orderedControllersBackToFront().map(\.sessionCapture)
    }

    func updateMetadata(for id: UUID, metadata: PinMetadata) {
        guard let controller = controllers[id] else { return }
        controller.updateMetadata(metadata)
        onSessionChanged?()
    }

    private func orderedControllersBackToFront() -> [PinWindowController] {
        let controllersByWindowNumber = Dictionary(
            uniqueKeysWithValues: controllers.values.compactMap { controller in
                controller.window.map { ($0.windowNumber, controller) }
            }
        )
        let frontToBack = (NSWindow.windowNumbers(options: []) ?? []).compactMap {
            controllersByWindowNumber[$0.intValue]
        }
        let orderedIDs = Set(frontToBack.map(\.id))
        let remaining = controllers.values.filter { !orderedIDs.contains($0.id) }
        // Restoring orders each window front, so persist back-to-front to preserve the visible stack.
        var backToFront = Array(frontToBack.reversed())
        backToFront.append(contentsOf: remaining)
        return backToFront
    }

    @discardableResult
    func restoreWorkspace(_ entries: [PinWorkspaceRestoreEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        var clearedApplicationBindings = 0
        for entry in entries {
            let controller = makeController(image: entry.image, metadata: entry.metadata)
            controllers[controller.id] = controller
            if controller.show(restoring: entry.state) {
                clearedApplicationBindings += 1
            }
        }
        startTrackpadMagnificationMonitoringIfNeeded()
        pinsAreVisible = true
        onSessionChanged?()
        return clearedApplicationBindings
    }

    func toggleAll() {
        pinsAreVisible.toggle()
        controllers.values.forEach { controller in
            pinsAreVisible ? controller.showWithoutActivating() : controller.hide()
        }
        onSessionChanged?()
    }

    func closeAll() {
        let active = Array(controllers.values)
        controllers.removeAll()
        trackpadMagnificationMonitor = nil
        cascadeIndex = 0
        comparisonReferenceID = nil
        comparisonDiscoveryTipController.dismiss()
        active.forEach { $0.close() }
        onSessionChanged?()
    }

    func restoreInteraction() {
        controllers.values.forEach { $0.restoreInteraction() }
    }

    func setShadowsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.shadowDefaultsKey)
        controllers.values.forEach { $0.setShadow(enabled) }
    }

    private func scaleTopmostPin(at anchor: CGPoint, by factor: CGFloat) {
        let controllersByWindowNumber = Dictionary(
            uniqueKeysWithValues: controllers.values.compactMap { controller in
                controller.window.map { ($0.windowNumber, controller) }
            }
        )
        let orderedWindowNumbers = NSWindow.windowNumbers(options: []) ?? []
        guard let controller = orderedWindowNumbers.lazy
            .compactMap({ controllersByWindowNumber[$0.intValue] })
            .first(where: { controller in
                guard let window = controller.window else { return false }
                return window.isVisible && !window.ignoresMouseEvents && window.frame.contains(anchor)
            }) else { return }
        controller.scale(by: factor, around: anchor)
    }

    private func startTrackpadMagnificationMonitoringIfNeeded() {
        guard trackpadMagnificationMonitor == nil else { return }
        trackpadMagnificationMonitor = PinTrackpadMagnificationMonitor { [weak self] magnification in
            self?.scaleTopmostPin(
                at: NSEvent.mouseLocation,
                by: max(0.1, 1 + magnification)
            )
        }
    }

    private func stopTrackpadMagnificationMonitoringIfUnused() {
        guard controllers.isEmpty else { return }
        trackpadMagnificationMonitor = nil
    }

    private func makeController(image: NSImage, metadata: PinMetadata = .empty) -> PinWindowController {
        let id = UUID()
        return PinWindowController(
            id: id,
            image: image,
            metadata: metadata,
            hasShadow: shadowsEnabled,
            onSaveWorkspace: { [weak self] in self?.onRequestSaveWorkspace?() },
            onEditMetadata: { [weak self] id, metadata in
                self?.onRequestEditMetadata?(id, metadata)
            },
            comparisonState: { [weak self] id in
                self?.comparisonMenuState(for: id) ?? .unavailable
            },
            onComparisonAction: { [weak self] id, mode in
                self?.handleComparisonAction(for: id, mode: mode)
            },
            onStateChanged: { [weak self] in self?.onSessionChanged?() }
        ) { [weak self] id in
            guard let self else { return }
            self.controllers.removeValue(forKey: id)
            if self.comparisonReferenceID == id {
                self.comparisonReferenceID = nil
                self.updateComparisonReferenceIndicators()
            }
            self.stopTrackpadMagnificationMonitoringIfUnused()
            self.onSessionChanged?()
        }
    }

    private func comparisonMenuState(for id: UUID) -> PinComparisonMenuState {
        guard controllers.count >= 2 else { return .unavailable }
        guard let comparisonReferenceID else { return .canSetReference }
        return comparisonReferenceID == id ? .isReference : .canCompare
    }

    private func handleComparisonAction(for id: UUID, mode: PinComparisonMode?) {
        guard controllers[id] != nil else { return }
        comparisonDiscoveryTipController.dismiss()
        if comparisonReferenceID == id {
            comparisonReferenceID = nil
            updateComparisonReferenceIndicators()
            return
        }
        guard let referenceID = comparisonReferenceID,
              let mode,
              let first = controllers[referenceID]?.comparisonSource,
              let second = controllers[id]?.comparisonSource else {
            comparisonReferenceID = id
            updateComparisonReferenceIndicators()
            return
        }
        if comparisonWindowController == nil {
            comparisonWindowController = PinComparisonWindowController()
        }
        comparisonWindowController?.show(first: first, second: second, initialMode: mode)
        comparisonReferenceID = nil
        updateComparisonReferenceIndicators()
    }

    private func showComparisonDiscoveryTipIfNeeded(near pinFrame: CGRect?) {
        guard PinComparisonDiscoveryPolicy.shouldShow(pinCount: controllers.count),
              let pinFrame else { return }
        PinComparisonDiscoveryPolicy.markShown()
        comparisonDiscoveryTipController.show(
            near: CGPoint(x: pinFrame.midX, y: pinFrame.minY),
            message: L10n.text("pin.compare.discoveryHint")
        )
    }

    private func updateComparisonReferenceIndicators() {
        controllers.values.forEach { controller in
            controller.setComparisonReference(controller.id == comparisonReferenceID)
        }
    }

}

enum PinComparisonMenuState {
    case unavailable
    case canSetReference
    case isReference
    case canCompare
}

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {
    let id: UUID
    private let image: NSImage
    private var metadata: PinMetadata
    private let onSaveWorkspace: () -> Void
    private let onEditMetadata: (UUID, PinMetadata) -> Void
    private let comparisonState: (UUID) -> PinComparisonMenuState
    private let onComparisonAction: (UUID, PinComparisonMode?) -> Void
    private let onStateChanged: () -> Void
    private let onClose: (UUID) -> Void
    private var initialState: PinWorkspaceWindowState?
    private var baseOpacity: CGFloat = 1
    private var isPointerHovering = false
    private(set) var isPositionLocked = false
    private(set) var isAutoFadeOnHoverEnabled = false
    private(set) var isComparisonReference = false
    private var visibilityBundleIdentifier: String?
    private var workspaceObserver: NSObjectProtocol?

    init(
        id: UUID,
        image: NSImage,
        metadata: PinMetadata = .empty,
        hasShadow: Bool,
        onSaveWorkspace: @escaping () -> Void = {},
        onEditMetadata: @escaping (UUID, PinMetadata) -> Void = { _, _ in },
        comparisonState: @escaping (UUID) -> PinComparisonMenuState = { _ in .unavailable },
        onComparisonAction: @escaping (UUID, PinComparisonMode?) -> Void = { _, _ in },
        onStateChanged: @escaping () -> Void = {},
        onClose: @escaping (UUID) -> Void
    ) {
        self.id = id
        self.image = image
        self.metadata = metadata
        self.onSaveWorkspace = onSaveWorkspace
        self.onEditMetadata = onEditMetadata
        self.comparisonState = comparisonState
        self.onComparisonAction = onComparisonAction
        self.onStateChanged = onStateChanged
        self.onClose = onClose

        let size = Self.initialSize(for: image.size)
        let panel = PinPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = hasShadow
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 80, height: 60)
        panel.contentAspectRatio = image.size

        super.init(window: panel)
        panel.onCloseShortcut = { [weak self] in self?.close() }
        panel.onCopyShortcut = { [weak self] in self?.copyImage() }
        panel.onSaveShortcut = { [weak self] in self?.saveImage() }
        panel.onScaleShortcut = { [weak self] factor in self?.scale(by: factor) }
        panel.onRestoreShortcut = { [weak self] in self?.restoreInitialState() }
        panel.onNudge = { [weak self] offset in self?.nudge(by: offset) }
        panel.delegate = self
        panel.contentView = PinImageView(image: image, controller: self)
    }

    required init?(coder: NSCoder) { nil }

    func show(near point: CGPoint) {
        guard let window else { return }
        let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = CGPoint(x: point.x + 16, y: point.y - window.frame.height - 16)
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - window.frame.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - window.frame.height)
        window.setFrameOrigin(origin)
        if initialState == nil {
            initialState = currentState
        }
        showWithoutActivating()
    }

    @discardableResult
    func show(restoring state: PinWorkspaceWindowState) -> Bool {
        let clearedApplicationBinding = apply(state)
        initialState = currentState
        showWithoutActivating()
        return clearedApplicationBinding
    }

    func showWithoutActivating() {
        guard shouldBeVisibleForFrontmostApplication else { return }
        window?.orderFrontRegardless()
    }
    func hide() { window?.orderOut(nil) }

    func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func saveImage() {
        do {
            _ = try ImageFileExporter.save(
                image,
                suggestedName: "PinboardShot-\(Self.timestamp()).\(PinImageSaveFormat.defaultFormat.pathExtension)"
            )
        } catch {
            presentSaveError(error)
        }
    }

    func scale(by factor: CGFloat, around anchor: CGPoint? = nil) {
        guard let window else { return }
        let frame = PinWindowScaleGeometry.scaledFrame(
            window.frame,
            by: factor,
            around: anchor ?? CGPoint(x: window.frame.midX, y: window.frame.midY),
            minimumSize: window.minSize
        )
        window.setFrame(frame, display: true)
        onStateChanged()
    }

    func nudge(by offset: CGPoint) {
        guard !isPositionLocked, let window else { return }
        window.setFrameOrigin(CGPoint(x: window.frame.minX + offset.x, y: window.frame.minY + offset.y))
        onStateChanged()
    }

    func adjustOpacity(by delta: CGFloat) {
        baseOpacity = min(max(baseOpacity + delta, 0.15), 1)
        applyVisibleOpacity()
        onStateChanged()
    }

    func togglePositionLock() {
        isPositionLocked.toggle()
        window?.isMovableByWindowBackground = !isPositionLocked
        window?.invalidateCursorRects(for: window?.contentView ?? NSView())
        onStateChanged()
    }

    func toggleAllSpaces() {
        guard let window else { return }
        if window.collectionBehavior.contains(.canJoinAllSpaces) {
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.collectionBehavior.insert(.moveToActiveSpace)
        } else {
            window.collectionBehavior.remove(.moveToActiveSpace)
            window.collectionBehavior.insert(.canJoinAllSpaces)
        }
        onStateChanged()
    }

    var appearsOnAllSpaces: Bool { window?.collectionBehavior.contains(.canJoinAllSpaces) == true }

    func toggleCurrentApplicationVisibility() {
        if visibilityBundleIdentifier != nil {
            setVisibilityBundleIdentifier(nil)
            showWithoutActivating()
            onStateChanged()
            return
        }
        setVisibilityBundleIdentifier(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        updateApplicationVisibility()
        onStateChanged()
    }

    var isLimitedToCurrentApplication: Bool { visibilityBundleIdentifier != nil }

    func toggleAutoFadeOnHover() {
        isAutoFadeOnHoverEnabled.toggle()
        applyVisibleOpacity()
        onStateChanged()
    }

    func updateHover(_ isHovering: Bool) {
        isPointerHovering = isHovering
        applyVisibleOpacity()
    }

    func restoreInitialState() {
        guard let initialState else { return }
        _ = apply(initialState)
        onStateChanged()
    }

    func toggleMousePassthrough() {
        guard let window else { return }
        window.ignoresMouseEvents.toggle()
        onStateChanged()
    }

    var ignoresMouseEvents: Bool { window?.ignoresMouseEvents ?? false }

    var workspaceCapture: PinWorkspaceCapture {
        PinWorkspaceCapture(image: image, state: currentState, metadata: metadata)
    }

    var sessionCapture: PinSessionCapture {
        PinSessionCapture(id: id, image: image, state: currentState, metadata: metadata)
    }

    var comparisonSource: NSImage { image }
    var comparisonMenuState: PinComparisonMenuState { comparisonState(id) }

    func requestMetadataEdit() { onEditMetadata(id, metadata) }
    func requestComparison(mode: PinComparisonMode?) { onComparisonAction(id, mode) }

    func updateMetadata(_ metadata: PinMetadata) {
        self.metadata = metadata
        if let view = window?.contentView as? PinImageView {
            view.updateMetadataAccessibility(metadata)
        }
    }

    func setComparisonReference(_ isReference: Bool) {
        isComparisonReference = isReference
        window?.contentView?.needsDisplay = true
    }

    func didFinishGeometryChange() { onStateChanged() }

    func requestSaveWorkspace() { onSaveWorkspace() }

    func restoreInteraction() {
        guard window?.ignoresMouseEvents == true else { return }
        window?.ignoresMouseEvents = false
        onStateChanged()
    }
    func setShadow(_ enabled: Bool) { window?.hasShadow = enabled }

    func windowWillClose(_ notification: Notification) {
        removeWorkspaceObserver()
        onClose(id)
    }

    private static func initialSize(for imageSize: CGSize) -> CGSize {
        let maximum = CGSize(width: 640, height: 480)
        let scale = min(maximum.width / imageSize.width, maximum.height / imageSize.height, 1)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private var shouldBeVisibleForFrontmostApplication: Bool {
        guard let visibilityBundleIdentifier else { return true }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == visibilityBundleIdentifier
    }

    private func updateApplicationVisibility() {
        shouldBeVisibleForFrontmostApplication ? window?.orderFrontRegardless() : window?.orderOut(nil)
    }

    private var currentState: PinWorkspaceWindowState {
        PinWorkspaceWindowState(
            frame: window?.frame ?? .zero,
            opacity: Double(baseOpacity),
            ignoresMouseEvents: window?.ignoresMouseEvents ?? false,
            isPositionLocked: isPositionLocked,
            appearsOnAllSpaces: appearsOnAllSpaces,
            visibilityBundleIdentifier: visibilityBundleIdentifier,
            isAutoFadeOnHoverEnabled: isAutoFadeOnHoverEnabled
        )
    }

    @discardableResult
    private func apply(_ state: PinWorkspaceWindowState) -> Bool {
        guard state.isValid, let window else { return false }
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        window.setFrame(
            PinWindowVisibleGeometry.constrainedFrame(state.frame, visibleFrames: visibleFrames),
            display: true
        )
        baseOpacity = min(max(CGFloat(state.opacity), 0.15), 1)
        window.ignoresMouseEvents = state.ignoresMouseEvents
        isPositionLocked = state.isPositionLocked
        window.isMovableByWindowBackground = !state.isPositionLocked
        window.collectionBehavior.subtract([.canJoinAllSpaces, .moveToActiveSpace])
        window.collectionBehavior.insert(state.appearsOnAllSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        isAutoFadeOnHoverEnabled = state.isAutoFadeOnHoverEnabled
        isPointerHovering = false

        let requestedBundleIdentifier = state.visibilityBundleIdentifier
        let canRestoreApplicationBinding = requestedBundleIdentifier.map {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
                || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == $0
        } ?? true
        setVisibilityBundleIdentifier(canRestoreApplicationBinding ? requestedBundleIdentifier : nil)
        applyVisibleOpacity()
        window.invalidateCursorRects(for: window.contentView ?? NSView())
        updateApplicationVisibility()
        return requestedBundleIdentifier != nil && !canRestoreApplicationBinding
    }

    private func applyVisibleOpacity() {
        window?.alphaValue = isAutoFadeOnHoverEnabled && isPointerHovering ? 0.18 : baseOpacity
    }

    private func setVisibilityBundleIdentifier(_ bundleIdentifier: String?) {
        removeWorkspaceObserver()
        visibilityBundleIdentifier = bundleIdentifier
        guard bundleIdentifier != nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateApplicationVisibility() }
        }
    }

    private func removeWorkspaceObserver() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("pin.saveFailedTitle")
        alert.informativeText = L10n.text("pin.saveFailedMessage", error.localizedDescription)
        alert.addButton(withTitle: L10n.text("common.done"))
        alert.runModal()
    }
}

final class PinImageView: NSImageView {
    private weak var pinController: PinWindowController?
    private var dragStart: (mouseLocation: CGPoint, windowOrigin: CGPoint)?
    private var resizeStart: (handle: PinWindowResizeHandle, mouseLocation: CGPoint, frame: CGRect)?
    private var pointerTrackingArea: NSTrackingArea?
    private var hoveredResizeHandle: PinWindowResizeHandle?
    private var showsResizeChrome = false

    private static let diagonalNorthWestSouthEastCursor = diagonalCursor(
        symbolName: "arrow.up.left.and.arrow.down.right"
    )
    private static let diagonalNorthEastSouthWestCursor = diagonalCursor(
        symbolName: "arrow.up.right.and.arrow.down.left"
    )

    init(image: NSImage, controller: PinWindowController) {
        pinController = controller
        super.init(frame: .zero)
        self.image = image
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        menu = buildMenu()
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L10n.text("pin.accessibility.image"))
        updateMetadataAccessibility(controller.workspaceCapture.metadata)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? { buildMenu() }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if pinController?.isComparisonReference == true {
            let referenceBorder = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
            referenceBorder.lineWidth = 4
            NSColor.controlAccentColor.setStroke()
            referenceBorder.stroke()
            let markerRect = CGRect(x: 8, y: bounds.height - 30, width: 24, height: 22)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: markerRect, xRadius: 6, yRadius: 6).fill()
            ("A" as NSString).draw(
                at: CGPoint(x: markerRect.minX + 7, y: markerRect.minY + 3),
                withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.boldSystemFont(ofSize: 13)]
            )
        }
        guard showsResizeChrome else { return }

        let borderRect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let border = NSBezierPath(roundedRect: borderRect, xRadius: 6, yRadius: 6)
        border.lineWidth = 3
        NSColor.black.withAlphaComponent(0.38).setStroke()
        border.stroke()
        border.lineWidth = 1
        NSColor.white.withAlphaComponent(0.95).setStroke()
        border.stroke()

        for handle in PinWindowResizeHandle.allCases {
            let rect = PinWindowResizeChromeGeometry.handleRect(for: handle, in: bounds)
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: min(rect.width, rect.height) / 2,
                yRadius: min(rect.width, rect.height) / 2
            )
            path.lineWidth = 1
            if handle == hoveredResizeHandle {
                NSColor.controlAccentColor.setFill()
                NSColor.white.withAlphaComponent(0.95).setStroke()
            } else {
                NSColor.white.withAlphaComponent(0.95).setFill()
                NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
            }
            path.fill()
            path.stroke()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        pinController?.updateHover(true)
        updateResizeChrome(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateResizeChrome(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        pinController?.updateHover(false)
        guard resizeStart == nil else { return }
        hoveredResizeHandle = nil
        showsResizeChrome = false
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let interior = bounds.insetBy(dx: PinWindowResizeGeometry.hitSlop, dy: PinWindowResizeGeometry.hitSlop)
        if !interior.isEmpty {
            addCursorRect(interior, cursor: .openHand)
        }
        for handle in PinWindowResizeHandle.allCases {
            let rect = PinWindowResizeGeometry.cursorRect(for: handle, in: bounds)
            if !rect.isEmpty {
                addCursorRect(rect, cursor: resizeCursor(for: handle))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.makeKey()
        window.makeFirstResponder(self)
        guard pinController?.isPositionLocked != true else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let handle = PinWindowResizeGeometry.handle(at: point, in: bounds) {
            resizeStart = (handle, NSEvent.mouseLocation, window.frame)
            dragStart = nil
            hoveredResizeHandle = handle
            showsResizeChrome = true
            needsDisplay = true
            resizeCursor(for: handle).set()
            return
        }
        // 图片视图覆盖整个无边框窗口，因此由它显式转发拖动，而不是依赖 window background。
        dragStart = (NSEvent.mouseLocation, window.frame.origin)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        if let resizeStart {
            let frame = PinWindowResizeGeometry.resizedFrame(
                resizeStart.frame,
                using: resizeStart.handle,
                from: resizeStart.mouseLocation,
                to: NSEvent.mouseLocation,
                minimumSize: window.minSize
            )
            window.setFrame(frame, display: true)
            resizeCursor(for: resizeStart.handle).set()
            return
        }
        guard let dragStart else { return }
        let origin = PinWindowDragGeometry.origin(
            initialWindowOrigin: dragStart.windowOrigin,
            initialMouseLocation: dragStart.mouseLocation,
            currentMouseLocation: NSEvent.mouseLocation
        )
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        resizeStart = nil
        updateResizeChrome(at: convert(event.locationInWindow, from: nil))
        window?.invalidateCursorRects(for: self)
        pinController?.didFinishGeometryChange()
    }

    func updateMetadataAccessibility(_ metadata: PinMetadata) {
        setAccessibilityValue(
            metadata.isEmpty
                ? L10n.text("pin.metadata.accessibility.empty")
                : L10n.text("pin.metadata.accessibility.summary", metadata.note.isEmpty ? 0 : 1, metadata.tags.count)
        )
    }

    private func updateResizeChrome(at point: CGPoint) {
        let nextHandle = PinWindowResizeGeometry.handle(at: point, in: bounds)
        let nextVisibility = resizeStart != nil || PinWindowResizeChromeGeometry.isNearEdge(point, in: bounds)
        guard hoveredResizeHandle != nextHandle || showsResizeChrome != nextVisibility else { return }
        hoveredResizeHandle = nextHandle
        showsResizeChrome = nextVisibility
        needsDisplay = true
    }

    private func resizeCursor(for handle: PinWindowResizeHandle) -> NSCursor {
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

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text("pin.copy"), action: #selector(copyImage), keyEquivalent: "c")
        menu.addItem(withTitle: L10n.text("pin.save"), action: #selector(saveImage), keyEquivalent: "s")
        menu.addItem(withTitle: L10n.text("pin.metadata.edit"), action: #selector(editMetadata), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("pin.zoomIn"), action: #selector(zoomIn), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("pin.zoomOut"), action: #selector(zoomOut), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("pin.restoreInitialState"), action: #selector(restoreInitialState), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("pin.opacityUp"), action: #selector(increaseOpacity), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("pin.opacityDown"), action: #selector(decreaseOpacity), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text(pinController?.isPositionLocked == true ? "pin.unlockPosition" : "pin.lockPosition"), action: #selector(togglePositionLock), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text(pinController?.appearsOnAllSpaces == true ? "pin.currentSpaceOnly" : "pin.allSpaces"), action: #selector(toggleAllSpaces), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text(pinController?.isLimitedToCurrentApplication == true ? "pin.allApplications" : "pin.currentApplicationOnly"), action: #selector(toggleCurrentApplicationVisibility), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text(pinController?.isAutoFadeOnHoverEnabled == true ? "pin.disableAutoFade" : "pin.enableAutoFade"), action: #selector(toggleAutoFade), keyEquivalent: "")
        menu.addItem(
            withTitle: L10n.text(pinController?.ignoresMouseEvents == true ? "pin.disableMousePassthrough" : "pin.enableMousePassthrough"),
            action: #selector(toggleMousePassthrough),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        addComparisonMenu(to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("pinWorkspace.saveCurrent"), action: #selector(saveWorkspace), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("pin.close"), action: #selector(closePin), keyEquivalent: "w")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func copyImage() { pinController?.copyImage() }
    @objc private func saveImage() { pinController?.saveImage() }
    @objc private func editMetadata() { pinController?.requestMetadataEdit() }
    @objc private func zoomIn() { pinController?.scale(by: 1.1) }
    @objc private func zoomOut() { pinController?.scale(by: 1 / 1.1) }
    @objc private func restoreInitialState() { pinController?.restoreInitialState() }
    @objc private func increaseOpacity() { pinController?.adjustOpacity(by: 0.1) }
    @objc private func decreaseOpacity() { pinController?.adjustOpacity(by: -0.1) }
    @objc private func togglePositionLock() { pinController?.togglePositionLock() }
    @objc private func toggleAllSpaces() { pinController?.toggleAllSpaces() }
    @objc private func toggleCurrentApplicationVisibility() { pinController?.toggleCurrentApplicationVisibility() }
    @objc private func toggleAutoFade() { pinController?.toggleAutoFadeOnHover() }
    @objc private func toggleMousePassthrough() { pinController?.toggleMousePassthrough() }
    @objc private func saveWorkspace() { pinController?.requestSaveWorkspace() }
    @objc private func closePin() { pinController?.close() }

    private func addComparisonMenu(to menu: NSMenu) {
        switch pinController?.comparisonMenuState ?? .unavailable {
        case .unavailable:
            let item = menu.addItem(withTitle: L10n.text("pin.compare.needsTwoPins"), action: nil, keyEquivalent: "")
            item.isEnabled = false
        case .canSetReference:
            menu.addItem(withTitle: L10n.text("pin.compare.setReference"), action: #selector(setComparisonReference), keyEquivalent: "")
        case .isReference:
            menu.addItem(withTitle: L10n.text("pin.compare.cancelReference"), action: #selector(cancelComparisonReference), keyEquivalent: "")
        case .canCompare:
            let parent = NSMenuItem(title: L10n.text("pin.compare.withReference"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(withTitle: L10n.text("pin.compare.sideBySide"), action: #selector(compareSideBySide), keyEquivalent: "")
            submenu.addItem(withTitle: L10n.text("pin.compare.overlay"), action: #selector(compareOverlay), keyEquivalent: "")
            submenu.addItem(withTitle: L10n.text("pin.compare.blend"), action: #selector(compareBlend), keyEquivalent: "")
            submenu.items.forEach { $0.target = self }
            parent.submenu = submenu
            menu.addItem(parent)
        }
    }

    @objc private func setComparisonReference() { pinController?.requestComparison(mode: nil) }
    @objc private func cancelComparisonReference() { pinController?.requestComparison(mode: nil) }
    @objc private func compareSideBySide() { pinController?.requestComparison(mode: .sideBySide) }
    @objc private func compareOverlay() { pinController?.requestComparison(mode: .overlay) }
    @objc private func compareBlend() { pinController?.requestComparison(mode: .blend) }
}
