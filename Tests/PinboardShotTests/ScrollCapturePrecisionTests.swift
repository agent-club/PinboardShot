import AppKit
import CoreText
import Testing
@testable import PinboardShot

@Suite("Scroll capture pixel precision")
struct ScrollCapturePrecisionTests {
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
        let expected = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: 240, height: 7060)))
        #expect(try pixels(stitched) == pixels(expected))
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
