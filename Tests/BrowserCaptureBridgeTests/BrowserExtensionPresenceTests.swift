import Foundation
import Testing
@testable import BrowserCaptureBridge

struct BrowserExtensionPresenceTests {
    @Test("Receipts detect both installation channels and expire")
    func expirationAndChannels() throws {
        let root = URL(fileURLWithPath: "/private/tmp/pinboardshot-presence-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserExtensionPresenceStore(inbox: BrowserCaptureInbox(rootURL: root))
        let now = Date(timeIntervalSince1970: 1_000)
        try store.record(extensionID: BrowserCaptureConfiguration.localExtensionID, now: now)
        #expect(try store.connectedExtensionIDs(now: now) == [BrowserCaptureConfiguration.localExtensionID])
        #expect(try store.connectedExtensionIDs(now: now.addingTimeInterval(150)).isEmpty)
        #expect(try store.connectedExtensionIDs(now: now.addingTimeInterval(-1)).isEmpty)
        try store.record(extensionID: BrowserCaptureConfiguration.extensionID, now: now)
        #expect(try store.connectedExtensionIDs(now: now) == [BrowserCaptureConfiguration.extensionID, BrowserCaptureConfiguration.localExtensionID])
        #expect(throws: BrowserCaptureBridgeError.self) { try store.record(extensionID: "unknown", now: now) }
    }

    @Test("A substituted receipt cannot mark an extension connected")
    func rejectsSymlink() throws {
        let root = URL(fileURLWithPath: "/private/tmp/pinboardshot-presence-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserExtensionPresenceStore(inbox: BrowserCaptureInbox(rootURL: root))
        try store.record(extensionID: BrowserCaptureConfiguration.extensionID)
        let receipt = root.appendingPathComponent("extension-\(BrowserCaptureConfiguration.extensionID).json")
        let other = root.appendingPathComponent("other.json")
        try FileManager.default.moveItem(at: receipt, to: other)
        try FileManager.default.createSymbolicLink(at: receipt, withDestinationURL: other)
        #expect(try store.connectedExtensionIDs().isEmpty)
    }
}
