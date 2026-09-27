import AppKit
import CoreText
import CoreVideo
import ImageIO
import Testing
import WebKit
@testable import PinboardShot

@Suite("Scroll capture pixel precision")
struct ScrollCapturePrecisionTests {
    @Test("Automatic capture commits settled views and skips transient broken frames", arguments: [0, 268_435_456])
    func settledAutomaticFrames(maximumPendingBytes: Int) throws {
        let source = try document(width: 600, height: 1_400)
        func frame(_ offset: Int) throws -> CGImage {
            try #require(source.cropping(to: CGRect(x: 0, y: offset, width: 600, height: 600)))
        }
        let pipeline = ScrollCaptureFramePipeline(maximumPendingBytes: maximumPendingBytes, onProgress: { _ in })
        let frames = try [0, 0, 20, 55].map(frame)
        for (index, image) in frames.enumerated() {
            #expect(pipeline.submit(image, timestamp: Double(index), requiresStableFrame: true))
        }
        // A compositor frame briefly has part of the list from another scroll
        // position. It must never supply rows to the exported long image.
        let context = try #require(CGContext(data: nil, width: 600, height: 600,
            bitsPerComponent: 8, bytesPerRow: 2_400, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(try frame(80), in: CGRect(x: 0, y: 0, width: 600, height: 600))
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 200, width: 600, height: 100))
        #expect(pipeline.submit(try #require(context.makeImage()), timestamp: 4, requiresStableFrame: true))
        let initial = try #require(pipeline.finalImage())
        #expect(try pixels(initial) == pixels(frame(0)))
        for (index, offset) in [100, 100, 160, 200, 200, 200].enumerated() {
            #expect(pipeline.submit(try frame(offset), timestamp: Double(index + 5), requiresStableFrame: true))
        }
        let stitched = try #require(pipeline.finalImage())
        let expected = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 600, height: 800)))
        #expect(try pixels(stitched) == pixels(expected))
        pipeline.cancel()
    }

    @Test("Floating sidebar labels are repaired with revealed content rather than repeated", arguments: [false, true], [1, 12, 100])
    func floatingSidebarLabel(backward: Bool, step: Int) throws {
        let width = 600
        let height = 600
        let source = try document(width: width, height: 1_500)
        func frame(_ offset: Int) throws -> CGImage {
            let cropped = try #require(source.cropping(to: CGRect(x: 0, y: offset, width: width, height: height)))
            let context = try #require(CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            // Put the label away from the exit edge for large reverse jumps so its
            // obscured document pixels are actually observed in the following frame.
            let labelY = backward && step == 100 ? 488 : 80
            context.setFillColor(gray: 0.96, alpha: 1)
            context.fill(CGRect(x: 504, y: labelY, width: 72, height: 32))
            let text = NSAttributedString(string: "11 小时", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.4, alpha: 1)
            ])
            context.textPosition = CGPoint(x: 510, y: labelY + 8)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            return try #require(context.makeImage())
        }
        let positions = Array(stride(from: 0, through: 600, by: step))
        let ordered = backward ? Array(positions.reversed()) : positions
        let accumulator = ScrollCaptureAccumulator()
        for offset in ordered {
            let result = accumulator.append(try frame(offset))
            if offset == ordered.first { #expect(result == .initial) }
            else if case .appended = result { continue }
            else { Issue.record("Floating label stopped capture: \(result)"); return }
        }
        let stitched = try #require(accumulator.makeImage())
        let context = try #require(CGContext(data: nil, width: width, height: 1_200,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(try #require(source.cropping(to: CGRect(x: 0, y: 0, width: width, height: 1_200))),
                     in: CGRect(x: 0, y: 0, width: width, height: 1_200))
        context.draw(try frame(try #require(ordered.last)),
                     in: CGRect(x: 0, y: backward ? 600 : 0, width: width, height: height))
        #expect(try pixels(stitched) == pixels(try #require(context.makeImage())))
    }

    @Test("Fast scrolling still aligns when a textured sidebar stays fixed")
    func fastScrollWithFixedSidebar() throws {
        let source = try document(width: 600, height: 3_200)
        func frame(_ offset: Int) throws -> CGImage {
            let cropped = try #require(source.cropping(to: CGRect(x: 0, y: offset, width: 600, height: 1_200)))
            let context = try #require(CGContext(data: nil, width: 600, height: 1_200,
                bitsPerComponent: 8, bytesPerRow: 2_400, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 600, height: 1_200))
            context.setFillColor(gray: 0.94, alpha: 1)
            context.fill(CGRect(x: 480, y: 0, width: 120, height: 1_200))
            for y in stride(from: 10, to: 1_200, by: 31) {
                context.setFillColor(gray: CGFloat(y % 180) / 255, alpha: 1)
                context.fill(CGRect(x: 505, y: y, width: 60, height: 9))
            }
            return try #require(context.makeImage())
        }
        let accumulator = ScrollCaptureAccumulator()
        for offset in [0, 1_020, 1_880] {
            let result = accumulator.append(try frame(offset))
            if offset == 0 { #expect(result == .initial) }
            else if case .appended = result { continue }
            else { Issue.record("Fixed sidebar stopped fast capture at \(offset): \(result)"); return }
        }
        #expect(accumulator.pixelHeight == 3_080)
        let stitched = try #require(accumulator.makeImage())
        let actual = try #require(stitched.cropping(to: CGRect(x: 0, y: 0, width: 475, height: 3_080)))
        let expected = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 475, height: 3_080)))
        #expect(try pixels(actual) == pixels(expected))
    }

    @Test("Selected BGRA rows are copied without rendering the whole window")
    func croppedStreamFrame() throws {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 8, 6, kCVPixelFormatType_32BGRA,
                                    nil, &buffer) == kCVReturnSuccess)
        let pixelBuffer = try #require(buffer)
        #expect(CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess)
        let base = try #require(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)
        let sourceStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<6 {
            for x in 0..<8 {
                let pixel = base.advanced(by: y * sourceStride + x * 4)
                pixel[0] = UInt8(x * 10)
                pixel[1] = UInt8(y * 10)
                pixel[2] = 30
                pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let image = try #require(ScrollCaptureFrameCropper.crop(
            pixelBuffer, to: CGRect(x: 1.2, y: 1.2, width: 3.4, height: 2.5)
        ))
        #expect(image.width == 4 && image.height == 3)
        let provider = try #require(image.dataProvider)
        let bytes = try #require(provider.data) as Data
        for y in 0..<3 {
            for x in 0..<4 {
                let offset = (y * 4 + x) * 4
                #expect(bytes[offset] == UInt8((x + 1) * 10))
                #expect(bytes[offset + 1] == UInt8((y + 1) * 10))
                #expect(bytes[offset + 2] == 30)
                #expect(bytes[offset + 3] == 255)
            }
        }
    }

    @Test("A blocked stitcher retains frames in memory and on disk", arguments: [0, 576_000, 268_435_456])
    func bufferedFastScroll(maximumPendingBytes: Int) throws {
        let source = try document(width: 240, height: 2_400)
        let frames = try [0, 300, 600, 900, 1_200].map { offset in
            try #require(source.cropping(to: CGRect(x: 0, y: offset, width: 240, height: 600)))
        }
        let queue = DispatchQueue(label: "PinboardShotTests.blocked-stitcher")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }
        // Release even if submit regresses into a blocking call, so the test fails
        // instead of hanging indefinitely.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { gate.signal() }
        let pipeline = ScrollCaptureFramePipeline(
            maximumPendingBytes: maximumPendingBytes, processingQueue: queue, onProgress: { _ in }
        )
        let start = CFAbsoluteTimeGetCurrent()
        for frame in frames { #expect(pipeline.submit(frame)) }
        let submissionTime = CFAbsoluteTimeGetCurrent() - start
        gate.signal()
        #expect(submissionTime < 0.5)
        let stitched = try #require(pipeline.finalImage())
        let expected = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 240, height: 1_800)))
        #expect(try pixels(stitched) == pixels(expected))
    }

    @Test("Animation in one content band does not invent scrolling")
    func stationaryAnimation() throws {
        let source = try document(width: 600, height: 1_200)
        let accumulator = ScrollCaptureAccumulator()
        #expect(accumulator.append(source) == .initial)
        for index in 0..<8 {
            let context = try #require(CGContext(data: nil, width: 600, height: 1_200,
                bitsPerComponent: 8, bytesPerRow: 2_400, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: 600, height: 1_200))
            context.setFillColor(gray: CGFloat(index + 1) / 10, alpha: 1)
            context.fill(CGRect(x: 170, y: 300 + index * 13, width: 80, height: 250))
            let result = accumulator.append(try #require(context.makeImage()))
            #expect(result == .duplicate || result == .unmatched)
        }
        #expect(accumulator.pixelHeight == 1_200)
        #expect(try pixels(try #require(accumulator.makeImage())) == pixels(source))
    }

    @Test("A skipped viewport stays recoverable when scrolling back to confirmed content")
    func skippedViewportRecovery() throws {
        let source = try document(width: 240, height: 6_000)
        let accumulator = ScrollCaptureAccumulator()
        for offset in stride(from: 0, through: 2_000, by: 200) {
            let frame = try #require(source.cropping(to: CGRect(x: 0, y: offset, width: 240, height: 600)))
            let result = accumulator.append(frame)
            if offset == 0 { #expect(result == .initial) }
            else if case .appended = result { continue }
            else { Issue.record("Expected content at \(offset): \(result)"); return }
        }
        let distant = try #require(source.cropping(to: CGRect(x: 0, y: 4_000, width: 240, height: 600)))
        for _ in 0..<24 { #expect(accumulator.append(distant) == .unmatched) }
        let overlap = try #require(source.cropping(to: CGRect(x: 0, y: 2_200, width: 240, height: 600)))
        guard case .appended = accumulator.append(overlap) else {
            Issue.record("Capture did not resume after returning to the last viewport")
            return
        }
        let stitched = try #require(accumulator.makeImage())
        let expected = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 240, height: 2_800)))
        #expect(try pixels(stitched) == pixels(expected))
    }

    private func document(width: Int = 1415, height: Int = 2200) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(gray: 0.94, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var seed: UInt64 = 42
        for y in stride(from: 0, to: height, by: 23) {
            for x in stride(from: 60, to: width - 60, by: 37) {
                seed = seed &* 6364136223846793005 &+ 1
                let shade = CGFloat((seed >> 32) % 180 + 30) / 255
                context.setFillColor(gray: shade, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 25, height: 13))
            }
        }
        return try #require(context.makeImage())
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
    }

    private func sidebarDocument(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(gray: 0.09, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let titles = ["Review scrolling capture", "Check image continuity", "Fix layout spacing", "Inspect window selection", "Verify exported document"]
        let font = CTFontCreateWithName("Helvetica" as CFString, 17, nil)
        for index in 0..<(height / 29) {
            let title = "\(index + 1). \(titles[(index * 7 + index / 3) % titles.count])"
            let text = NSAttributedString(string: title, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.7, alpha: 1)
            ])
            context.textPosition = CGPoint(x: index.isMultiple(of: 5) ? 18 : 36, y: index * 29 + 7)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        return try #require(context.makeImage())
    }

    @Test("Retina frames resolve shifts between thumbnail pixels", arguments: [31, 65, 127, -31])
    func exactShift(shift: Int) throws {
        let image = try document()
        let firstY = max(0, -shift)
        let first = try #require(image.cropping(to: CGRect(x: 0, y: firstY, width: image.width, height: 1200)))
        let second = try #require(image.cropping(to: CGRect(x: 0, y: firstY + shift, width: image.width, height: 1200)))
        let match = try #require(ScrollFrameMatcher.match(previous: first, current: second))
        #expect(match.verticalShift == shift)
    }

    @Test("Fast scroll with a narrow overlap is still stitched", arguments: [false, true])
    func fastScroll(backward: Bool) throws {
        let shift = 960
        let image = try document(width: 600, height: 2_400)
        let firstY = backward ? shift : 0
        let secondY = backward ? 0 : shift
        let first = try #require(image.cropping(to: CGRect(x: 0, y: firstY, width: 600, height: 1_200)))
        let second = try #require(image.cropping(to: CGRect(x: 0, y: secondY, width: 600, height: 1_200)))
        #expect(ScrollFrameMatcher.match(previous: first, current: second)?.verticalShift == (backward ? -shift : shift))
        let accumulator = ScrollCaptureAccumulator()
        #expect(accumulator.append(first) == .initial)
        guard case .appended(let height, _) = accumulator.append(second) else {
            Issue.record("Fast scroll was not appended")
            return
        }
        #expect(height == shift)
        let stitched = try #require(accumulator.makeImage())
        let expected = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: 600, height: 1_200 + shift)))
        #expect(try pixels(stitched) == pixels(expected))
    }

    @Test("Sparse rendered release text stays aligned through small and near-full scrolls")
    @MainActor
    func renderedReleaseText() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 620))
        let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let sections = (0..<24).map { index in
            "<section><h2>Release section \(index)</h2><p>Updated menu \(index * 17) and capture options \(index * 29).</p>" +
            "<ul><li>Clear output control \(index * 31)</li><li>Long document capture \(index * 37)</li></ul></section>"
        }.joined()
        web.loadHTMLString("""
            <style>html,body{margin:0;background:white;color:#24292f;font:16px/26px system-ui}
            article{max-width:680px;margin:28px auto;border:1px solid #d0d7de;border-radius:6px;padding:24px}
            h1{font-size:28px;margin:0 0 32px}h2{font-size:22px;border-bottom:1px solid #d0d7de;padding-bottom:14px}
            section{margin:36px 0 48px}li{padding:3px 0}</style>
            <article><h1>PinboardShot 0.12.0</h1>\(sections)</article>
            """, baseURL: nil)
        var loaded = false
        for _ in 0..<100 {
            if !web.isLoading,
               (try? await web.evaluateJavaScript("document.querySelectorAll('section').length")) as? Int == 24 {
                loaded = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(loaded)
        guard loaded else { return }
        let accumulator = ScrollCaptureAccumulator()
        var capturedFrames: [(offset: Int, image: CGImage)] = []
        for offset in [0, 1, 2, 12, 40, 120, 240, 770] {
            _ = try await web.evaluateJavaScript("window.scrollTo(0, \(offset))")
            try await Task.sleep(for: .milliseconds(100))
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = 800
            let image = try await web.takeSnapshot(configuration: config)
            var bounds = CGRect(origin: .zero, size: image.size)
            let frame = try #require(image.cgImage(forProposedRect: &bounds, context: nil, hints: nil))
            capturedFrames.append((offset, frame))
            let result = accumulator.append(frame)
            if offset == 0 { #expect(result == .initial) }
            else if case .appended = result { continue }
            else { Issue.record("Rendered release text stopped at \(offset): \(result)"); return }
        }
        #expect(accumulator.pixelHeight == (620 + 770) * 2)
        let stitched = try #require(accumulator.makeImage())
        for captured in capturedFrames {
            let viewport = try #require(stitched.cropping(to: CGRect(
                x: 0, y: captured.offset * 2, width: captured.image.width, height: captured.image.height
            )))
            #expect(try pixels(viewport) == pixels(captured.image))
        }
    }

    @Test("Scrolling upward backfills the complete top half")
    func reverseBackfill() throws {
        let width = 240
        let image = try document(width: width, height: 6_600)
        let accumulator = ScrollCaptureAccumulator()
        for position in stride(from: 6_000, through: 0, by: -200) {
            let frame = try #require(image.cropping(to: CGRect(
                x: 0, y: position, width: width, height: 600
            )))
            let result = accumulator.append(frame)
            if position == 6_000 { #expect(result == .initial) }
            else if case .appended = result { continue }
            else { Issue.record("Reverse capture stopped at \(position): \(result)"); return }
        }
        let stitched = try #require(accumulator.makeImage())
        #expect(stitched.height == 6_600)
        #expect(try pixels(stitched) == pixels(image))
    }

    @Test("Reversing direction fills rows above the starting viewport")
    func reverseAfterForward() throws {
        let width = 240
        let image = try document(width: width, height: 4_000)
        let accumulator = ScrollCaptureAccumulator()
        let positions = [3_000, 3_200, 3_400, 3_200, 3_000] +
            Array(stride(from: 2_800, through: 0, by: -200))
        for (index, position) in positions.enumerated() {
            let frame = try #require(image.cropping(to: CGRect(
                x: 0, y: position, width: width, height: 600
            )))
            let result = accumulator.append(frame)
            if index == 0 { #expect(result == .initial) }
            else if case .appended = result { continue }
            else if case .revisited = result { continue }
            else { Issue.record("Direction reversal stopped at \(position): \(result)"); return }
        }
        let stitched = try #require(accumulator.makeImage())
        #expect(stitched.height == 4_000)
        #expect(try pixels(stitched) == pixels(image))
    }

    @Test("Many narrow slices preserve every source pixel without seams")
    func consecutiveFrames() throws {
        let image = try document()
        let accumulator = ScrollCaptureAccumulator()
        let positions = [0, 31, 65, 96, 127, 162, 193, 225, 256, 290, 321]
        for position in positions {
            let frame = try #require(image.cropping(to: CGRect(x: 0, y: position, width: image.width, height: 1200)))
            let result = accumulator.append(frame)
            if position == 0 {
                #expect(result == .initial)
            } else {
                guard case .appended = result else {
                    Issue.record("Frame at \(position) was not appended: \(result)")
                    return
                }
            }
        }
        let stitched = try #require(accumulator.makeImage())
        #expect(stitched.height == 1521)
        let expected = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: stitched.height)))
        #expect(try pixels(stitched) == pixels(expected))
        let png = try #require(NSBitmapImageRep(cgImage: stitched).representation(using: .png, properties: [:]))
        let decoded = try #require(NSBitmapImageRep(data: png)?.cgImage)
        #expect(try pixels(decoded) == pixels(expected))
    }

    @Test("One-pixel scroll frames accumulate instead of resetting the reference")
    func gradualMovement() throws {
        let image = try document()
        let accumulator = ScrollCaptureAccumulator()
        for position in 0...40 {
            let frame = try #require(image.cropping(to: CGRect(x: 0, y: position, width: image.width, height: 1200)))
            _ = accumulator.append(frame)
        }
        #expect(accumulator.pixelHeight >= 1230)
        let stitched = try #require(accumulator.makeImage())
        let expected = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: stitched.height)))
        #expect(try pixels(stitched) == pixels(expected))
    }

    @Test("Captured rows survive eviction of old tracking keyframes")
    func sustainedCapture() throws {
        let image = try document(width: 240, height: 8000)
        let accumulator = ScrollCaptureAccumulator()
        for index in 0...220 {
            let frame = try #require(image.cropping(to: CGRect(x: 0, y: index * 31, width: 240, height: 240)))
            let result = accumulator.append(frame)
            if index > 0 {
                guard case .appended = result else {
                    Issue.record("Continuous capture stopped at frame \(index): \(result)")
                    return
                }
            }
        }
        let stitched = try #require(accumulator.makeImage())
        #expect(stitched.height == 7060)
        let preview = try #require(accumulator.makePreviewImage(maximumWidth: 120, maximumHeight: 256))
        #expect(preview.width <= 120 && preview.height == 256)
        let expected = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: 240, height: 7060)))
        #expect(try pixels(stitched) == pixels(expected))
    }

    @Test("Capture beyond 32768 rows remains readable at both ends")
    func veryLongCapture() throws {
        let width = 240
        let image = try document(width: width, height: 36_000)
        let accumulator = ScrollCaptureAccumulator()
        for index in 0...177 {
            let frame = try #require(image.cropping(to: CGRect(
                x: 0, y: index * 200, width: width, height: 600
            )))
            let result = accumulator.append(frame)
            if index > 0, case .appended = result { continue }
            if index > 0 {
                let prior = try #require(image.cropping(to: CGRect(
                    x: 0, y: (index - 1) * 200, width: width, height: 600
                )))
                let previousOverlap = try #require(prior.cropping(to: CGRect(x: 0, y: 200, width: width, height: 400)))
                let currentOverlap = try #require(frame.cropping(to: CGRect(x: 0, y: 0, width: width, height: 400)))
                Issue.record("Long capture stopped at frame \(index): \(result), local match: \(String(describing: ScrollFrameMatcher.match(previous: prior, current: frame))), overlap equal: \(try pixels(previousOverlap) == pixels(currentOverlap))")
                return
            }
        }
        let stitched = try #require(accumulator.makeImage())
        #expect(stitched.height == 36_000)
        let png = try #require(NSImage(
            cgImage: stitched, size: CGSize(width: width, height: 36_000)
        ).mappedPNGData)
        let encodedSource = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let encodedProperties = try #require(
            CGImageSourceCopyPropertiesAtIndex(encodedSource, 0, nil) as? [CFString: Any]
        )
        #expect(encodedProperties[kCGImagePropertyPixelHeight] as? Int == 36_000)
        for y in [0, 35_400] {
            let rect = CGRect(x: 0, y: y, width: width, height: 600)
            let actual = try #require(stitched.cropping(to: rect))
            let expected = try #require(image.cropping(to: rect))
            #expect(try pixels(actual) == pixels(expected))
        }
    }

    @Test("Fixed header and footer appear once without hiding scrolling content", arguments: [false, true], [false, true])
    func fixedChrome(backward: Bool, dark: Bool) throws {
        let width = 507
        let viewportHeight = 600
        let headerHeight = 64
        let footerHeight = 52
        let contentHeight = viewportHeight - headerHeight - footerHeight
        let image = try dark ? sidebarDocument(width: width, height: 1600) : document(width: width, height: 1600)
        func frame(at position: Int, contentHeight: Int) throws -> CGImage {
            let height = contentHeight + headerHeight + footerHeight
            let context = try #require(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(gray: 0.09, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let content = try #require(image.cropping(to: CGRect(x: 0, y: position, width: width, height: contentHeight)))
            context.draw(content, in: CGRect(x: 0, y: footerHeight, width: width, height: contentHeight))
            if dark {
                let gradient = try #require(CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [CGColor(gray: 0.09, alpha: 0), CGColor(gray: 0.09, alpha: 1)] as CFArray,
                    locations: [0, 1]
                ))
                context.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: footerHeight + 28),
                    end: CGPoint(x: 0, y: footerHeight), options: [])
                context.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: height - headerHeight - 28),
                    end: CGPoint(x: 0, y: height - headerHeight), options: [])
            }
            for x in stride(from: 20, to: width - 20, by: 25) {
                context.setFillColor(gray: CGFloat(x % 43 + 140) / 255, alpha: 1)
                context.fill(CGRect(x: x, y: 16, width: 12, height: 14))
                context.fill(CGRect(x: x, y: height - 32, width: 14, height: 15))
            }
            return try #require(context.makeImage())
        }
        let positions = backward
            ? [310, 279, 248, 279, 186, 155, 217, 93, 62, 0]
            : [0, 31, 62, 31, 124, 155, 93, 217, 248, 310]
        let accumulator = ScrollCaptureAccumulator()
        for position in positions {
            let result = accumulator.append(try frame(at: position, contentHeight: contentHeight))
            if position != positions.first {
                switch result {
                case .appended, .revisited:
                    break
                default:
                    Issue.record("Fixed chrome capture stopped at \(position): \(result)")
                    return
                }
            }
        }
        let stitched = try #require(accumulator.makeImage())
        let expected = try frame(at: 0, contentHeight: contentHeight + 310)
        #expect(stitched.height == expected.height)
        #expect(try pixels(stitched) == pixels(expected))
        let preview = try #require(accumulator.makePreviewImage(maximumWidth: width, maximumHeight: 1000))
        #expect(try pixels(preview) == pixels(expected))
    }
}
