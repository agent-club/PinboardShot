import AppKit
import SwiftUI

struct MagneticDesktopPreferences: View {
    @AppStorage(MagneticDesktopSettings.enabledKey) private var enabled = false
    @AppStorage(MagneticDesktopSettings.maximumVisibleKey) private var maximumVisible = MagneticDesktopSettings.defaultMaximumVisible
    @AppStorage(HistorySettings.enabledDefaultsKey) private var historyEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.text("magnetic.enabled"), isOn: $enabled).clickCursor()
            HStack {
                Stepper(value: $maximumVisible, in: MagneticDesktopSettings.supportedLimits) {
                    Text(L10n.text("magnetic.maximum", maximumVisible))
                }
                .disabled(!enabled)
                Text("1–10").font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("magnetic.help"))
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

struct MagneticFanMotionView: View {
    @ObservedObject var motion: MagneticFanMotion
    let screenFrame: CGRect
    let pivot: CGPoint

    var body: some View {
        Canvas { context, _ in
            let hinge = CGPoint(x: pivot.x - screenFrame.minX, y: screenFrame.maxY - pivot.y)
            for (index, leaf) in motion.leaves.enumerated().reversed() {
                let delay = 0.14 * CGFloat(index) / CGFloat(max(1, motion.leaves.count - 1))
                let progress = min(1, max(0, (motion.progress - delay) / (1 - delay)))
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
                        CGPoint(x: flight.start.x + (flight.end.x - flight.start.x) * progress - screenFrame.minX,
                                y: screenFrame.maxY - flight.start.y - (flight.end.y - flight.start.y) * progress)
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
            .overlay {
                if motion.progress > 0 && motion.progress < 1 {
                    GeometryReader { geometry in
                        LinearGradient(colors: [.clear, .cyan.opacity(0.25), .white.opacity(0.8), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 0.45)
                            .rotationEffect(.degrees(-18))
                            .offset(x: geometry.size.width * (motion.progress * 1.6 - 0.5))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .allowsHitTesting(false)
                }
            }
            .rotation3DEffect(.degrees(motion.progress >= 1 ? 0 : Double(motion.progress) * 360 * (motion.direction == .outward ? -1 : 1)),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.35)
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
                        .offset(x: sin(motion.progress * .pi * 8) * 2 * (1 - motion.progress),
                                y: -sin(motion.progress * .pi) * 2)
                        .rotationEffect(.degrees(Double(sin(motion.progress * .pi * 6) * 2 * (1 - motion.progress))))
                        .scaleEffect(1 + sin(motion.progress * .pi) * 0.015)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
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
                    .rotationEffect(.degrees([-8, 6, -3, 9, 1][index] * (isHovering ? 1.08 : 1)))
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

struct MagneticFoldedView: View {
    let count: Int
    let onExpand: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: onExpand) {
            GeometryReader { geometry in
                ZStack {
                    foldedFan
                    Text(count.formatted(.number.grouping(.never)))
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.96, green: 0.94, blue: 0.88))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(width: geometry.size.width * 0.53, height: geometry.size.height * 0.08)
                        .position(x: geometry.size.width * 0.74, y: geometry.size.height * 0.91)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                // Paper folds change their highlights, never the passive panel's click region.
                .contentShape(Rectangle())
            }
        }.clickCursor()
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(L10n.text("magnetic.expandCount", count))
        .accessibilityLabel(L10n.text("magnetic.expandCount", count))
    }

    private var foldedFan: some View {
        Canvas { context, size in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * size.width / 32, y: y * size.height / 144)
            }
            func polygon(_ vertices: [(CGFloat, CGFloat)]) -> Path {
                Path { path in
                    path.move(to: point(vertices[0].0, vertices[0].1))
                    for vertex in vertices.dropFirst() { path.addLine(to: point(vertex.0, vertex.1)) }
                    path.closeSubpath()
                }
            }
            let dark = colorScheme == .dark
            let edge = Color(red: 0.27, green: 0.28, blue: 0.28)
            let sheath = polygon([(29, 5), (32, 3), (32, 141), (29, 141)])
            context.fill(sheath, with: .linearGradient(Gradient(colors: [edge, .black.opacity(0.85)]),
                startPoint: point(29, 0), endPoint: point(32, 0)))

            // Converging facets preserve the near-closed fan silhouette at desktop scale.
            let tips: [(CGFloat, CGFloat)] = [(30, 7), (24, 19), (17, 37), (10, 59), (5, 81), (11, 108)]
            let pivot = point(27, 119)
            for index in 0..<5 {
                let face = polygon([tips[index], tips[index + 1], (27, 119)])
                let shade = Double(index) * 0.016 + (dark ? 0.045 : 0)
                let highlight = isHovered ? 0.035 : 0
                let paper = Color(red: 0.94 - shade + highlight,
                                  green: 0.92 - shade + highlight, blue: 0.86 - shade + highlight)
                let fold = Color(red: 0.74 - shade, green: 0.72 - shade, blue: 0.67 - shade)
                context.fill(face, with: .linearGradient(Gradient(colors: [paper, paper, fold]),
                    startPoint: point(tips[index].0, tips[index].1),
                    endPoint: point(tips[index + 1].0, tips[index + 1].1)))
                context.stroke(face, with: .color(edge.opacity(0.45)), lineWidth: 0.45)
                var crease = Path()
                crease.move(to: point(tips[index + 1].0 + 0.5, tips[index + 1].1))
                crease.addLine(to: pivot)
                context.stroke(crease, with: .color(.white.opacity(dark ? 0.35 : 0.65)), lineWidth: 0.5)
            }
            var accent = Path()
            accent.move(to: point(24, 21)); accent.addLine(to: point(27, 114))
            context.stroke(accent, with: .color(Color(red: 0.79, green: 0.36, blue: 0.24)
                .opacity(isHovered ? 0.95 : 0.7)), lineWidth: 1)

            let cap = Path { path in
                path.move(to: point(27, 110))
                path.addLine(to: point(31, 110))
                path.addLine(to: point(31, 141))
                path.addQuadCurve(to: point(27, 142), control: point(30, 144))
                path.addLine(to: point(17, 130))
                path.addQuadCurve(to: point(17, 118), control: point(12, 123))
                path.addLine(to: point(23, 112))
                path.addQuadCurve(to: point(27, 110), control: point(25, 110))
                path.closeSubpath()
            }
            let capLight = isHovered ? Color(red: 0.27, green: 0.32, blue: 0.36)
                                     : Color(red: 0.20, green: 0.25, blue: 0.29)
            context.fill(cap, with: .linearGradient(Gradient(colors: [capLight,
                Color(red: 0.10, green: 0.14, blue: 0.18)]),
                startPoint: point(16, 115), endPoint: point(32, 140)))
            context.stroke(cap, with: .color(.black.opacity(0.7)), lineWidth: 0.6)
            var rim = Path()
            rim.move(to: point(28, 111)); rim.addLine(to: point(24, 113)); rim.addLine(to: point(18, 119))
            context.stroke(rim, with: .color(.white.opacity(isHovered ? 0.4 : 0.22)), lineWidth: 0.5)
            let rivet = CGRect(x: size.width * 23.5 / 32, y: size.height * 115 / 144,
                               width: size.width * 3 / 32, height: size.height * 3 / 144)
            context.fill(Path(ellipseIn: rivet), with: .color(Color(red: 0.68, green: 0.60, blue: 0.43)))
            context.stroke(Path(ellipseIn: rivet.insetBy(dx: 0.7, dy: 0.7)),
                           with: .color(.black.opacity(0.8)), lineWidth: 0.6)
        }
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
