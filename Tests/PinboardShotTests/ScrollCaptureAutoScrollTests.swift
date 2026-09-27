import Testing
import AppKit
@testable import PinboardShot

@Suite("Auto scroll pacing")
struct ScrollCaptureAutoScrollTests {
    @Test("Automatic wheel events retain the current cursor instead of targeting a fixed point")
    func wheelPreservesPointer() throws {
        let before = try #require(CGEvent(source: nil)).location
        let event = try #require(ScrollCaptureAutoScroll.scrollEvent(points: 90))
        let after = try #require(CGEvent(source: nil)).location
        // The real pointer may move during the test; the event must use one of
        // these current positions, never a fixed selection-center coordinate.
        let tolerance = hypot(after.x - before.x, after.y - before.y) + 2
        #expect(hypot(event.location.x - before.x, event.location.y - before.y) <= tolerance)
        #expect(event.type == .scrollWheel)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -90)
    }

    @Test("Active snapshots advance a static window without any idle stream buffers")
    func staticWindowSampling() throws {
        let context = try #require(CGContext(data: nil, width: 80, height: 120,
            bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        let frame = try #require(context.makeImage())
        let observations = Observations()
        let pipeline = ScrollCaptureFramePipeline(onProgress: { _ in },
                                                 onObservation: { observations.append($0) })
        #expect(pipeline.submit(frame, timestamp: 10.01, requiresStableFrame: true))
        #expect(pipeline.submit(frame, timestamp: 10.25, requiresStableFrame: true))
        #expect(pipeline.submit(frame, timestamp: 10.5, requiresStableFrame: true))
        #expect(pipeline.finalImage() != nil)
        var state = ScrollCaptureAutoScroll(viewportHeight: 600, now: 10)
        for observation in observations.values { state.observe(observation) }
        #expect(state.tick(now: 10.51) == .scroll(90))
        pipeline.cancel()
    }

    @Test("A late screenshot cannot replace a newer streaming viewport")
    func snapshotOrder() {
        var order = ScrollCaptureFrameOrder()
        let results = [10, 10.2, 10.1, Double.nan, 10.4].map { order.accept(timestamp: $0) }
        #expect(results == [true, true, false, false, true])
    }

    private final class Observations: @unchecked Sendable {
        private let lock = NSLock()
        private var observations: [ScrollCaptureFrameObservation] = []
        func append(_ value: ScrollCaptureFrameObservation) { lock.withLock { observations.append(value) } }
        var values: [ScrollCaptureFrameObservation] { lock.withLock { observations } }
    }

    @Test("Idle acknowledgements drain behind queued frames and retain unmatched state")
    func pipelineBarrier() throws {
        func frame(_ gray: CGFloat) throws -> CGImage {
            let context = try #require(CGContext(data: nil, width: 80, height: 120,
                bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(gray: gray, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
            return try #require(context.makeImage())
        }
        let observations = Observations()
        let queue = DispatchQueue(label: "PinboardShotTests.auto-barrier")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { gate.signal() }
        let pipeline = ScrollCaptureFramePipeline(processingQueue: queue, onProgress: { _ in },
                                                 onObservation: { observations.append($0) })
        #expect(pipeline.submit(try frame(0), timestamp: 1))
        pipeline.observeIdle(timestamp: 1.3)
        #expect(observations.values.isEmpty)
        gate.signal()
        #expect(pipeline.finalImage() != nil)
        #expect(observations.values.map(\.timestamp) == [1, 1.3])
        #expect(observations.values.map(\.result) == [.initial, .duplicate])
        #expect(pipeline.submit(try frame(1), timestamp: 2))
        pipeline.observeIdle(timestamp: 2.3)
        #expect(pipeline.finalImage() != nil)
        #expect(observations.values.suffix(2).map(\.result) == [.unmatched, .unmatched])
        pipeline.cancel()
        pipeline.observeIdle(timestamp: 3)
        #expect(pipeline.finalImage() != nil)
        #expect(observations.values.count == 4)
    }

    private func observe(_ state: inout ScrollCaptureAutoScroll, _ time: Double,
                         _ result: ScrollCaptureAppendResult = .duplicate, height: Int = 600) {
        state.observe(ScrollCaptureFrameObservation(timestamp: time, pixelHeight: height, result: result))
    }

    @Test("Commands wait for a fresh settled frame and cannot overlap")
    func matchingBarrier() {
        var state = ScrollCaptureAutoScroll(viewportHeight: 600, now: 0)
        observe(&state, 0.01, .initial)
        #expect(state.tick(now: 0.1) == .wait)
        observe(&state, 0.21)
        #expect(state.tick(now: 0.22) == .scroll(90))
        observe(&state, 0.20, .appended(pixelHeight: 90, score: 0), height: 690)
        #expect(state.tick(now: 0.4) == .wait)
        observe(&state, 0.42, .appended(pixelHeight: 90, score: 0), height: 690)
        observe(&state, 0.5, height: 690)
        #expect(state.tick(now: 0.51) == .wait)
        observe(&state, 0.63, height: 690)
        #expect(state.tick(now: 0.64) == .scroll(90))
        #expect(state.tick(now: 0.65) == .wait)
    }

    @Test("A backlog or unmatched view never triggers another scroll")
    func stalledCapture() {
        var state = ScrollCaptureAutoScroll(viewportHeight: 600, now: 0)
        observe(&state, 0.01, .initial)
        observe(&state, 0.21)
        #expect(state.tick(now: 0.22) == .scroll(90))
        observe(&state, 0.3, .appended(pixelHeight: 90, score: 0), height: 690)
        observe(&state, 0.6, height: 690)
        #expect(state.tick(now: 1.2) == .wait)
        observe(&state, 1.3, .unmatched, height: 690)
        observe(&state, 4.3, .unmatched, height: 690)
        #expect(state.tick(now: 4.31) == .pause(.unmatched))
        #expect(state.tick(now: 5) == .wait)
    }

    @Test("Bottom needs three settled probes, while an unscrollable selection pauses")
    func bottomProbes() {
        for moved in [false, true] {
            var state = ScrollCaptureAutoScroll(viewportHeight: 600, now: 0)
            observe(&state, 0.01, .initial)
            observe(&state, 0.21)
            #expect(state.tick(now: 0.22) == .scroll(90))
            let height = moved ? 690 : 600
            if moved {
                observe(&state, 0.3, .appended(pixelHeight: 90, score: 0), height: height)
                observe(&state, 0.51, height: height)
                #expect(state.tick(now: 0.52) == .scroll(90))
            }
            for time in [1.3, 2.5] {
                observe(&state, time, height: height)
                #expect(state.tick(now: time) == .scroll(90))
            }
            observe(&state, 4.4, height: height)
            #expect(state.tick(now: 4.4) == (moved ? .finish : .pause(.noMovement)))
        }
    }

    @Test("Pause stops commands, and resume rejects old frames")
    func pauseResume() {
        var state = ScrollCaptureAutoScroll(viewportHeight: 40, now: 0)
        #expect(state.pause(.user) == .pause(.user))
        observe(&state, 1, .initial)
        #expect(state.tick(now: 2) == .wait)
        state.resume(now: 3)
        observe(&state, 2.9)
        #expect(state.tick(now: 3.2) == .wait)
        observe(&state, 3.3)
        observe(&state, 3.51)
        #expect(state.tick(now: 3.52) == .scroll(6))
    }

    @Test("Revisiting captured content is movement, not the bottom")
    func revisit() {
        var state = ScrollCaptureAutoScroll(viewportHeight: 600, now: 0)
        observe(&state, 0.01, .initial)
        observe(&state, 0.21)
        #expect(state.tick(now: 0.22) == .scroll(90))
        observe(&state, 0.3, .revisited(pixelOffset: 90, score: 0))
        observe(&state, 0.51)
        #expect(state.tick(now: 0.52) == .scroll(90))
    }
}
