import AppKit
import CoreText
import CryptoKit
import Darwin
import Testing
@testable import PinboardShot

// Opt in with PINBOARDSHOT_BENCHMARK=1 and run `swift test -c release --filter PerformanceBenchmarks`.
// Synthetic fixtures avoid capturing the desktop or touching personal history/Keychain data.
@Suite(.serialized)
struct PerformanceBenchmarks {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PINBOARDSHOT_BENCHMARK"] == "1"))
    func imageProcessing() throws {
        let environment = ProcessInfo.processInfo.environment
        let selected = environment["PINBOARDSHOT_BENCHMARK_CASE"]
        let iterations = Int(environment["PINBOARDSHOT_BENCHMARK_ITERATIONS"] ?? "21") ?? 21
        let id = UUID(uuidString: "12345678-1234-5678-9012-123456789012")!

        for (label, width, height) in [("1080p", 1920, 1080), ("4k", 3840, 2160), ("8k", 7680, 4320)]
        where selected == nil || selected?.hasSuffix(".\(label)") == true || (label == "1080p" && selected == "scale.1080p.4k") {
            try autoreleasepool {
                let cgImage = try fixture(width: width, height: height)
                let image = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
                let stroke = AnnotationStroke(tool: .pen, points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.8, y: 0.6)],
                    color: AnnotationColor(.red), width: 0.005)
                let mosaic = AnnotationStroke(tool: .mosaic, points: stroke.points,
                    color: stroke.color, width: 0.02)
                let operations: [(String, () throws -> Void)] = [
                    ("validate", { () throws -> Void in #expect(CaptureImageValidator.nativeLuminanceRange(cgImage) != nil) }),
                    ("png", { () throws -> Void in #expect(image.pngData?.isEmpty == false) }),
                    ("annotation.pen", { () throws -> Void in #expect(try AnnotationRenderer.render(image: cgImage, strokes: [stroke]).width == width) }),
                    ("annotation.mosaic", { () throws -> Void in #expect(try AnnotationRenderer.render(image: cgImage, strokes: [mosaic]).width == width) }),
                    ("comparison", { () throws -> Void in #expect(PinComparisonRenderer.render(first: image, second: image, mode: .overlay) != nil) }),
                    ("watermark.embed", { () throws -> Void in #expect(try InvisibleWatermarkCodec.embed(id: id, in: image).pixelDimensions?.width == width) }),
                    ("watermark.absent", { () throws -> Void in #expect(try InvisibleWatermarkCodec.detect(in: image) == nil) })
                ]
                for (operation, body) in operations {
                    let name = "\(operation).\(label)"
                    if selected == nil || selected == name {
                        try measure(name, iterations: iterations, body: body)
                    }
                }
                let detectionName = "watermark.present.\(label)"
                if selected == nil || selected == detectionName {
                    let marked = try InvisibleWatermarkCodec.embed(id: id, in: image)
                    #expect(try InvisibleWatermarkCodec.detect(in: marked) == id)
                    try measure(detectionName, iterations: iterations) { () throws -> Void in
                        #expect(try InvisibleWatermarkCodec.detect(in: marked) == id)
                    }
                }
                if label == "1080p", selected == nil || selected == "scale.1080p.4k" {
                    try measure("scale.1080p.4k", iterations: iterations) { () throws -> Void in
                        #expect(try CaptureImageScaler.scaled(cgImage, quality: .uhd4K).width == 3840)
                    }
                }
            }
        }

        for (name, width, frameHeight, documentHeight, step) in [
            ("scroll.4k", 3840, 2160, 5760, 300),
            ("scroll.long", 1920, 1080, 21080, 1000)
        ] where selected == nil || selected == name || selected == "\(name).preview" {
            try autoreleasepool {
                let source = try fixture(width: width, height: documentHeight)
                let frames = try stride(from: 0, through: documentHeight - frameHeight, by: step).map { offset in
                    let cropped = try #require(source.cropping(to: CGRect(x: 0, y: offset, width: width, height: frameHeight)))
                    // Capture streams deliver independent frames, not crops that retain a huge document backing bitmap.
                    let context = try #require(CGContext(data: nil, width: width, height: frameHeight,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                    context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: frameHeight))
                    return try #require(context.makeImage())
                }
                let accumulator = ScrollCaptureAccumulator()
                for frame in frames { _ = accumulator.append(frame) }
                #expect(accumulator.pixelHeight == documentHeight)
                if selected == nil || selected == name {
                    try measure(name, iterations: min(iterations, 21)) {
                        let candidate = ScrollCaptureAccumulator()
                        for frame in frames { _ = candidate.append(frame) }
                        #expect(candidate.pixelHeight == documentHeight)
                        #expect(candidate.makeImage()?.height == documentHeight)
                    }
                }
                if selected == nil || selected == "\(name).preview" {
                    try measure("\(name).preview", iterations: iterations) { () throws -> Void in
                        #expect(accumulator.makePreviewImage() != nil)
                    }
                }
            }
        }

        if selected == nil || selected == "compatibility" {
            for (width, height) in [(321, 201), (961, 603)] {
                let source = try fixture(width: width, height: height)
                let image = NSImage(cgImage: source, size: CGSize(width: width, height: height))
                let marked = try InvisibleWatermarkCodec.embed(id: id, in: image)
                var rect = CGRect(origin: .zero, size: marked.size)
                print("PINBOARDSHOT_GOLDEN watermark.\(width)x\(height) " + (try digest(#require(marked.cgImage(forProposedRect: &rect, context: nil, hints: nil)))))
                for tool in [AnnotationTool.pen, .mosaic] {
                    let stroke = AnnotationStroke(tool: tool, points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.8, y: 0.6)],
                        color: AnnotationColor(.red), width: 0.02)
                    print("PINBOARDSHOT_GOLDEN annotation.\(tool.rawValue).\(width)x\(height) " + (try digest(AnnotationRenderer.render(image: source, strokes: [stroke]))))
                }
            }
        }

        if selected == nil || selected == "ocr.1080p" {
            let image = try textFixture()
            try measure("ocr.1080p", iterations: min(iterations, 5)) { () throws -> Void in
                let text = try TextRecognitionService.recognizeText(in: image)
                #expect(!text.isEmpty)
            }
        }
    }

    @Test("Watermark pixel output preserves the existing protocol on odd image sizes")
    func watermarkPixelCompatibility() throws {
        let id = UUID(uuidString: "12345678-1234-5678-9012-123456789012")!
        // Recorded from the pre-optimization codec; odd sizes exercise integer grid boundaries and clipping.
        for (width, height, expected) in [
            (321, 201, "72fc22d7b4b33fbb4e115cc6f4ab67bf730df973c2e0782f3c3fc5639aa876ad"),
            (961, 603, "f7a2efc06025be687f04fd863aee88288782a224500de3637b61253e8c29a8e0")
        ] {
            let source = try fixture(width: width, height: height)
            let marked = try InvisibleWatermarkCodec.embed(id: id,
                in: NSImage(cgImage: source, size: CGSize(width: width, height: height)))
            var rect = CGRect(origin: .zero, size: marked.size)
            let image = try #require(marked.cgImage(forProposedRect: &rect, context: nil, hints: nil))
            #expect(try digest(image) == expected)
        }
    }

    private func measure(_ name: String, iterations: Int, body: () throws -> Void) throws {
        let residentAtEntry = residentMemoryMiB()
        for _ in 0..<2 { try autoreleasepool(invoking: body) }
        var wall: [Double] = []
        var cpu: [Double] = []
        for _ in 0..<max(1, iterations) {
            var before = rusage()
            getrusage(RUSAGE_SELF, &before)
            let start = DispatchTime.now().uptimeNanoseconds
            try autoreleasepool(invoking: body)
            wall.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            var after = rusage()
            getrusage(RUSAGE_SELF, &after)
            cpu.append(cpuTime(after) - cpuTime(before))
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let sorted = wall.sorted()
        let record: [String: Any] = [
            "name": name, "samples": wall.count, "wall_ms": wall,
            "resident_at_entry_mib": residentAtEntry, "resident_after_mib": residentMemoryMiB(),
            "median_ms": sorted[sorted.count / 2],
            "p95_ms": sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)],
            "cpu_median_ms": cpu.sorted()[cpu.count / 2],
            // macOS reports bytes; this is the cumulative process high-water mark, not a per-operation peak.
            "process_high_water_mib": Double(usage.ru_maxrss) / 1_048_576
        ]
        print("PINBOARDSHOT_BENCHMARK " + String(decoding: try JSONSerialization.data(withJSONObject: record, options: .sortedKeys), as: UTF8.self))
    }

    private func residentMemoryMiB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }

    private func cpuTime(_ usage: rusage) -> Double {
        Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
    }

    private func fixture(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        // A deterministic textured document provides unique rows for frame alignment.
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let value = UInt8(truncatingIfNeeded: (y &* 37) ^ (x &* 13) ^ ((y / 7) &* 19))
                bytes[offset] = value
                bytes[offset + 1] = UInt8(truncatingIfNeeded: Int(value) + x / 17)
                bytes[offset + 2] = UInt8(truncatingIfNeeded: Int(value) + y / 11)
                bytes[offset + 3] = 255
            }
        }
        return try #require(context.makeImage())
    }

    private func digest(_ image: CGImage) throws -> String {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data)
        return SHA256.hash(data: Data(bytes: bytes, count: image.width * image.height * 4))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func textFixture() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 1920, height: 1080,
            bitsPerComponent: 8, bytesPerRow: 7680, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "PinboardShot performance benchmark 1234567890", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 32, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
            ]))
        for y in stride(from: 60, to: 1040, by: 70) {
            context.textPosition = CGPoint(x: 40, y: y)
            CTLineDraw(line, context)
        }
        return try #require(context.makeImage())
    }
}
