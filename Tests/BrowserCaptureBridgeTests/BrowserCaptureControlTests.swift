import Foundation
import Testing
@testable import BrowserCaptureBridge

@Suite("Browser capture controls")
struct BrowserCaptureControlTests {
    @Test("App pause and stop requests cross only the matching native session")
    func sessionControls() throws {
        let root = URL(fileURLWithPath: "/private/tmp/pinboardshot-controls-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = BrowserCaptureInbox(rootURL: root)
        let processor = BrowserCaptureProtocolProcessor(inbox: inbox)
        func request(_ command: String, _ fields: [String: Any] = [:]) throws -> [String: Any] {
            let payload = fields.merging(["command": command, "requestId": UUID().uuidString]) { _, new in new }
            return try #require(JSONSerialization.jsonObject(with: processor.process(JSONSerialization.data(withJSONObject: payload)).data) as? [String: Any])
        }
        #expect(try request("hello", ["protocolVersion": 1])["supportsCaptureControl"] as? Bool == true)
        let rawID = try #require(request("begin")["captureId"] as? String)
        let id = try #require(UUID(uuidString: rawID))
        let store = BrowserCaptureControlStore(inbox: inbox)
        try store.setRequest(id: id, paused: true, stopped: false)
        let control = try request("control", ["captureId": id.uuidString, "status": "paused", "progress": 23])
        #expect(control["paused"] as? Bool == true)
        #expect(control["stopped"] as? Bool == false)
        #expect(try store.state(id: id).status == .paused)
        #expect(try store.state(id: id).progress == 23)
        #expect(try request("control", ["captureId": UUID().uuidString, "status": "paused", "progress": 23])["ok"] as? Bool == false)
        #expect(try request("setControl", ["captureId": id.uuidString, "paused": 1, "stopped": false])["ok"] as? Bool == false)
        #expect(try request("setControl", ["captureId": id.uuidString, "paused": false, "stopped": false])["ok"] as? Bool == true)
        #expect(try store.request(id: id).paused == false)
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            try? store.setRequest(id: id, paused: index.isMultiple(of: 2), stopped: index == 3)
        }
        #expect(try store.request(id: id).stopped)
        try store.setRequest(id: id, paused: false, stopped: false)
        #expect(try store.request(id: id).stopped)
        processor.cancelPartialSession()
        #expect(try store.activeStates(since: .distantPast).isEmpty)
    }

    @Test("Control files reject symlinks and stale sessions are not attached")
    func safeControlFiles() throws {
        let root = URL(fileURLWithPath: "/private/tmp/pinboardshot-controls-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = BrowserCaptureInbox(rootURL: root)
        let id = UUID()
        let writer = try inbox.makeWriter(id: id)
        let store = BrowserCaptureControlStore(inbox: inbox)
        try store.begin(id: id, now: Date(timeIntervalSince1970: 10))
        #expect(try store.activeStates(since: .distantPast).isEmpty)
        let file = root.appendingPathComponent(id.uuidString.lowercased()).appendingPathComponent("control-request.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: URL(fileURLWithPath: "/dev/null"))
        #expect(throws: BrowserCaptureBridgeError.self) { try store.request(id: id) }
        try FileManager.default.removeItem(at: file)
        try writer.cancel()
    }
}
