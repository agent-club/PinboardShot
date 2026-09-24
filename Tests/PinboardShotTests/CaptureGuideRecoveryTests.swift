import Foundation
import Testing
@testable import PinboardShot

@Test func captureGuideRecoveryRoundTripsAndExpires() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("recovery/draft.json")
    let store = CaptureGuideRecoveryStore(fileURL: fileURL)
    let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let guide = CaptureGuide(title: "Temporary guide")

    try await store.save(guide, now: savedAt)
    #expect(try await store.load(now: savedAt.addingTimeInterval(60))?.title == guide.title)
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.deletingLastPathComponent().path)
    #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)

    #expect(try await store.load(now: savedAt.addingTimeInterval(25 * 60 * 60)) == nil)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
}
