import BrowserCaptureBridge
import Foundation
import Testing
@testable import PinboardShot

struct BrowserExtensionSetupTests {
    private let hostURL = URL(fileURLWithPath: "/Applications/PinboardShot.app/Contents/MacOS/PinboardShotBrowserHost")

    @Test("Connecting registers both user installation channels without exporting an extension")
    func registersBothInstallationChannels() throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let registration = try BrowserExtensionSetup.registerHost(hostURL: hostURL, home: home)
        try Data(#"{"allowed_origins":["chrome-extension://olghjpagobkdfmiphmabpapcfgjfdeaf/"]}"#.utf8)
            .write(to: registration)
        #expect(try BrowserExtensionSetup.registerHost(hostURL: hostURL, home: home) == registration)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: registration)) as? [String: Any])
        #expect(json["name"] as? String == BrowserCaptureConfiguration.hostName)
        #expect(json["path"] as? String == hostURL.path)
        #expect(json["type"] as? String == "stdio")
        #expect(json["allowed_origins"] as? [String] == BrowserCaptureConfiguration.allowedOrigins)
        let attributes = try FileManager.default.attributesOfItem(atPath: registration.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Downloads").path))
    }

    @Test("Refreshing registration removes unknown origins while retaining both installation channels")
    func removesUnknownOrigins() throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let registration = try BrowserExtensionSetup.registerHost(hostURL: hostURL, home: home)
        try Data(#"{"allowed_origins":["chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"]}"#.utf8).write(to: registration)
        _ = try BrowserExtensionSetup.registerHost(hostURL: hostURL, home: home)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: registration)) as? [String: Any])
        #expect(json["allowed_origins"] as? [String] == ["chrome-extension://kjpleeeibdicdoljjhoahhnkggncglac/",
            "chrome-extension://olghjpagobkdfmiphmabpapcfgjfdeaf/"])
    }

    @Test("Connecting rejects a substituted host manifest and preserves its target")
    func rejectsSymlinkedManifest() throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let registration = try BrowserExtensionSetup.registerHost(hostURL: hostURL, home: home)
        let otherFile = home.appendingPathComponent("other.json")
        let original = Data("untouched".utf8)
        try original.write(to: otherFile)
        try FileManager.default.removeItem(at: registration)
        try FileManager.default.createSymbolicLink(at: registration, withDestinationURL: otherFile)
        #expect(throws: BrowserCaptureImportError.self) {
            try BrowserExtensionSetup.registerHost(hostURL: hostURL, home: home)
        }
        #expect(try Data(contentsOf: otherFile) == original)
    }
}
