import AppKit
import Foundation
import Testing
@testable import PinboardShot

private func advancedWorkspaceImage(_ color: NSColor = .systemBlue) -> NSImage {
    let image = NSImage(size: CGSize(width: 18, height: 12))
    image.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.unlockFocus()
    return image
}

private let advancedWorkspaceState = PinWorkspaceWindowState(
    frame: CGRect(x: 10, y: 20, width: 180, height: 120),
    opacity: 0.8,
    ignoresMouseEvents: false,
    isPositionLocked: true,
    appearsOnAllSpaces: true,
    visibilityBundleIdentifier: nil,
    isAutoFadeOnHoverEnabled: false
)

@Test("工作区元数据规范化并执行长度和数量上限")
func advancedWorkspaceMetadataValidation() throws {
    let metadata = try PinMetadata.validated(
        note: "  对稿说明  ",
        tags: [" Design ", "design", "", "客户"]
    )
    #expect(metadata.note == "对稿说明")
    #expect(metadata.tags == ["Design", "客户"])
    #expect(!metadata.isEmpty)
    #expect(PinMetadata.empty.isEmpty)

    #expect(throws: PinWorkspaceStoreError.invalidMetadata) {
        try PinMetadata(note: String(repeating: "a", count: 2_001))
    }
    #expect(throws: PinWorkspaceStoreError.invalidMetadata) {
        try PinMetadata(tags: (0..<13).map { "tag-\($0)" })
    }
    #expect(throws: PinWorkspaceStoreError.invalidMetadata) {
        try PinMetadata(tags: [String(repeating: "a", count: 33)])
    }
}

@Test("旧 v1 manifest 缺少新字段时映射为空元数据")
@MainActor
func advancedWorkspaceDecodesOriginalV1Manifest() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceAdvanced-\(UUID())")
    defer { try? fileManager.removeItem(at: root) }
    let store = PinWorkspaceStore(fileManager: fileManager, rootDirectory: root)
    let saved = try store.save(
        name: "旧格式",
        captures: [PinWorkspaceCapture(image: advancedWorkspaceImage(), state: advancedWorkspaceState)]
    )
    let directory = root.appendingPathComponent(saved.id.uuidString)
    let manifestURL = directory.appendingPathComponent("manifest.json")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
    json.removeValue(forKey: "lastRestoredAt")
    var pins = try #require(json["pins"] as? [[String: Any]])
    pins[0].removeValue(forKey: "metadata")
    json["pins"] = pins
    try JSONSerialization.data(withJSONObject: json).write(to: manifestURL, options: .atomic)

    store.refresh()
    let workspace = try #require(store.workspaces.first)
    #expect(workspace.lastRestoredAt == nil)
    #expect(workspace.aggregateTags.isEmpty)
    #expect(workspace.noteCount == 0)
    #expect(try store.load(workspace).entries.first?.metadata == .empty)
}

@Test("单条损坏元数据不会阻塞工作区图片恢复")
@MainActor
func advancedWorkspaceIgnoresMalformedMetadata() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceAdvanced-\(UUID())")
    defer { try? fileManager.removeItem(at: root) }
    let store = PinWorkspaceStore(fileManager: fileManager, rootDirectory: root)
    let saved = try store.save(
        name: "损坏元数据",
        captures: [PinWorkspaceCapture(
            image: advancedWorkspaceImage(),
            state: advancedWorkspaceState,
            metadata: try PinMetadata(note: "有效", tags: ["Review"])
        )]
    )
    let manifestURL = root
        .appendingPathComponent(saved.id.uuidString)
        .appendingPathComponent("manifest.json")
    var json = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
    )
    var pins = try #require(json["pins"] as? [[String: Any]])
    pins[0]["metadata"] = ["note": String(repeating: "x", count: 2_001), "tags": []]
    json["pins"] = pins
    try JSONSerialization.data(withJSONObject: json).write(to: manifestURL, options: .atomic)

    store.refresh()
    let workspace = try #require(store.workspaces.first)
    let loaded = try store.load(workspace)
    #expect(loaded.entries.count == 1)
    #expect(loaded.entries[0].metadata == .empty)
}

@Test("重命名、元数据、恢复时间和独立复制保持一致")
@MainActor
func advancedWorkspaceMutationAndDuplication() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceAdvanced-\(UUID())")
    defer { try? fileManager.removeItem(at: root) }
    let store = PinWorkspaceStore(fileManager: fileManager, rootDirectory: root)
    let initialMetadata = try PinMetadata(note: "第一版", tags: ["UI", "Review"])
    let saved = try store.save(
        name: "方案 A",
        captures: [PinWorkspaceCapture(
            image: advancedWorkspaceImage(.systemPink),
            state: advancedWorkspaceState,
            metadata: initialMetadata
        )]
    )

    let renamed = try store.rename(saved, to: "  方案 B  ")
    #expect(renamed.name == "方案 B")
    let metadataItem = try #require(store.metadataItems(for: renamed).first)
    let updatedMetadata = try PinMetadata(note: "已确认", tags: ["Final", "final"])
    let updated = try store.updateMetadata(for: metadataItem.id, in: renamed, metadata: updatedMetadata)
    #expect(updated.aggregateTags == ["Final"])
    #expect(updated.noteCount == 1)

    let restoredAt = Date(timeIntervalSince1970: 123_456)
    let restored = try store.markRestored(updated, at: restoredAt)
    #expect(restored.lastRestoredAt == restoredAt)
    let duplicate = try store.duplicate(restored, name: "方案 B 副本")
    #expect(duplicate.id != restored.id)
    #expect(duplicate.lastRestoredAt == nil)
    #expect(try store.load(duplicate).entries.first?.metadata == updatedMetadata)

    try store.delete(restored)
    #expect(try store.load(duplicate).entries.count == 1)
    let manifestPermissions = try fileManager.attributesOfItem(
        atPath: root.appendingPathComponent(duplicate.id.uuidString).appendingPathComponent("manifest.json").path
    )[.posixPermissions] as? NSNumber
    #expect(manifestPermissions?.intValue == 0o600)
}

@Test("纯搜索与排序不改变工作区集合")
func advancedWorkspaceSearchAndSort() {
    let older = PinWorkspaceSummary(
        id: UUID(),
        name: "Beta",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        pinCount: 1,
        aggregateTags: ["Review"]
    )
    let newer = PinWorkspaceSummary(
        id: UUID(),
        name: "Alpha",
        createdAt: Date(timeIntervalSince1970: 2),
        updatedAt: Date(timeIntervalSince1970: 3),
        pinCount: 1,
        lastRestoredAt: Date(timeIntervalSince1970: 5),
        aggregateTags: ["Final"],
        searchableNotes: ["Crème layout approved"]
    )
    #expect(PinWorkspaceSort.updatedNewest.sorted([older, newer]).map(\.name) == ["Alpha", "Beta"])
    #expect(PinWorkspaceSort.nameAscending.sorted([older, newer]).map(\.name) == ["Alpha", "Beta"])
    #expect(newer.matchesSearch("final"))
    #expect(newer.matchesSearch("creme approved"))
    #expect(!older.matchesSearch("missing"))
}

@Test("恢复快照隐藏、可失效、复用稳定资源并允许部分恢复")
@MainActor
func advancedWorkspaceRecoveryLifecycle() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceAdvanced-\(UUID())")
    defer { try? fileManager.removeItem(at: root) }
    let store = PinWorkspaceStore(fileManager: fileManager, rootDirectory: root)
    let firstID = UUID()
    let secondID = UUID()
    let recoveryMetadata = try PinMetadata(note: "会话备注", tags: ["恢复"])
    let captures = [
        PinSessionCapture(
            id: firstID,
            image: advancedWorkspaceImage(.red),
            state: advancedWorkspaceState,
            metadata: recoveryMetadata
        ),
        PinSessionCapture(id: secondID, image: advancedWorkspaceImage(.green), state: advancedWorkspaceState)
    ]

    let summary = try #require(try store.saveRecoverySession(captures: captures, pinsAreVisible: false))
    #expect(summary.pinCount == 2)
    #expect(!summary.pinsAreVisible)
    #expect(store.workspaces.isEmpty)
    #expect(store.recoveryStorageBytes() > 0)
    let metrics = try store.storageMetrics()
    #expect(metrics.workspaceCount == 0)
    #expect(metrics.pinCount == 0)
    #expect(metrics.workspaceBytes == 0)
    #expect(metrics.recoveryBytes > 0)
    #expect(metrics.totalBytes == metrics.recoveryBytes)

    let recoveryDirectory = root.appendingPathComponent(".session-recovery")
    let firstAsset = recoveryDirectory.appendingPathComponent("assets/\(firstID.uuidString).png")
    let firstAttributes = try fileManager.attributesOfItem(atPath: firstAsset.path)
    let firstModificationDate = try #require(firstAttributes[.modificationDate] as? Date)
    _ = try store.saveRecoverySession(captures: captures, pinsAreVisible: true)
    let reusedModificationDate = try #require(
        fileManager.attributesOfItem(atPath: firstAsset.path)[.modificationDate] as? Date
    )
    #expect(reusedModificationDate == firstModificationDate)

    try fileManager.removeItem(at: recoveryDirectory.appendingPathComponent("assets/\(secondID.uuidString).png"))
    let partial = try #require(store.loadRecoverySession())
    #expect(partial.entries.count == 1)
    #expect(partial.skippedPinCount == 1)
    #expect(partial.pinsAreVisible)
    #expect(partial.entries.first?.metadata == recoveryMetadata)

    try store.invalidateRecoverySession()
    #expect(fileManager.fileExists(atPath: firstAsset.path))
    #expect(store.loadRecoverySession() == nil)
    #expect(!fileManager.fileExists(atPath: firstAsset.path))

    _ = try store.saveRecoverySession(captures: captures, pinsAreVisible: true)
    #expect(store.loadRecoverySession(maxAge: 0, now: Date().addingTimeInterval(10)) == nil)
    #expect(store.recoveryStorageBytes() == 0)
}

@Test("工作区和恢复读取拒绝符号链接")
@MainActor
func advancedWorkspaceRejectsSymbolicLinks() throws {
    let fileManager = FileManager.default
    let sourceRoot = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceSource-\(UUID())")
    let targetRoot = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceTarget-\(UUID())")
    defer {
        try? fileManager.removeItem(at: sourceRoot)
        try? fileManager.removeItem(at: targetRoot)
    }
    let sourceStore = PinWorkspaceStore(fileManager: fileManager, rootDirectory: sourceRoot)
    let source = try sourceStore.save(
        name: "源工作区",
        captures: [PinWorkspaceCapture(image: advancedWorkspaceImage(), state: advancedWorkspaceState)]
    )
    try fileManager.createDirectory(at: targetRoot, withIntermediateDirectories: false)
    try fileManager.createSymbolicLink(
        at: targetRoot.appendingPathComponent(source.id.uuidString),
        withDestinationURL: sourceRoot.appendingPathComponent(source.id.uuidString)
    )

    let targetStore = PinWorkspaceStore(fileManager: fileManager, rootDirectory: targetRoot)
    #expect(targetStore.workspaces.isEmpty)
    #expect(targetStore.loadWarningCount == 1)
    #expect(throws: PinWorkspaceStoreError.workspaceUnavailable) {
        try targetStore.load(source)
    }
}

@Test("恢复设置默认关闭")
func advancedWorkspaceRecoverySettingDefaultsOff() throws {
    let suiteName = "PinWorkspaceAdvanced-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = PinSessionRecoverySettings(defaults: defaults)
    #expect(!settings.isEnabled)
    settings.isEnabled = true
    #expect(settings.isEnabled)
}

@Test("存储指标分别统计工作区和隐藏恢复缓存")
@MainActor
func advancedWorkspaceStorageMetricsDoNotDoubleCountRecovery() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceAdvanced-\(UUID())")
    defer { try? fileManager.removeItem(at: root) }
    let store = PinWorkspaceStore(fileManager: fileManager, rootDirectory: root)
    _ = try store.save(
        name: "占用统计",
        captures: [PinWorkspaceCapture(image: advancedWorkspaceImage(), state: advancedWorkspaceState)]
    )
    _ = try store.saveRecoverySession(
        captures: [PinSessionCapture(
            id: UUID(),
            image: advancedWorkspaceImage(.orange),
            state: advancedWorkspaceState
        )],
        pinsAreVisible: true
    )

    let metrics = try store.storageMetrics()
    #expect(metrics.workspaceCount == 1)
    #expect(metrics.pinCount == 1)
    #expect(metrics.workspaceBytes > 0)
    #expect(metrics.recoveryBytes > 0)
    #expect(metrics.totalBytes == metrics.workspaceBytes + metrics.recoveryBytes)
    #expect(store.storageBytes() == metrics.totalBytes)
}
