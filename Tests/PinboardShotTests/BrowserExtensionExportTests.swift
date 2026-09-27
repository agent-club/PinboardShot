import Foundation
import Testing
@testable import PinboardShot

struct BrowserExtensionExportTests {
    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("icons"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        for file in ["manifest.json", "background.js", "capture.js", "popup.html", "popup.js", "popup.css",
                     "lib/planner.mjs", "lib/native-protocol.mjs", "lib/native-client.mjs",
                     "icons/icon16.png", "icons/icon32.png", "icons/icon48.png", "icons/icon128.png"] {
            try Data(file.utf8).write(to: source.appendingPathComponent(file))
        }
        return (root, source, downloads)
    }

    @Test("A changed runtime gets a new folder without replacing an installed export")
    func preservesExistingExport() throws {
        let (root, source, downloads) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try BrowserExtensionSetup.exportExtension(from: source, downloads: downloads)
        #expect(try BrowserExtensionSetup.exportExtension(from: source, downloads: downloads) == first)
        #expect(try Data(contentsOf: first.appendingPathComponent("icons/icon128.png")) == Data("icons/icon128.png".utf8))
        let original = try Data(contentsOf: first.appendingPathComponent("capture.js"))
        try Data("updated runtime".utf8).write(to: source.appendingPathComponent("capture.js"))
        let second = try BrowserExtensionSetup.exportExtension(from: source, downloads: downloads)
        #expect(first != second)
        #expect(try Data(contentsOf: first.appendingPathComponent("capture.js")) == original)
        #expect(try Data(contentsOf: second.appendingPathComponent("capture.js")) == Data("updated runtime".utf8))
    }

    @Test("A modified exported file is rejected and retained")
    func preservesUserEdit() throws {
        let (root, source, downloads) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = try BrowserExtensionSetup.exportExtension(from: source, downloads: downloads)
        let editedFile = exported.appendingPathComponent("capture.js")
        let edited = Data("user change".utf8)
        try edited.write(to: editedFile)
        #expect(throws: BrowserCaptureImportError.self) {
            try BrowserExtensionSetup.exportExtension(from: source, downloads: downloads)
        }
        #expect(try Data(contentsOf: editedFile) == edited)
    }

    @Test("The export rejects an existing symlinked module folder")
    func rejectsSymlink() throws {
        let (root, source, downloads) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = try BrowserExtensionSetup.exportExtension(from: source, downloads: downloads)
        let lib = exported.appendingPathComponent("lib")
        try FileManager.default.removeItem(at: lib)
        try FileManager.default.createSymbolicLink(at: lib, withDestinationURL: source.appendingPathComponent("lib"))
        #expect(throws: BrowserCaptureImportError.self) {
            try BrowserExtensionSetup.exportExtension(from: source, downloads: downloads)
        }
    }
}
