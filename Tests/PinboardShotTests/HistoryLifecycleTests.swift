import AppKit
import Foundation
import Testing
@testable import PinboardShot

private final class LifecycleFileManager: FileManager {
    let root: URL
    var rejectsStaging = false

    init(root: URL) {
        self.root = root
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        directory == .applicationSupportDirectory ? [root] : super.urls(for: directory, in: domainMask)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if rejectsStaging, dstURL.deletingLastPathComponent().lastPathComponent.hasPrefix(".deleting-") {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

@Suite("History lifecycle")
@MainActor
struct HistoryLifecycleTests {
    @Test("启动即执行保留期，并同步删除过期图片及 OCR 索引")
    func startupEnforcesRetention() throws {
        try withFixture { root, defaults, fileManager in
            let history = root.appendingPathComponent("PinboardShot/History")
            let old = try seedImage(in: history, ageInDays: 8)
            let recent = try seedImage(in: history, ageInDays: 1)
            try JSONEncoder().encode([recent, old]).write(to: history.appendingPathComponent("index.json"))
            defaults.set(7, forKey: HistorySettings.retentionDaysDefaultsKey)

            let store = HistoryStore(fileManager: fileManager, defaults: defaults)

            #expect(store.items.map(\.id) == [recent.id])
            #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: old).path))
            #expect(FileManager.default.fileExists(atPath: store.fileURL(for: recent).path))
            let persisted = try JSONDecoder().decode(
                [HistoryItem].self, from: Data(contentsOf: history.appendingPathComponent("index.json"))
            )
            #expect(persisted.map(\.id) == [recent.id])
        }
    }

    @Test("损坏索引恢复时真正删除超额图片，不留下隐藏磁盘占用")
    func recoveryRemovesExcessFiles() throws {
        try withFixture { root, defaults, fileManager in
            let history = root.appendingPathComponent("PinboardShot/History")
            let seeded = try (0..<12).map { try seedImage(in: history, ageInDays: $0) }
            try Data("invalid index".utf8).write(to: history.appendingPathComponent("index.json"))
            defaults.set(10, forKey: HistorySettings.maximumItemsDefaultsKey)

            let store = HistoryStore(fileManager: fileManager, defaults: defaults)
            let files = try FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "png" }

            #expect(store.items.count == 10)
            #expect(files.count == 10)
            #expect(Set(store.items.map(\.id)) == Set(seeded.prefix(10).map(\.id)))
            for item in seeded.suffix(2) {
                #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: item).path))
            }
        }
    }

    @Test("无限保留仍保留旧图片")
    func unlimitedRetentionPreservesOldImages() throws {
        try withFixture { root, defaults, fileManager in
            let history = root.appendingPathComponent("PinboardShot/History")
            let old = try seedImage(in: history, ageInDays: 180)
            try JSONEncoder().encode([old]).write(to: history.appendingPathComponent("index.json"))
            defaults.set(0, forKey: HistorySettings.retentionDaysDefaultsKey)
            let store = HistoryStore(fileManager: fileManager, defaults: defaults)
            #expect(store.items.map(\.id) == [old.id])
            #expect(FileManager.default.fileExists(atPath: store.fileURL(for: old).path))
        }
    }

    @Test("显式保留的截图跳过自动清理，仍可手动删除")
    func keptCaptureSurvivesAutomaticRetention() throws {
        try withFixture { root, defaults, fileManager in
            let history = root.appendingPathComponent("PinboardShot/History")
            var kept = try seedImage(in: history, ageInDays: 30)
            kept.isKept = true
            let recent = try (0..<12).map { try seedImage(in: history, ageInDays: $0) }
            try JSONEncoder().encode(recent + [kept]).write(to: history.appendingPathComponent("index.json"))
            defaults.set(10, forKey: HistorySettings.maximumItemsDefaultsKey)

            let store = HistoryStore(fileManager: fileManager, defaults: defaults)
            #expect(store.items.count == 11)
            #expect(store.items.contains(where: { $0.id == kept.id && $0.isKept }))

            defaults.set(7, forKey: HistorySettings.retentionDaysDefaultsKey)
            try store.applyRetentionPolicy()
            #expect(store.items.count == 8)
            #expect(store.items.contains(where: { $0.id == kept.id }))

            let reloaded = HistoryStore(fileManager: fileManager, defaults: defaults)
            #expect(reloaded.items.contains(where: { $0.id == kept.id && $0.isKept }))
            try reloaded.delete(kept)
            #expect(!FileManager.default.fileExists(atPath: reloaded.fileURL(for: kept).path))
        }
    }

    @Test("清理失败保留图片并给出可见错误，重试成功后清除错误")
    func retentionFailurePreservesImagesAndCanRetry() throws {
        try withFixture { root, defaults, fileManager in
            let history = root.appendingPathComponent("PinboardShot/History")
            let old = try seedImage(in: history, ageInDays: 8)
            try JSONEncoder().encode([old]).write(to: history.appendingPathComponent("index.json"))
            defaults.set(7, forKey: HistorySettings.retentionDaysDefaultsKey)
            fileManager.rejectsStaging = true

            let store = HistoryStore(fileManager: fileManager, defaults: defaults)
            #expect(store.items.map(\.id) == [old.id])
            #expect(FileManager.default.fileExists(atPath: store.fileURL(for: old).path))
            #expect(store.retentionErrorMessage != nil)

            fileManager.rejectsStaging = false
            try store.applyRetentionPolicy()
            #expect(store.items.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: old).path))
            #expect(store.retentionErrorMessage == nil)
        }
    }

    private func withFixture(
        _ body: (URL, UserDefaults, LifecycleFileManager) throws -> Void
    ) throws {
        let name = "PinboardShotHistoryLifecycle.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        try body(root, defaults, LifecycleFileManager(root: root))
    }

    private func seedImage(in directory: URL, ageInDays: Int) throws -> HistoryItem {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 16, bitsPerPixel: 32
        ))
        bitmap.bitmapData?.initialize(repeating: 0, count: 64)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let id = UUID()
        let filename = "\(id.uuidString).png"
        let date = Date().addingTimeInterval(-Double(ageInDays) * 86_400)
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return HistoryItem(
            id: id, createdAt: date, filename: filename, pixelWidth: 4, pixelHeight: 4,
            recognizedText: "Synthetic lifecycle fixture"
        )
    }
}
