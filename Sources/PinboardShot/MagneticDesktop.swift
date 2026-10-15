import AppKit
import Foundation

enum MagneticAnimationStyle: String, CaseIterable {
    case full, simple
}

struct MagneticDesktopSettings: Equatable {
    static let enabledKey = "magneticDesktopEnabled"
    static let maximumVisibleKey = "magneticDesktopMaximumVisible"
    static let collapsedKey = "magneticDesktopCollapsed"
    static let animationStyleKey = "magneticDesktopAnimationStyle"
    static let reduceMotionKey = "magneticDesktopReduceMotion"
    static let defaultMaximumVisible = 10
    static let supportedLimits = 1...100
    static let maximumCardsPerGroup = 10

    let isEnabled: Bool
    let maximumVisible: Int
    let isCollapsed: Bool
    let animationStyle: MagneticAnimationStyle
    let reduceMotion: Bool

    init(defaults: UserDefaults = .standard) {
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        isCollapsed = defaults.bool(forKey: Self.collapsedKey)
        animationStyle = MagneticAnimationStyle(rawValue: defaults.string(forKey: Self.animationStyleKey) ?? "") ?? .full
        reduceMotion = defaults.bool(forKey: Self.reduceMotionKey)
        let stored = defaults.object(forKey: Self.maximumVisibleKey) as? Int
        maximumVisible = stored.map { min(max($0, Self.supportedLimits.lowerBound), Self.supportedLimits.upperBound) }
            ?? Self.defaultMaximumVisible
    }
}

struct MagneticDesktopQueue {
    private(set) var recentIDs: [UUID] = []
    private(set) var retrievedID: UUID?
    private(set) var pageIndex = 0
    private var railReturns: [UUID] = []
    private var boxReturns: Set<UUID> = []

    mutating func synchronize(_ ids: [UUID]) {
        // Retrieval is temporary display priority; a new capture restores chronological order.
        let newestChanged = ids.first != recentIDs.first
        if newestChanged || (retrievedID != nil && !ids.contains(where: { $0 == retrievedID })) {
            retrievedID = nil
        }
        if newestChanged { railReturns.removeAll(); pageIndex = 0 }
        var seen = Set<UUID>()
        recentIDs = ids.filter { seen.insert($0).inserted }
        railReturns.removeAll { !seen.contains($0) }
        boxReturns.formIntersection(seen)
    }

    mutating func retrieve(_ id: UUID) {
        guard recentIDs.contains(id) else { return }
        retrievedID = id
        pageIndex = 0
        boxReturns.remove(id)
    }

    mutating func returnToRail(_ id: UUID) {
        guard recentIDs.contains(id) else { return }
        boxReturns.remove(id)
        railReturns.removeAll { $0 == id }
        railReturns.insert(id, at: 0)
        pageIndex = 0
    }

    mutating func returnToBox(_ id: UUID) {
        guard recentIDs.contains(id) else { return }
        railReturns.removeAll { $0 == id }
        if retrievedID == id { retrievedID = nil }
        boxReturns.insert(id)
    }

    mutating func returnToEdge() { retrievedID = nil; railReturns.removeAll(); pageIndex = 0 }

    func railIDs(excluding desktopIDs: Set<UUID> = []) -> [UUID] {
        let priority = railReturns + (retrievedID.map { [$0] } ?? [])
        var seen = Set<UUID>()
        return (priority + recentIDs).filter {
            !desktopIDs.contains($0) && !boxReturns.contains($0) && seen.insert($0).inserted
        }
    }

    func fanIDs(limit: Int, excluding desktopIDs: Set<UUID> = []) -> [UUID] {
        // The preference limits the fan's collection; screenshots outside it belong only to the box.
        Array(railIDs(excluding: desktopIDs).prefix(max(1, limit)))
    }

    mutating func setPage(_ page: Int, limit: Int, excluding desktopIDs: Set<UUID> = []) {
        let count = fanIDs(limit: limit, excluding: desktopIDs).count
        let size = MagneticDesktopSettings.maximumCardsPerGroup
        pageIndex = min(max(0, page), max(0, (count - 1) / size))
    }

    mutating func locate(_ id: UUID, limit: Int, excluding desktopIDs: Set<UUID> = []) {
        guard recentIDs.contains(id), !desktopIDs.contains(id) else { return }
        boxReturns.remove(id)
        retrievedID = nil
        if let index = fanIDs(limit: limit, excluding: desktopIDs).firstIndex(of: id) {
            pageIndex = index / MagneticDesktopSettings.maximumCardsPerGroup
        } else {
            // Locating a boxed screenshot promotes it into the bounded fan without expanding the capacity.
            retrievedID = id
            pageIndex = 0
        }
    }

    func partition(limit: Int, excluding desktopIDs: Set<UUID> = []) -> (visible: [UUID], boxed: [UUID]) {
        let ordered = railIDs(excluding: desktopIDs)
        let fan = fanIDs(limit: limit, excluding: desktopIDs)
        let size = MagneticDesktopSettings.maximumCardsPerGroup
        let page = min(pageIndex, max(0, (fan.count - 1) / size))
        let visible = Array(fan.dropFirst(page * size).prefix(size))
        let fanMembers = Set(fan)
        return (visible, ordered.filter { !fanMembers.contains($0) } + recentIDs.filter {
            boxReturns.contains($0) && !desktopIDs.contains($0)
        })
    }
}

enum MagneticCardHome: String, Codable, Sendable { case rail, box }

struct MagneticPinSource: Codable, Equatable, Sendable {
    let historyItemID: UUID
    let home: MagneticCardHome
}

enum MagneticDesktopPlacement {
    static let gap: CGFloat = 12

    static func frame(size: CGSize, near point: CGPoint, occupied: [CGRect], in bounds: CGRect) -> CGRect? {
        guard size.width > 0, size.height > 0, size.width <= bounds.width, size.height <= bounds.height else { return nil }
        var xs = [bounds.minX, bounds.maxX - size.width, point.x - size.width / 2]
        var ys = [bounds.minY, bounds.maxY - size.height, point.y - size.height / 2]
        for other in occupied {
            xs += [other.minX - size.width - gap, other.maxX + gap]
            ys += [other.minY - size.height - gap, other.maxY + gap]
        }
        let xPositions = Set(xs.map { min(max($0.rounded(.down), bounds.minX), bounds.maxX - size.width) })
        let yPositions = Set(ys.map { min(max($0.rounded(.down), bounds.minY), bounds.maxY - size.height) })
        let candidates = xPositions.flatMap { x in yPositions.map { y in CGRect(origin: CGPoint(x: x, y: y), size: size) } }
        return candidates.filter { candidate in
            bounds.contains(candidate) && occupied.allSatisfy { !candidate.intersects($0.insetBy(dx: -gap, dy: -gap)) }
        }.min { lhs, rhs in
            let left = pow(lhs.midX - point.x, 2) + pow(lhs.midY - point.y, 2)
            let right = pow(rhs.midX - point.x, 2) + pow(rhs.midY - point.y, 2)
            if left != right { return left < right }
            return lhs.minY == rhs.minY ? lhs.minX < rhs.minX : lhs.minY > rhs.minY
        }
    }

    static func centeredGroup(_ preferred: [UUID: CGRect], fixed: [CGRect], in bounds: CGRect) -> [UUID: CGRect]? {
        guard !preferred.isEmpty, bounds.width > 0, bounds.height > 0,
              bounds.minX.isFinite, bounds.minY.isFinite, bounds.maxX.isFinite, bounds.maxY.isFinite else { return nil }
        let frames = Array(preferred.values)
        guard frames.allSatisfy({
            $0.width > 0 && $0.height > 0 &&
            $0.minX.isFinite && $0.minY.isFinite && $0.maxX.isFinite && $0.maxY.isFinite
        }), fixed.allSatisfy({
            $0.width > 0 && $0.height > 0 &&
            $0.minX.isFinite && $0.minY.isFinite && $0.maxX.isFinite && $0.maxY.isFinite
        }) else { return nil }

        var group = frames[0].standardized
        for frame in frames.dropFirst() { group = group.union(frame.standardized) }
        guard group.width <= bounds.width, group.height <= bounds.height else { return nil }

        let minDX = bounds.minX - group.minX
        let maxDX = bounds.maxX - group.maxX
        let minDY = bounds.minY - group.minY
        let maxDY = bounds.maxY - group.maxY
        let centeredDX = min(max(bounds.midX - group.midX, minDX), maxDX)
        let centeredDY = min(max(bounds.midY - group.midY, minDY), maxDY)
        var xOffsets: Set<CGFloat> = [centeredDX]
        var yOffsets: Set<CGFloat> = [centeredDY]

        // A conservative group envelope keeps obstacle search bounded without packing individual cards.
        func isSafe(_ dx: CGFloat, _ dy: CGFloat) -> Bool {
            let moved = group.offsetBy(dx: dx, dy: dy)
            return bounds.contains(moved) && fixed.allSatisfy { obstacle in
                !moved.intersects(obstacle.standardized.insetBy(dx: -gap, dy: -gap))
            }
        }

        if isSafe(0, 0) {
            xOffsets.insert(0)
            yOffsets.insert(0)
        }
        for obstacle in fixed.map({ $0.standardized }) {
            xOffsets.insert(obstacle.minX - gap - group.maxX)
            xOffsets.insert(obstacle.maxX + gap - group.minX)
            yOffsets.insert(obstacle.minY - gap - group.maxY)
            yOffsets.insert(obstacle.maxY + gap - group.minY)
        }

        let candidates = xOffsets.flatMap { dx in yOffsets.map { dy in (dx, dy) } }
        guard let translation = candidates.filter({ isSafe($0.0, $0.1) }).min(by: { lhs, rhs in
            let left = pow(group.midX + lhs.0 - bounds.midX, 2) + pow(group.midY + lhs.1 - bounds.midY, 2)
            let right = pow(group.midX + rhs.0 - bounds.midX, 2) + pow(group.midY + rhs.1 - bounds.midY, 2)
            if left != right { return left < right }
            return lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
        }) else { return nil }

        return preferred.mapValues { $0.offsetBy(dx: translation.0, dy: translation.1) }
    }

    static func reflow(_ preferred: [UUID: CGRect], fixed: [CGRect], in bounds: CGRect) -> [UUID: CGRect]? {
        let ordered = preferred.sorted {
            let first = $0.value, second = $1.value
            let left = first.width * first.height, right = second.width * second.height
            return left == right ? $0.key.uuidString < $1.key.uuidString : left > right
        }.map(\.key)
        // Repack only when a new card cannot fit; existing user placements win in the normal case.
        for scale in stride(from: 1.0, through: 0.2, by: -0.08) {
            var occupied = fixed
            var result: [UUID: CGRect] = [:]
            for id in ordered {
                guard let original = preferred[id] else { continue }
                let factor = max(scale, 80 / original.width, 60 / original.height)
                let size = CGSize(width: (original.width * factor).rounded(.down),
                                  height: (original.height * factor).rounded(.down))
                guard let pose = frame(size: size, near: CGPoint(x: original.midX, y: original.midY),
                                       occupied: occupied, in: bounds) else { break }
                result[id] = pose
                occupied.append(pose)
            }
            if result.count == preferred.count { return result }
        }
        return nil
    }
}

struct MagneticDragVelocity {
    private var samples: [(point: CGPoint, time: TimeInterval)] = []

    mutating func record(_ point: CGPoint, at time: TimeInterval) {
        samples.append((point, time))
        // A pause before release cancels momentum; old movement must not cause a surprise return.
        samples.removeAll { time - $0.time > 0.12 }
        if samples.count > 16 { samples.removeFirst(samples.count - 16) }
    }

    var velocity: CGPoint {
        guard let first = samples.first, let last = samples.last, last.time - first.time >= 0.016 else { return .zero }
        let duration = last.time - first.time
        return CGPoint(x: (last.point.x - first.point.x) / duration, y: (last.point.y - first.point.y) / duration)
    }
}

enum MagneticDesktopThrow {
    static func shouldReturn(card: CGRect, velocity: CGPoint, screen: CGRect) -> Bool {
        // A card on another display must not count as being past this display's magnetic edge.
        guard screen.contains(CGPoint(x: card.midX, y: card.midY)) else { return false }
        if card.maxX >= screen.maxX - 36 { return true }
        // Require a deliberate rightward throw whose projected coast reaches the magnet zone.
        return velocity.x >= 850 && abs(velocity.y) < velocity.x * 0.85
            && card.maxX + velocity.x * 0.30 >= screen.maxX - 80
    }

    static func settledFrame(_ card: CGRect, velocity: CGPoint, screen: CGRect) -> CGRect {
        let coast = CGPoint(x: min(max(velocity.x * 0.10, -100), 100), y: min(max(velocity.y * 0.10, -100), 100))
        let projected = card.offsetBy(dx: coast.x, dy: coast.y)
        return PinWindowVisibleGeometry.constrainedFrame(
            CGRect(x: projected.minX.rounded(.down), y: projected.minY.rounded(.down),
                   width: projected.width, height: projected.height), visibleFrames: [screen])
    }
}

enum MagneticDesktopGeometry {
    static let cardSize = CGSize(width: 128, height: 76)
    // Keep room for the photo stack and its arrival bounce beneath the draggable header.
    static let boxSize = CGSize(width: 180, height: 134)

    static func screenFrame(for card: CGRect, in frames: [CGRect]) -> CGRect? {
        let constrained = PinWindowVisibleGeometry.constrainedFrame(card, visibleFrames: frames)
        return frames.first { $0.contains(constrained) }
    }

    static func boxFrame(in visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: min(boxSize.width, visibleFrame.width), height: min(boxSize.height, visibleFrame.height))
        return CGRect(x: visibleFrame.maxX - size.width - min(12, max(0, visibleFrame.width - size.width)),
                      y: visibleFrame.minY + min(12, max(0, visibleFrame.height - size.height)),
                      width: size.width, height: size.height)
    }

    struct CardLayout {
        let frame: CGRect
        let column: Int
        let angle: Double
    }

    static func cardFrames(count: Int, in visibleFrame: CGRect) -> [CGRect] {
        cardLayouts(count: count, in: visibleFrame).map(\.frame)
    }

    static func cardLayouts(count: Int, in visibleFrame: CGRect) -> [CardLayout] {
        guard count > 0, visibleFrame.width > 0, visibleFrame.height > 0 else { return [] }
        let width = min(cardSize.width, visibleFrame.width)
        let height = min(cardSize.height, visibleFrame.height)
        // Reserve a fixed gap for the pager so changing groups never moves or covers the tray.
        let bottom = min(visibleFrame.maxY - height, boxFrame(in: visibleFrame).maxY + 52)
        let top = max(bottom, visibleFrame.maxY - height - 12)
        // Add columns on short displays instead of compressing every card into a thin strip.
        let rows = max(1, Int((top - bottom) / 52) + 1)
        let columns = max(1, Int(ceil(Double(count) / Double(rows))))
        let depth = min(48, max(0, visibleFrame.width - width - 24))
        let columnStep = columns > 1
            ? min(width + depth + 12, max(0, (visibleFrame.width - width - depth - 24) / CGFloat(columns - 1))) : 0
        return (0..<count).map { index in
            let column = index / rows, row = index % rows
            let columnCount = min(rows, count - column * rows)
            let centeredHeight = max(0, min(visibleFrame.midY - bottom, top + height - visibleFrame.midY) * 2)
            let gap: CGFloat = columnCount >= 5 && centeredHeight < height * CGFloat(columnCount) + 10 * CGFloat(columnCount - 1) ? 6 : 10
            // Shrink dense groups proportionally before letting pictures overlap or hiding corner timestamps.
            let fittedHeight = min(height, max(36, (centeredHeight - gap * CGFloat(columnCount - 1)) / CGFloat(columnCount)))
            let fittedWidth = width * fittedHeight / height
            let step = columnCount > 1
                ? min(fittedHeight + gap, (visibleFrame.maxY - fittedHeight - 12 - bottom) / CGFloat(columnCount - 1)) : 0
            let span = CGFloat(columnCount - 1) * step
            let groupBottom = min(max(visibleFrame.midY - (fittedHeight + span) / 2, bottom),
                                  visibleFrame.maxY - fittedHeight - 12 - span)
            let position = columnCount > 1 ? CGFloat(row) / CGFloat(columnCount - 1) * 2 - 1 : 0
            let fanned = columnCount >= 2
            let arcScale: CGFloat = columnCount <= 3 ? 0.35 : columnCount == 4 ? 0.6 : 1
            let tiltScale: Double = columnCount <= 3 ? 0.45 : columnCount == 4 ? 0.7 : 1
            // The fixed hit windows follow the same shallow arc as the pictures; hover never changes them.
            let inset = fanned ? depth * arcScale * (1 - position * position) : 0
            let frame = CGRect(x: max(visibleFrame.minX, (visibleFrame.maxX - fittedWidth - 12 - CGFloat(column) * columnStep - inset).rounded(.down)),
                               y: max(bottom, (groupBottom + span - CGFloat(row) * step).rounded(.down)),
                               width: fittedWidth, height: fittedHeight)
            return CardLayout(frame: frame, column: column, angle: fanned ? -Double(position) * 7 * tiltScale : 0)
        }
    }

    static func pagerFrame(beside cards: [CGRect], in screen: CGRect) -> CGRect {
        let bottom = cards.map(\.minY).min() ?? screen.midY
        return PinWindowVisibleGeometry.constrainedFrame(
            CGRect(x: screen.maxX - 172, y: bottom - 40, width: min(160, screen.width), height: 32),
            visibleFrames: [screen])
    }

    static func expandedFrame(imageSize: CGSize, near point: CGPoint, in visibleFrame: CGRect) -> CGRect {
        let ratio = imageSize.width / max(1, imageSize.height)
        let width = min(420, visibleFrame.width * 0.6).rounded(.down)
        let height = min(max(60, width / max(0.1, ratio)), visibleFrame.height * 0.7).rounded(.down)
        // AppKit rounds window origins; save the same integral pose to prevent drift on refresh.
        return PinWindowVisibleGeometry.constrainedFrame(
            CGRect(x: (point.x - width / 2).rounded(.down), y: (point.y - height / 2).rounded(.down), width: width, height: height),
            visibleFrames: [visibleFrame]
        )
    }

    static func hoverFrame(for card: CGRect, beside rail: [CGRect], in visibleFrame: CGRect) -> CGRect {
        let leftEdge = rail.reduce(card) { $0.union($1) }.minX
        // Clear the entire fan, including other columns, so the preview never hides a pointer target.
        let width = min(210, max(0, leftEdge - 12 - visibleFrame.minX))
        let height = min(160 * width / 210, visibleFrame.height)
        return PinWindowVisibleGeometry.constrainedFrame(
            CGRect(x: leftEdge - 12 - width, y: card.midY - height / 2, width: width, height: height),
            visibleFrames: [visibleFrame]
        )
    }

    static func foldedFrame(in visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: min(32, visibleFrame.width), height: min(144, visibleFrame.height * 0.65))
        return CGRect(x: visibleFrame.maxX - size.width, y: (visibleFrame.midY - size.height / 2).rounded(.down),
                      width: size.width, height: size.height)
    }

    static func hoveredCard(at point: CGPoint, ids: [UUID], frames: [CGRect], excluding expandedID: UUID?) -> UUID? {
        // Match the fixed rail's front-to-back order, independent of the enlarged preview.
        zip(ids, frames).reversed().first { $0.0 != expandedID && $0.1.contains(point) }?.0
    }
}
