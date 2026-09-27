import Foundation
import CoreGraphics

struct ScrollCaptureFrameOrder {
    private var latestTimestamp: TimeInterval = -.infinity

    mutating func accept(timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite, timestamp >= latestTimestamp else { return false }
        latestTimestamp = timestamp
        return true
    }
}

struct ScrollCaptureFrameObservation: Sendable {
    let timestamp: TimeInterval
    let pixelHeight: Int
    let result: ScrollCaptureAppendResult
}

struct ScrollCaptureAutoScroll {
    enum PauseReason: String, Sendable {
        case unmatched, stalled, noMovement, targetChanged, user
    }
    enum Action: Equatable {
        case wait, scroll(Int), finish, pause(PauseReason)
    }

    private(set) var isPaused = false
    private var latest: ScrollCaptureFrameObservation?
    private var lastChange: TimeInterval = 0
    private var stepStarted: TimeInterval?
    private var baselineHeight = 0
    private var stepMoved = false
    private var everMoved = false
    private var bottomProbes = 0
    private var started: TimeInterval
    let stepPoints: Int

    init(viewportHeight: Double, now: TimeInterval) {
        stepPoints = max(1, min(100, Int(viewportHeight * 0.15)))
        started = now
    }

    static func scrollEvent(points: Int) -> CGEvent? {
        // Keep Quartz's current pointer location: overriding it moves the cursor
        // when the event passes through WindowServer's input routing.
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: -Int32(points), wheel2: 0, wheel3: 0)
    }

    mutating func observe(_ observation: ScrollCaptureFrameObservation) {
        // Frames queued before our command cannot acknowledge its effect.
        guard observation.timestamp >= (stepStarted ?? started),
              observation.timestamp >= (latest?.timestamp ?? 0) else { return }
        if latest == nil || observation.result != .duplicate { lastChange = observation.timestamp }
        latest = observation
        let movedWithinCapture: Bool
        if case .revisited = observation.result { movedWithinCapture = true }
        else { movedWithinCapture = false }
        if stepStarted != nil, observation.pixelHeight > baselineHeight || movedWithinCapture {
            stepMoved = true
            everMoved = true
            bottomProbes = 0
        }
    }

    mutating func tick(now: TimeInterval) -> Action {
        guard !isPaused else { return .wait }
        guard let latest else {
            return now - started >= 4 ? pause(.stalled) : .wait
        }
        let waitingSince = stepStarted ?? started
        if case .limitReached = latest.result { return pause(.stalled) }
        if now - waitingSince >= 4 {
            return pause(latest.result == .unmatched ? .unmatched : .stalled)
        }
        // A fresh unchanged frame is the barrier: matching and rendering must both
        // settle before another command. An elapsed timer alone never advances us.
        guard latest.result == .duplicate, now - latest.timestamp <= 0.5,
              latest.timestamp - lastChange >= 0.18 else { return .wait }
        if let stepStarted, !stepMoved {
            let probeWait = [0.7, 1.1, 1.8][min(bottomProbes, 2)]
            guard latest.timestamp - stepStarted >= probeWait else { return .wait }
            bottomProbes += 1
            if bottomProbes >= 3 {
                if everMoved { isPaused = true; return .finish }
                return pause(.noMovement)
            }
        }
        baselineHeight = latest.pixelHeight
        stepMoved = false
        stepStarted = now
        return .scroll(stepPoints)
    }

    @discardableResult
    mutating func pause(_ reason: PauseReason) -> Action {
        isPaused = true
        return .pause(reason)
    }

    mutating func resume(now: TimeInterval) {
        isPaused = false
        started = now
        latest = nil
        stepStarted = nil
        stepMoved = false
        bottomProbes = 0
    }
}
