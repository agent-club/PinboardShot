import AppKit
import Foundation
import Testing
@testable import PinboardShot

private struct LegacyHistoryItem: Encodable {
    let id: UUID
    let createdAt: Date
    let filename: String
    let pixelWidth: Int
    let pixelHeight: Int
    let recognizedText: String?
}

private final class HistoryTestFileManager: FileManager {
    let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .applicationSupportDirectory, domainMask == .userDomainMask {
            return [applicationSupportDirectory]
        }
        return super.urls(for: directory, in: domainMask)
    }
}

private func historyTestImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 24, height: 16))
    image.lockFocus()
    NSColor.systemIndigo.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.unlockFocus()
    return image
}

@Test("旧历史 JSON 根据 recognizedText 推导 OCR 状态")
func legacyHistoryItemInfersOCRStatus() throws {
    let withText = LegacyHistoryItem(
        id: UUID(),
        createdAt: Date(timeIntervalSinceReferenceDate: 100),
        filename: "with-text.png",
        pixelWidth: 20,
        pixelHeight: 10,
        recognizedText: "  searchable\n text  "
    )
    let withoutText = LegacyHistoryItem(
        id: UUID(),
        createdAt: Date(timeIntervalSinceReferenceDate: 200),
        filename: "without-text.png",
        pixelWidth: 30,
        pixelHeight: 15,
        recognizedText: nil
    )

    let decoded = try JSONDecoder().decode(
        [HistoryItem].self,
        from: JSONEncoder().encode([withText, withoutText])
    )

    #expect(decoded[0].recognizedText == "searchable\n text")
    #expect(decoded[0].ocrStatus == .indexed)
    #expect(decoded[1].ocrStatus == .notIndexed)
    #expect(decoded.allSatisfy { $0.sourceApplicationBundleIdentifier == nil })
    #expect(HistorySearchMatcher.matches(decoded[0], query: "searchable"))
    #expect(HistorySearchMatcher.matches(decoded[1], query: "30 × 15"))
}

@Test("历史排除应用只持久化规范化 bundle identifier")
func historyPrivacySettingsNormalizeAndPersistOnlyBundleIdentifier() throws {
    let suiteName = "PinboardShotHistoryPrivacyTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = HistoryPrivacySettings(defaults: defaults)

    #expect(settings.excludedApplications.isEmpty)
    settings.add(bundleIdentifier: "  COM.Example.Secret  ", displayName: "Secret Window")
    settings.add(bundleIdentifier: "com.example.secret", displayName: "Duplicate")

    #expect(settings.hasExclusions)
    #expect(settings.excludedApplications == [
        HistoryExcludedApplication(bundleIdentifier: "com.example.secret")
    ])
    #expect(settings.isExcluded(bundleIdentifier: "COM.EXAMPLE.SECRET"))
    let storedData = try #require(defaults.data(forKey: HistoryPrivacySettings.excludedApplicationsDefaultsKey))
    let storedText = try #require(String(data: storedData, encoding: .utf8))
    #expect(!storedText.contains("Secret Window"))
    #expect(!storedText.contains("Duplicate"))

    settings.remove(bundleIdentifier: " COM.EXAMPLE.SECRET ")
    #expect(!settings.hasExclusions)
}

@Test("历史排除规则对未知来源 fail closed")
@MainActor
func historyStoreSkipsExcludedAndUnknownApplications() throws {
    let suiteName = "PinboardShotHistoryExclusionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    HistoryPrivacySettings(defaults: defaults).add(bundleIdentifier: "com.example.secret")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HistoryStore(
        fileManager: HistoryTestFileManager(applicationSupportDirectory: directory),
        defaults: defaults
    )

    #expect(try store.add(historyTestImage()) == nil)
    #expect(try store.add(
        historyTestImage(),
        sourceApplicationBundleIdentifier: "COM.EXAMPLE.SECRET"
    ) == nil)
    let item = try #require(try store.add(
        historyTestImage(),
        sourceApplicationBundleIdentifier: "com.example.allowed"
    ))
    #expect(item.sourceApplicationBundleIdentifier == "com.example.allowed")
}

@Test("损坏的历史排除配置采用 fail closed")
@MainActor
func historyStoreBlocksCaptureWhenExclusionConfigurationIsCorrupt() throws {
    let suiteName = "PinboardShotHistoryCorruptExclusionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(Data("not-json".utf8), forKey: HistoryPrivacySettings.excludedApplicationsDefaultsKey)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HistoryStore(
        fileManager: HistoryTestFileManager(applicationSupportDirectory: directory),
        defaults: defaults
    )

    #expect(HistoryPrivacySettings(defaults: defaults).isConfigurationCorrupted)
    #expect(try store.add(
        historyTestImage(),
        sourceApplicationBundleIdentifier: "com.example.allowed"
    ) == nil)
    #expect(store.items.isEmpty)
}

@Test("OCR 状态更新规范化文本且可清空索引")
@MainActor
func historyStoreUpdatesAndClearsOCRIndex() throws {
    let suiteName = "PinboardShotHistoryOCRTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HistoryStore(
        fileManager: HistoryTestFileManager(applicationSupportDirectory: directory),
        defaults: defaults
    )
    let item = try #require(try store.add(historyTestImage()))

    try store.updateOCRStatus(itemID: item.id, status: .pending)
    #expect(store.items[0].ocrStatus == .pending)
    try store.updateRecognizedText(itemID: item.id, text: "  first\n\nsecond  ")
    #expect(store.items[0].recognizedText == "first\n\nsecond")
    #expect(store.items[0].ocrStatus == .indexed)
    #expect(store.items[0].ocrIndexedAt != nil)

    try store.clearOCRIndex()
    #expect(store.items[0].recognizedText == nil)
    #expect(store.items[0].ocrStatus == .notIndexed)
    #expect(store.items[0].ocrIndexedAt == nil)

    let staleRequest = try #require(try store.beginOCRIndexing(itemID: item.id))
    try store.clearOCRIndex()
    try store.completeOCRIndexing(staleRequest, status: .indexed, text: "不得写回")
    #expect(store.items[0].recognizedText == nil)
    #expect(store.items[0].ocrStatus == .notIndexed)
}

@Test("清理预览固定候选并报告存储占用")
@MainActor
func historyCleanupPreviewDoesNotDeleteNewItems() throws {
    let suiteName = "PinboardShotHistoryCleanupTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HistoryStore(
        fileManager: HistoryTestFileManager(applicationSupportDirectory: directory),
        defaults: defaults
    )
    let first = try #require(try store.add(historyTestImage()))
    let preview = try store.cleanupPreview(olderThan: Date().addingTimeInterval(60))
    let second = try #require(try store.add(historyTestImage()))

    #expect(preview.candidateIDs == Set([first.id]))
    #expect(preview.reclaimableBytes > 0)
    #expect(fileManagerExists(store.fileURL(for: first)))
    #expect(try store.clearItems(matching: preview) == 1)
    #expect(store.items.map(\.id) == [second.id])
    #expect(!fileManagerExists(store.fileURL(for: first)))

    let orphanData = Data(repeating: 7, count: 19)
    try orphanData.write(
        to: store.fileURL(for: second).deletingLastPathComponent().appendingPathComponent("orphan.png")
    )
    let metrics = try store.storageMetrics()
    #expect(metrics.itemCount == 1)
    #expect(metrics.imageBytes >= 19)
    #expect(metrics.indexBytes > 0)
    #expect(metrics.totalBytes == metrics.imageBytes + metrics.indexBytes)
}

@Test("损坏历史索引不能交叉引用或删除其他截图")
@MainActor
func historyStoreRejectsCrossReferencedFilenames() throws {
    let suiteName = "PinboardShotHistoryCrossReferenceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
    defer { try? FileManager.default.removeItem(at: base) }
    let historyDirectory = base.appendingPathComponent("PinboardShot/History", isDirectory: true)
    try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
    let firstID = UUID()
    let secondID = UUID()
    let secondFilename = "\(secondID.uuidString).png"
    let imageData = try #require(historyTestImage().pngData)
    try imageData.write(to: historyDirectory.appendingPathComponent(secondFilename))
    let items = [
        HistoryItem(
            id: firstID,
            createdAt: Date(),
            filename: secondFilename,
            pixelWidth: 24,
            pixelHeight: 16
        ),
        HistoryItem(
            id: secondID,
            createdAt: Date(),
            filename: secondFilename,
            pixelWidth: 24,
            pixelHeight: 16
        )
    ]
    try JSONEncoder().encode(items).write(
        to: historyDirectory.appendingPathComponent("index.json"),
        options: .atomic
    )

    let store = HistoryStore(
        fileManager: HistoryTestFileManager(applicationSupportDirectory: base),
        defaults: defaults
    )
    #expect(store.items.map(\.id) == [secondID])
    #expect(store.image(for: store.items[0]) != nil)
}

@Test("启动时清理遗留的历史删除暂存目录")
@MainActor
func historyStoreCleansStagedRemovalsOnLaunch() throws {
    let suiteName = "PinboardShotHistoryStagedRemovalTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
    defer { try? FileManager.default.removeItem(at: base) }
    let staging = base.appendingPathComponent("PinboardShot/History/.deleting-test", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try Data(repeating: 3, count: 64).write(to: staging.appendingPathComponent("orphan.png"))

    _ = HistoryStore(
        fileManager: HistoryTestFileManager(applicationSupportDirectory: base),
        defaults: defaults
    )
    #expect(!FileManager.default.fileExists(atPath: staging.path))
}

private func fileManagerExists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}
