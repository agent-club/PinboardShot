import AppKit
import SwiftUI

struct MagneticDesktopPreferences: View {
    @AppStorage(MagneticDesktopSettings.enabledKey) private var enabled = false
    @AppStorage(MagneticDesktopSettings.maximumVisibleKey) private var maximumVisible = MagneticDesktopSettings.defaultMaximumVisible
    @AppStorage(HistorySettings.enabledDefaultsKey) private var historyEnabled = true
    @AppStorage(MagneticDesktopSettings.animationStyleKey) private var animationStyle = MagneticAnimationStyle.full
    @AppStorage(MagneticDesktopSettings.reduceMotionKey) private var motionReduced = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.text("magnetic.enabled"), isOn: $enabled).clickCursor()
            HStack {
                Stepper(value: $maximumVisible, in: MagneticDesktopSettings.supportedLimits) {
                    Text(L10n.text("magnetic.maximum", maximumVisible))
                }
                .disabled(!enabled)
                Text(verbatim: "\(MagneticDesktopSettings.supportedLimits.lowerBound)–\(MagneticDesktopSettings.supportedLimits.upperBound)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("magnetic.help"))
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Picker(L10n.text("magnetic.animationStyle"), selection: $animationStyle) {
                ForEach(MagneticAnimationStyle.allCases, id: \.self) { style in
                    Text(L10n.text("magnetic.animationStyle.\(style.rawValue)")).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!enabled)
            Text(L10n.text("magnetic.animationStyle.\(animationStyle.rawValue).help"))
                .font(.callout).foregroundStyle(.secondary)
            Toggle(L10n.text("magnetic.reduceMotion"), isOn: $motionReduced)
                .clickCursor().disabled(!enabled)
            Text(L10n.text(systemReduceMotion ? "magnetic.reduceMotion.system" : "magnetic.reduceMotion.help"))
                .font(.callout).foregroundStyle(.secondary)
            if !historyEnabled {
                Text(L10n.text("magnetic.needsHistory"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

enum MagneticFlightDirection { case outward, inward }

@MainActor
final class MagneticCardMotion: ObservableObject {
    @Published var progress: CGFloat = 1
    @Published var direction: MagneticFlightDirection = .outward
    @Published var style: MagneticAnimationStyle = .full
    func begin(_ direction: MagneticFlightDirection) { self.direction = direction; progress = 0 }
    func finish() { progress = 1 }
}

struct MagneticFanLeaf: Identifiable {
    let id: Int
    let image: NSImage
    let frame: CGRect
}

@MainActor
final class MagneticFanMotion: ObservableObject {
    @Published var progress: CGFloat = 0
    var leaves: [MagneticFanLeaf] = []
}

@MainActor
final class MagneticDockMotionView: NSView {
    private let start: CGFloat
    private let end: CGFloat
    private let duration: TimeInterval
    private var startedAt: CFTimeInterval = 0

    var progress: CGFloat {
        let elapsed = min(1, max(0, (CACurrentMediaTime() - startedAt) / duration))
        return start + (end - start) * CGFloat(elapsed)
    }

    convenience init(leaves: [MagneticFanLeaf], screen: CGRect, pivot: CGPoint,
                     start: CGFloat, end: CGFloat, duration: TimeInterval) {
        let frames = leaves.map { leaf in
            (start: CGRect(x: pivot.x - leaf.frame.width * 0.01, y: pivot.y - leaf.frame.height * 0.01,
                           width: leaf.frame.width * 0.02, height: leaf.frame.height * 0.02), end: leaf.frame)
        }
        self.init(leaves: leaves, screen: screen, frames: frames, start: start, end: end,
                  duration: duration, fades: true)
    }

    init(leaves: [MagneticFanLeaf], screen: CGRect, frames: [(start: CGRect, end: CGRect)],
         start: CGFloat = 0, end: CGFloat = 1, duration: TimeInterval, fades: Bool = false) {
        self.start = start
        self.end = end
        self.duration = duration
        super.init(frame: CGRect(origin: .zero, size: screen.size))
        wantsLayer = true
        let root = CALayer()
        root.frame = bounds
        layer = root

        // Cache each card once; the compositor interpolates these poses without main-thread redraws.
        let samples = (0...30).map { start + (end - start) * CGFloat($0) / 30 }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (leaf, frames) in zip(leaves, frames).reversed() {
            let card = CALayer()
            card.bounds = CGRect(origin: .zero, size: leaf.frame.size)
            card.contents = leaf.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            card.contentsGravity = .resize
            card.contentsScale = leaf.image.representations.first.map {
                CGFloat($0.pixelsWide) / leaf.frame.width
            } ?? 1
            let eased = samples.map { $0 * $0 * (3 - 2 * $0) }
            let positions = eased.map { NSValue(point: CGPoint(
                x: frames.start.midX + (frames.end.midX - frames.start.midX) * $0 - screen.minX,
                y: frames.start.midY + (frames.end.midY - frames.start.midY) * $0 - screen.minY)) }
            let transforms = eased.map { NSValue(caTransform3D: CATransform3DMakeScale(
                (frames.start.width + (frames.end.width - frames.start.width) * $0) / leaf.frame.width,
                (frames.start.height + (frames.end.height - frames.start.height) * $0) / leaf.frame.height, 1)) }
            let opacities = samples.map { fades ? min(1, $0 * 8) : 1 }
            let finalProgress = end * end * (3 - 2 * end)
            card.position = CGPoint(x: frames.start.midX + (frames.end.midX - frames.start.midX) * finalProgress - screen.minX,
                                    y: frames.start.midY + (frames.end.midY - frames.start.midY) * finalProgress - screen.minY)
            card.transform = CATransform3DMakeScale(
                (frames.start.width + (frames.end.width - frames.start.width) * finalProgress) / leaf.frame.width,
                (frames.start.height + (frames.end.height - frames.start.height) * finalProgress) / leaf.frame.height, 1)
            card.opacity = Float(fades ? min(1, end * 8) : 1)
            root.addSublayer(card)

            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = positions
            let scale = CAKeyframeAnimation(keyPath: "transform")
            scale.values = transforms
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = opacities
            let group = CAAnimationGroup()
            group.animations = [position, scale, opacity]
            group.duration = duration
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            card.add(group, forKey: "dockShrink")
        }
        startedAt = CACurrentMediaTime()
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct MagneticFanMotionView: View {
    @ObservedObject var motion: MagneticFanMotion
    let screenFrame: CGRect
    let pivot: CGPoint
    var simple = false
    var style: MagneticAnimationStyle = .full

    var body: some View {
        Canvas { context, _ in
            let hinge = CGPoint(x: pivot.x - screenFrame.minX, y: screenFrame.maxY - pivot.y)
            for (index, leaf) in motion.leaves.enumerated().reversed() {
                if simple {
                    var drawing = context
                    drawing.opacity = Double(motion.progress)
                    drawing.draw(drawing.resolve(Image(nsImage: leaf.image)), in:
                        CGRect(x: leaf.frame.minX - screenFrame.minX, y: screenFrame.maxY - leaf.frame.maxY,
                               width: leaf.frame.width, height: leaf.frame.height))
                    continue
                }
                let delay = 0.14 * CGFloat(index) / CGFloat(max(1, motion.leaves.count - 1))
                let progress = min(1, max(0, (motion.progress - delay) / (1 - delay)))
                if style == .elastic || style == .arc {
                    let eased = style.progress(progress)
                    let end = CGPoint(x: leaf.frame.midX - screenFrame.minX, y: screenFrame.maxY - leaf.frame.midY)
                    let point = style.point(from: hinge, to: end, progress: eased)
                    let pulse = sin(progress * .pi)
                    var drawing = context
                    drawing.opacity = Double(min(1, progress * 6))
                    drawing.translateBy(x: point.x, y: point.y)
                    drawing.rotate(by: .degrees(Double(pulse) * (style == .arc ? -14 : 5)))
                    let scale = style == .elastic
                        ? 0.12 + 0.88 * eased + sin(progress * .pi * 3) * pulse * 0.08
                        : 0.12 + 0.88 * eased
                    drawing.scaleBy(x: scale, y: scale)
                    drawing.draw(drawing.resolve(Image(nsImage: leaf.image)), in:
                        CGRect(x: -leaf.frame.width / 2, y: -leaf.frame.height / 2,
                               width: leaf.frame.width, height: leaf.frame.height))
                    continue
                }
                let eased = progress * progress * (3 - 2 * progress)
                let end = CGPoint(x: leaf.frame.midX - screenFrame.minX, y: screenFrame.maxY - leaf.frame.midY)
                let dx = end.x - hinge.x, dy = end.y - hinge.y
                var endAngle = atan2(dy, dx)
                if endAngle > 0 { endAngle -= 2 * .pi }
                let angle = -.pi / 2 + (endAngle + .pi / 2) * eased
                let radius = 16 + (hypot(dx, dy) - 16) * eased
                // First turn the leaves around the shared hinge, then flatten them into the existing rail.
                let flatten = min(1, max(0, (progress - 0.62) / 0.38))
                let aligned = flatten * flatten * (3 - 2 * flatten)
                let rotation = (angle + .pi) * (1 - aligned)
                let scale = 0.08 + 0.92 * eased
                var drawing = context
                drawing.opacity = Double(min(1, progress * 7))
                drawing.translateBy(x: hinge.x + cos(angle) * radius, y: hinge.y + sin(angle) * radius)
                drawing.rotate(by: .radians(Double(rotation)))
                drawing.scaleBy(x: scale, y: scale)
                drawing.draw(drawing.resolve(Image(nsImage: leaf.image)), in:
                    CGRect(x: -leaf.frame.width / 2, y: -leaf.frame.height / 2,
                           width: leaf.frame.width, height: leaf.frame.height))
            }
        }
        .allowsHitTesting(false)
    }
}

struct MagneticFlightTrail: Identifiable {
    let id: UUID
    let start: CGPoint
    let end: CGPoint
    var progress: CGFloat
    var style: MagneticAnimationStyle = .full
}

@MainActor
final class MagneticFlightTrailState: ObservableObject {
    @Published var flights: [MagneticFlightTrail] = []
}

struct MagneticFlightTrailView: View {
    @ObservedObject var state: MagneticFlightTrailState
    let screenFrame: CGRect

    var body: some View {
        Canvas { context, _ in
            for flight in state.flights {
                for segment in 0..<12 {
                    let tail = CGFloat(segment) / 12
                    let start = max(0, flight.progress - 0.18 * (1 - tail))
                    let end = max(0, flight.progress - 0.18 * (1 - tail - 1 / 12))
                    func point(_ progress: CGFloat) -> CGPoint {
                        let point = flight.style.point(from: flight.start, to: flight.end, progress: progress)
                        return CGPoint(x: point.x - screenFrame.minX, y: screenFrame.maxY - point.y)
                    }
                    var path = Path()
                    path.move(to: point(start)); path.addLine(to: point(end))
                    let opacity = tail * min(1, (1 - flight.progress) * 6)
                    context.stroke(path, with: .color(.cyan.opacity(Double(opacity) * 0.55)),
                                   style: StrokeStyle(lineWidth: 3 + tail * 6, lineCap: .round))
                    context.stroke(path, with: .color(.white.opacity(Double(opacity))),
                                   style: StrokeStyle(lineWidth: 1 + tail, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct MagneticCardView: View {
    let image: NSImage
    let item: HistoryItem
    let isExpanded: Bool
    var isFocused: Bool = false
    var fanAngle: Double = 0
    let onExtract: () -> Void
    let onReturn: () -> Void
    let onReturnAll: () -> Void
    @ObservedObject var motion: MagneticCardMotion
    let onCopy: () -> Void
    let onPin: () -> Void
    let onEdit: () -> Void
    let onDrag: (CGPoint, Bool, TimeInterval) -> Void

    private var flightScale: CGFloat {
        let pulse = sin(motion.progress * .pi)
        switch motion.style {
        case .elastic: return 1 - abs(sin(motion.progress * .pi * 2.5)) * pulse * 0.045
        case .arc: return 1 - pulse * 0.12
        case .full, .simple: return 1
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if isExpanded {
                    HStack(spacing: 10) {
                        Button(action: onEdit) { Label(L10n.text("magnetic.edit"), systemImage: "pencil") }.clickCursor()
                        Spacer(minLength: 4)
                        Button(action: onReturn) { Label(L10n.text("magnetic.return"), systemImage: "arrow.right.to.line") }.clickCursor()
                        Button(action: onReturnAll) { Image(systemName: "rectangle.stack.badge.minus") }.clickCursor()
                            .help(L10n.text("magnetic.returnAll"))
                            .accessibilityLabel(L10n.text("magnetic.returnAll"))
                    }
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                }
                imageButton
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(isExpanded ? 1 : 0.25), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5).allowsHitTesting(false))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(OrbitalPalette.blue.opacity(0.82), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(flightScale)
            .rotationEffect(.degrees(motion.style == .arc ? Double(sin(motion.progress * .pi)) * -3 : 0))
            .rotationEffect(.degrees(isExpanded ? 0 : fanAngle))
            // Leave room for the small fan rotation inside each stable native hit window.
            .padding(isExpanded ? 3 : min(8, max(4, geometry.size.width / 16)))
            .contextMenu {
                if !isExpanded { Button(L10n.text("magnetic.extract"), action: onExtract) }
                Button(L10n.text("magnetic.edit"), action: onEdit)
                if isExpanded {
                    Button(L10n.text("magnetic.return"), action: onReturn)
                    Button(L10n.text("magnetic.returnAll"), action: onReturnAll)
                }
                Divider()
                Button(L10n.text("common.copy"), action: onCopy)
                Button(L10n.text("magnetic.openPin"), action: onPin)
            }
        }
    }

    private var imageButton: some View {
        Button(action: onExtract) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomLeading) {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HStack(spacing: 0) {
                                Text(item.createdAt, style: .time)
                                    .font(.system(size: isExpanded ? 10 : min(8, max(6, geometry.size.width / 12)),
                                                  weight: .medium, design: .rounded))
                                    .padding(.horizontal, isExpanded ? 4 : 3).padding(.vertical, 1)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(3)
                    }
                    .allowsHitTesting(false)
                }
                .padding(isExpanded ? 5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("magnetic.card", item.pixelWidth, item.pixelHeight))
        .help(L10n.text("magnetic.cardHelp"))
    }
}

class MagneticPassiveHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class MagneticCardHostingView: MagneticPassiveHostingView<MagneticCardView> {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    private var pressStart: (point: CGPoint, time: TimeInterval)?
    private var isNativeDragging = false

    private var imageArea: CGRect {
        let toolbar: CGFloat = rootView.isExpanded ? 40 : 0
        return CGRect(x: bounds.minX, y: bounds.minY + (isFlipped ? toolbar : 0),
                      width: bounds.width, height: max(0, bounds.height - toolbar))
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(imageArea, cursor: .openHand)
    }

    func handleMouseEvent(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        switch event.type {
        case .leftMouseDown:
            pressStart = nil
            isNativeDragging = false
            let local = convert(event.locationInWindow, from: nil)
            // Leave toolbar buttons to SwiftUI; only the screenshot surface owns native dragging.
            guard imageArea.contains(local) else { return false }
            pressStart = (point, event.timestamp)
            isNativeDragging = false
            return true
        case .leftMouseDragged:
            guard let start = pressStart else { return false }
            if !isNativeDragging {
                guard hypot(point.x - start.point.x, point.y - start.point.y) >= 4 else { return true }
                isNativeDragging = true
                NSCursor.closedHand.set()
                rootView.onDrag(start.point, false, start.time)
            }
            // Use the event's own screen position and time: callback delays and a moving window
            // must not turn a fast release into a zero-speed SwiftUI gesture.
            rootView.onDrag(point, false, event.timestamp)
            return true
        case .leftMouseUp:
            guard pressStart != nil else { return false }
            let wasDragging = isNativeDragging
            pressStart = nil
            isNativeDragging = false
            window.invalidateCursorRects(for: self)
            (imageArea.contains(convert(event.locationInWindow, from: nil)) ? NSCursor.openHand : .arrow).set()
            if wasDragging { rootView.onDrag(point, true, event.timestamp) }
            else { rootView.onExtract() }
            return true
        default:
            return false
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverArea == nil else { return }
        // Nonactivating panels need tracking even while another application is frontmost.
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
    override func mouseMoved(with event: NSEvent) { onHoverChanged?(true) }
}

@MainActor
final class MagneticBoxMotion: ObservableObject {
    @Published var progress: CGFloat = 1
}

struct MagneticBoxView: View {
    let images: [NSImage]
    let count: Int
    let desktopCount: Int
    @ObservedObject var motion: MagneticBoxMotion
    let onReturnAll: () -> Void
    let onOpen: () -> Void
    let onCollapse: () -> Void
    var motionReduced = false
    var decorativeEffects = true
    var animationStyle: MagneticAnimationStyle = .full

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onOpen) {
                VStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "archivebox").foregroundStyle(OrbitalPalette.blue)
                        Text(L10n.text("magnetic.box")).fontWeight(.semibold).lineLimit(1)
                        Text("\(count)").monospacedDigit().foregroundStyle(OrbitalPalette.secondaryText)
                        Spacer(minLength: 2)
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(OrbitalPalette.secondaryText.opacity(0.65))
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 11)).frame(height: 20)
                    previewStack
                        .offset(x: animationStyle == .full ? sin(motion.progress * .pi * 8) * 2 * (1 - motion.progress) : 0,
                                y: -sin(motion.progress * .pi) * (animationStyle == .elastic ? 5 : 2))
                        .rotationEffect(.degrees(Double(sin(motion.progress * .pi * (animationStyle == .arc ? 2 : 6))
                            * 2 * (1 - motion.progress))))
                        .scaleEffect(1 + sin(motion.progress * .pi) * (animationStyle == .elastic ? 0.035 : 0.015))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("magnetic.boxCount", count))
            .help(L10n.text("magnetic.boxHelp"))
            HStack(spacing: 6) {
                Button(L10n.text("magnetic.browseBox"), action: onOpen).clickCursor()
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(OrbitalPalette.blue)
                Spacer(minLength: 0)
                if desktopCount > 0 {
                    Button(action: onReturnAll) {
                        Image(systemName: "arrow.down.to.line.compact").frame(width: 22, height: 22)
                    }.clickCursor()
                    .help(L10n.text("magnetic.returnAll"))
                    .accessibilityLabel(L10n.text("magnetic.returnAll"))
                }
                Button(action: onCollapse) {
                    Image(systemName: "chevron.right.2").frame(width: 22, height: 22)
                }.clickCursor()
                .help(L10n.text("magnetic.collapse"))
                .accessibilityLabel(L10n.text("magnetic.collapse"))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(OrbitalPalette.secondaryText).buttonStyle(.plain)
            .frame(height: 22)
        }
        .padding(9)
        .frame(width: MagneticDesktopGeometry.boxSize.width, height: MagneticDesktopGeometry.boxSize.height)
        .foregroundStyle(OrbitalPalette.text)
        .background(TrayPanelBackdrop())
        // Hover only fans the photos; the tray and its drag target keep fixed bounds.
        .onHover { isHovering = $0 }
        .animation(reduceMotion || motionReduced ? nil : .easeOut(duration: 0.18), value: isHovering)
    }

    private var previewStack: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(OrbitalPalette.nodeFill)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(OrbitalPalette.nodeEdge.opacity(0.25), lineWidth: 0.5))
            if count == 0 {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(OrbitalPalette.nodeEdge)
                    .accessibilityHidden(true)
            }
            ForEach(Array(images.prefix(5).enumerated()), id: \.offset) { index, image in
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 68, height: 42).clipped().padding(2)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .rotationEffect(.degrees([-8, 6, -3, 9, 1][index] * (isHovering && decorativeEffects && !reduceMotion && !motionReduced ? 1.08 : 1)))
                    .offset(x: [-28, 21, -10, 29, 2][index], y: [0, -1, -3, 2, -2][index])
            }
        }
        .frame(height: 62)
    }
}

final class MagneticBoxHostingView: MagneticPassiveHostingView<MagneticBoxView> {
    var onMove: ((CGPoint) -> Void)?
    private var pressStart: (point: CGPoint, origin: CGPoint)?
    private(set) var isDragging = false

    private var dragArea: CGRect {
        // The footer belongs to SwiftUI buttons; header and photo surface own window dragging.
        let footer: CGFloat = 37
        return CGRect(x: bounds.minX, y: bounds.minY + (isFlipped ? 0 : footer),
                      width: bounds.width, height: max(0, bounds.height - footer))
    }

    func cancelDrag() { pressStart = nil; isDragging = false }

    func handleMouseEvent(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        switch event.type {
        case .leftMouseDown:
            cancelDrag()
            guard dragArea.contains(convert(event.locationInWindow, from: nil)) else { return false }
            pressStart = (point, window.frame.origin)
            return true
        case .leftMouseDragged:
            guard let start = pressStart else { return false }
            guard isDragging || hypot(point.x - start.point.x, point.y - start.point.y) >= 4 else { return true }
            isDragging = true
            NSCursor.closedHand.set()
            onMove?(CGPoint(x: start.origin.x + point.x - start.point.x,
                            y: start.origin.y + point.y - start.point.y))
            return true
        case .leftMouseUp:
            guard let start = pressStart else { return false }
            let moved = isDragging
            if moved {
                onMove?(CGPoint(x: start.origin.x + point.x - start.point.x,
                                y: start.origin.y + point.y - start.point.y))
            }
            cancelDrag()
            window.invalidateCursorRects(for: self)
            (dragArea.contains(convert(event.locationInWindow, from: nil)) ? NSCursor.openHand : .arrow).set()
            if !moved { rootView.onOpen() }
            return true
        default:
            return false
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(dragArea, cursor: .openHand)
    }
}

@MainActor
struct MagneticCapsuleBubbles: View {
    let capsuleFrame: CGRect
    let viewport: CGRect
    let edge: MagneticDockEdge

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
            Canvas { context, _ in
                let inwardAngle: CGFloat
                switch edge {
                case .right: inwardAngle = .pi
                case .left: inwardAngle = 0
                case .top: inwardAngle = .pi / 2
                case .bottom: inwardAngle = -.pi / 2
                }
                let capsuleCenter = CGPoint(x: capsuleFrame.midX - viewport.minX, y: viewport.maxY - capsuleFrame.midY)
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6) / 3.6
                // Three tiny, staggered rings stay sparse and fade continuously rather than flashing.
                for index in 0..<3 {
                    let progress = CGFloat((phase + Double(index) / 3).truncatingRemainder(dividingBy: 1))
                    // Spread emitters around the exposed perimeter; the screen-facing rim stays clear.
                    let angle = inwardAngle + CGFloat(index - 1) * .pi * 0.44
                    let normal = CGPoint(x: cos(angle), y: sin(angle))
                    let origin = CGPoint(x: capsuleCenter.x + normal.x * (capsuleFrame.width / 2 - 2),
                                         y: capsuleCenter.y + normal.y * (capsuleFrame.height / 2 - 2))
                    let distance = 4 + 22 * progress
                    let drift = sin(progress * .pi * 2 + CGFloat(index)) * 2 + CGFloat(index - 1) * 3
                    let radius = 1.6 + sin(progress * .pi) * 0.8
                    let opacity = Double(sin(progress * .pi)) * 0.24
                    let center = CGPoint(x: origin.x + normal.x * distance - normal.y * drift,
                                         y: origin.y + normal.y * distance + normal.x * drift)
                    let bubble = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                       width: radius * 2, height: radius * 2))
                    context.fill(bubble, with: .color(OrbitalPalette.blue.opacity(opacity * 0.12)))
                    context.stroke(bubble, with: .color(OrbitalPalette.blue.opacity(opacity)), lineWidth: 0.65)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
final class MagneticFoldedMotion: ObservableObject {
    @Published var progress: CGFloat = 0
    @Published var compactProgress: CGFloat = 0
    @Published var pull: CGFloat = 0
    @Published var dockEdge: MagneticDockEdge = .right
}

final class MagneticFoldedHostingView: MagneticPassiveHostingView<MagneticFoldedView> {
    var onDragBegan: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint, Bool) -> Void)?
    var onDragCancelled: (() -> Void)?
    private var pressStart: CGPoint?
    private(set) var isDragging = false

    func cancelDrag() {
        pressStart = nil
        isDragging = false
        onDragCancelled?()
    }

    func handleMouseEvent(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        switch event.type {
        case .leftMouseDown:
            cancelDrag()
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
            pressStart = point
            onDragBegan?(point)
            return true
        case .leftMouseDragged:
            guard let start = pressStart else { return false }
            // Match the tray's threshold so a small hand movement still counts as an expand click.
            guard isDragging || hypot(point.x - start.x, point.y - start.y) >= 4 else { return true }
            isDragging = true
            NSCursor.closedHand.set()
            onDrag?(point, false)
            return true
        case .leftMouseUp:
            guard pressStart != nil else { return false }
            let moved = isDragging
            if moved { onDrag?(point, true) }
            cancelDrag()
            window.invalidateCursorRects(for: self)
            (bounds.contains(convert(event.locationInWindow, from: nil)) ? NSCursor.openHand : .arrow).set()
            if !moved { rootView.onExpand() }
            return true
        default:
            return false
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
}

struct MagneticFoldedView: View {
    let count: Int
    // Fixed decorative artwork keeps the folded handle independent of captured content.
    static let artworkNames = ["MagneticFoldedMountain", "MagneticFoldedChart", "MagneticFoldedPaper"]
    @ObservedObject var motion = MagneticFoldedMotion()
    let onExpand: () -> Void
    var onHoverChanged: ((Bool) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: onExpand) {
            GeometryReader { geometry in
                let progress = motion.progress
                let compact = motion.compactProgress * (1 - progress)
                let canvasWidth = 32 + 64 * progress - 8 * compact
                let canvasHeight = 144 - 32 * progress - 88 * compact
                let rotation = (motion.dockEdge == .top ? -90.0 : (motion.dockEdge == .bottom ? 90.0 : 0)) * Double(1 - progress)
                let radians = CGFloat(rotation * .pi / 180)
                let rotatedWidth = canvasWidth * abs(cos(radians)) + canvasHeight * abs(sin(radians))
                let rotatedHeight = canvasWidth * abs(sin(radians)) + canvasHeight * abs(cos(radians))
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10 + 12 * progress, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 10 + 12 * progress, style: .continuous)
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.4), lineWidth: 0.5))
                        .frame(width: 24 + 56 * progress - 8 * compact, height: 132 - 44 * progress - 88 * compact)
                        .offset(x: 8, y: 6 + 6 * progress)

                    ForEach([0, 2, 1], id: \.self) { index in
                        if let image = NSImage(named: Self.artworkNames[index]) {
                            thumbnail(image, at: index)
                        }
                    }

                    Capsule()
                        .fill(Color(nsColor: .secondaryLabelColor).opacity(isHovered ? 0.65 : 0.42))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                        .frame(width: 4, height: 39 - 17 * compact)
                        .offset(x: 1, y: 53 - 36 * compact)
                        .opacity(1 - progress)
                }
                .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
                .scaleEffect(x: motion.dockEdge == .left ? -1 : 1, y: 1)
                .rotationEffect(.degrees(rotation))
                .frame(width: rotatedWidth, height: rotatedHeight)
                .scaleEffect(x: geometry.size.width / rotatedWidth, y: geometry.size.height / rotatedHeight)
                // The whole handle stays clickable while the overlapping cards morph.
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0; onHoverChanged?($0) }
        .help(L10n.text("magnetic.expandCount", count))
        .accessibilityLabel(L10n.text("magnetic.expandCount", count))
    }

    private func thumbnail(_ image: NSImage, at index: Int) -> some View {
        let middle = index == 1
        let progress = motion.progress
        let compact = motion.compactProgress * (1 - progress)
        // Keep the entire rounded rim inside the panel instead of cutting its right corners flat.
        let edgeWidth: CGFloat = middle ? 26 : (index == 0 ? 22 : 21)
        let edgeHeight: CGFloat = middle ? 46 : 44
        let edgeX: CGFloat = middle ? 5 : (index == 0 ? 9 : 10)
        let width = edgeWidth + ((middle ? 60 : 56) - edgeWidth) * progress
            + ((middle ? 18 : 16) - edgeWidth) * compact
        let height = edgeHeight + ((middle ? 76 : 72) - edgeHeight) * progress + (36 - edgeHeight) * compact
        let x = edgeX + ([14, 18, 26][index] - edgeX) * progress
            + ([7, 4, 8][index] - edgeX) * compact - motion.pull * (middle ? 2 : 1)
        let edgeY: CGFloat = [8, 49, 92][index]
        let y = edgeY + ([17, 18, 23][index] - edgeY) * progress + ([9, 10, 12][index] - edgeY) * compact
        let edgeAngle: Double = [-1.2, 1, -0.7][index]
        let angle = edgeAngle + ([-10, 0, 10][index] - edgeAngle) * Double(progress)
            + ([-6, 0, 6][index] - edgeAngle) * Double(compact)
        return Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width - 3, height: height - 3)
            .clipShape(RoundedRectangle(cornerRadius: 6.5 + 3 * progress, style: .continuous))
            .padding(1.5)
            .background(Color(nsColor: .windowBackgroundColor).opacity(isHovered ? 0.98 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8 + 3 * progress, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8 + 3 * progress, style: .continuous).strokeBorder(.white.opacity(colorScheme == .dark ? 0.25 : 0.45), lineWidth: 0.5))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.16), radius: 1.5 + 2 * progress, x: -0.5, y: 1 + progress)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }
}

struct MagneticFanPagerView: View {
    let first: Int
    let last: Int
    let total: Int
    let page: Int
    let pageCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.up").frame(width: 24, height: 24)
            }.clickCursor()
            .buttonStyle(.plain)
            .help(L10n.text("magnetic.previousGroup"))
            .accessibilityLabel(L10n.text("magnetic.previousGroup"))
            .disabled(page == 0)
            Text(L10n.text("magnetic.pageRange", first, last, total))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            Button(action: onNext) {
                Image(systemName: "chevron.down").frame(width: 24, height: 24)
            }.clickCursor()
            .buttonStyle(.plain)
            .help(L10n.text("magnetic.nextGroup"))
            .accessibilityLabel(L10n.text("magnetic.nextGroup"))
            .disabled(page + 1 >= pageCount)
        }
        .padding(.horizontal, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
    }
}

struct MagneticBoxContents: View {
    let items: [HistoryItem]
    let historyStore: HistoryStore
    let onRetrieve: (HistoryItem) -> Void
    let onHover: (HistoryItem, Bool) -> Void
    let onClose: () -> Void
    var page: Int = 0
    var onPageChange: (Int) -> Void = { _ in }

    private var pageCount: Int { max(1, (items.count + 19) / 20) }
    private var safePage: Int { min(max(page, 0), pageCount - 1) }
    private var pageItems: [HistoryItem] { Array(items.dropFirst(safePage * 20).prefix(20)) }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(110, geometry.size.width - 32)
            let columnCount = max(1, Int((availableWidth + 12) / 122))
            let rowCount = max(1, (pageItems.count + columnCount - 1) / columnCount)
            let availableHeight = max(0, geometry.size.height - 32 - 36 - 32 - 24)
            let thumbnailHeight = max(28, min(90,
                (availableHeight - CGFloat(rowCount - 1) * 12) / CGFloat(rowCount) - 40))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L10n.text("magnetic.collectionTitle", items.count), systemImage: "archivebox")
                        .font(.headline)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").frame(width: 24, height: 24).contentShape(Rectangle())
                    }.clickCursor()
                    .buttonStyle(.plain)
                    .help(L10n.text("common.close"))
                    .accessibilityLabel(L10n.text("common.close"))
                    .keyboardShortcut(.cancelAction)
                }
                if items.isEmpty {
                    ContentUnavailableView(L10n.text("magnetic.emptyBox"), systemImage: "archivebox")
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 110), spacing: 12),
                                                 count: columnCount), spacing: 12) {
                            ForEach(pageItems) { item in
                                MagneticBoxThumbnail(item: item, historyStore: historyStore,
                                    thumbnailHeight: thumbnailHeight,
                                    onRetrieve: { onRetrieve(item) }, onHover: { onHover(item, $0) })
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button { onPageChange(max(0, safePage - 1)) } label: {
                            Image(systemName: "chevron.left").frame(width: 24, height: 24)
                        }.clickCursor()
                        .buttonStyle(.plain)
                        .help(L10n.text("magnetic.previousPage"))
                        .accessibilityLabel(L10n.text("magnetic.previousPage"))
                        .disabled(safePage == 0)
                        Text(L10n.text("magnetic.pageRange", safePage * 20 + 1,
                                       min(items.count, (safePage + 1) * 20), items.count))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .frame(maxWidth: .infinity)
                        Button { onPageChange(min(pageCount - 1, safePage + 1)) } label: {
                            Image(systemName: "chevron.right").frame(width: 24, height: 24)
                        }.clickCursor()
                        .buttonStyle(.plain)
                        .help(L10n.text("magnetic.nextPage"))
                        .accessibilityLabel(L10n.text("magnetic.nextPage"))
                        .disabled(safePage + 1 >= pageCount)
                        if pageCount > 1 {
                            Picker("", selection: Binding(get: { safePage }, set: { onPageChange($0) })) {
                                ForEach(0..<pageCount, id: \.self) { pageIndex in
                                    Text(L10n.text("magnetic.collectionPage", pageIndex + 1, pageCount))
                                        .tag(pageIndex)
                                }
                            }.clickCursor()
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 80)
                            .help(L10n.text("magnetic.collectionPage", safePage + 1, pageCount))
                            .accessibilityLabel(L10n.text("magnetic.collectionPage", safePage + 1, pageCount))
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)).allowsHitTesting(false))
        }
    }
}

final class MagneticBoxContentsHostingView: MagneticPassiveHostingView<MagneticBoxContents> {
    private var routingScroll = false

    private func embeddedScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.embeddedScrollView(in: $0) }.first
    }

    override func scrollWheel(with event: NSEvent) {
        // AppKit can forward a wheel at the end of the document back to this responder.
        // Consume it here, including wheels over padding, rather than passing it to another window.
        guard !routingScroll else { return }
        guard let scroll = embeddedScrollView(in: self) else { return }
        routingScroll = true
        defer { routingScroll = false }
        scroll.scrollWheel(with: event)
    }
}

private struct MagneticBoxThumbnail: View {
    let item: HistoryItem
    let historyStore: HistoryStore
    var thumbnailHeight: CGFloat = 90
    let onRetrieve: () -> Void
    let onHover: (Bool) -> Void
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Button(action: onRetrieve) {
                    VStack(spacing: 6) {
                        Image(nsImage: image).resizable().scaledToFit().frame(height: thumbnailHeight)
                        Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(8).frame(maxWidth: .infinity)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }.clickCursor()
        .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("magnetic.locate"))
                .onHover(perform: onHover)
                .onDisappear { onHover(false) }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity).frame(height: thumbnailHeight + 27)
            }
        }
        .task(id: item.id) {
            image = await historyStore.thumbnail(for: item)
            isLoading = false
        }
    }
}
