@testable import BrowserCaptureBridge
import CoreGraphics
import Foundation
import ImageIO
import Testing

@Suite(.serialized)
struct BrowserCaptureBridgeTests {
    @Test func nativeMessageFrameUsesLittleEndianLengthAndRoundTrips() throws {
        let payload = Data("{\"command\":\"hello\"}".utf8)
        let frame = try BrowserCaptureNativeMessageFraming.frame(payload)
        #expect(Array(frame.prefix(4)) == [UInt8(payload.count), 0, 0, 0])
        #expect(try BrowserCaptureNativeMessageFraming.payload(from: frame) == payload)
        #expect(throws: BrowserCaptureBridgeError.self) {
            try BrowserCaptureNativeMessageFraming.payload(from: Data([10, 0, 0, 0, 1]))
        }
    }

    @Test func protocolWritesManifestAndUUIDScopedTileWithoutOpeningApp() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let inbox = BrowserCaptureInbox(rootURL: root)
        try inbox.ensureSecureRoot(create: true)
        let processor = BrowserCaptureProtocolProcessor(inbox: inbox)
        #expect(try response(processor, ["requestId": "hello", "command": "hello", "protocolVersion": 1])["ok"] as? Bool == true)
        let begin = try response(processor, ["requestId": "begin", "command": "begin"])
        let captureID = try #require(begin["captureId"] as? String, "begin response: \(begin)")
        let png = try makePNG(width: 2, height: 3)
        let encoded = png.base64EncodedString()

        #expect(try response(processor, ["requestId": "tile-begin", "command": "tileBegin", "captureId": captureID,
                                          "index": 0, "scrollY": 0.5, "viewportWidth": 800.0,
                                          "viewportHeight": 600.0, "documentHeight": 1200.0,
                                          "base64Length": encoded.utf8.count])["ok"] as? Bool == true)
        let split = 7
        let first = String(encoded.prefix(split))
        let second = String(encoded.dropFirst(split))
        #expect(try response(processor, ["requestId": "tile-chunk-0", "command": "tileChunk", "captureId": captureID,
                                          "index": 0, "sequence": 0, "data": first])["ok"] as? Bool == true)
        #expect(try response(processor, ["requestId": "tile-chunk-1", "command": "tileChunk", "captureId": captureID,
                                          "index": 0, "sequence": 1, "data": second])["ok"] as? Bool == true)
        #expect(try response(processor, ["requestId": "tile-end", "command": "tileEnd", "captureId": captureID,
                                          "index": 0])["ok"] as? Bool == true)
        let finish = processor.process(try json(["requestId": "finish", "command": "finish", "captureId": captureID,
                                                 "capturedHeight": 600.0]))
        #expect(finish.captureReadyToOpen == UUID(uuidString: captureID))
        let manifest = try BrowserCaptureInbox(rootURL: root).readManifest(id: try #require(UUID(uuidString: captureID)))
        #expect(manifest.capturedHeight == 600)
        #expect(manifest.tiles.count == 1)
        #expect(manifest.tiles[0].scrollY == 0.5)
        #expect(manifest.tiles[0].pngPixelWidth == 2)
        #expect(manifest.tiles[0].pngPixelHeight == 3)
        #expect(try BrowserCaptureInbox(rootURL: root).readTile(id: try #require(UUID(uuidString: captureID)), index: 0) == png)
        try BrowserCaptureInbox(rootURL: root).cleanup(id: try #require(UUID(uuidString: captureID)))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(captureID).path))
    }

    @Test func rejectsChunkSequenceGapsAndCleansPartialSession() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let processor = BrowserCaptureProtocolProcessor(inbox: BrowserCaptureInbox(rootURL: root))
        let begin = try response(processor, ["requestId": "begin", "command": "begin"])
        let captureID = try #require(begin["captureId"] as? String, "begin response: \(begin)")
        let png = try makePNG(width: 1, height: 1).base64EncodedString()
        _ = try response(processor, ["requestId": "tile-begin", "command": "tileBegin", "captureId": captureID,
                                     "index": 0, "scrollY": 0, "viewportWidth": 20, "viewportHeight": 20,
                                     "documentHeight": 20, "base64Length": png.utf8.count])
        let failed = try response(processor, ["requestId": "gap", "command": "tileChunk", "captureId": captureID,
                                               "index": 0, "sequence": 1, "data": png])
        #expect(failed["ok"] as? Bool == false)
        #expect(failed["error"] as? String == "invalid_chunk")
        processor.cancelPartialSession()
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(captureID).path))
    }

    @Test func inboxRejectsSymlinkedCaptureDirectory() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let id = UUID()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(id.uuidString.lowercased()), withDestinationURL: outside)
        #expect(throws: BrowserCaptureBridgeError.self) {
            _ = try BrowserCaptureInbox(rootURL: root).readManifest(id: id)
        }
    }

    private func response(_ processor: BrowserCaptureProtocolProcessor, _ object: [String: Any]) throws -> [String: Any] {
        let reply = processor.process(try json(object))
        return try #require(JSONSerialization.jsonObject(with: reply.data) as? [String: Any])
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func makeTemporaryRoot() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("BrowserCaptureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let root = base.appendingPathComponent("BrowserCaptures", isDirectory: true)
        return root
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
