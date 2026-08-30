import AppKit
import Foundation
import ImageIO

enum HistorySettings {
    static let enabledDefaultsKey = "historyEnabled"
    static let maximumItemsDefaultsKey = "historyMaximumItems"
    static let retentionDaysDefaultsKey = "historyRetentionDays"
    static let ocrIndexingDefaultsKey = "historyOCRIndexingEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: enabledDefaultsKey) != nil else { return true }
        return defaults.bool(forKey: enabledDefaultsKey)
    }

    static func maximumItems(defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: maximumItemsDefaultsKey)
        return [10, 25, 50, 100, 250].contains(value) ? value : 50
    }

    static func retentionDays(defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: retentionDaysDefaultsKey)
        return [0, 1, 7, 30, 90].contains(value) ? value : 0
    }

    static func ocrIndexingEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: ocrIndexingDefaultsKey) != nil else { return true }
        return defaults.bool(forKey: ocrIndexingDefaultsKey)
    }
}

struct HistoryExcludedApplication: Codable, Hashable, Identifiable, Sendable {
    let bundleIdentifier: String

    var id: String { bundleIdentifier }
}

struct HistoryPrivacySettings {
    static let excludedApplicationsDefaultsKey = "historyExcludedApplications"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var excludedApplications: [HistoryExcludedApplication] {
        guard let decodedApplications else {
            return []
        }
        return Self.normalizedApplications(decodedApplications)
    }

    var hasExclusions: Bool { isConfigurationCorrupted || !excludedApplications.isEmpty }
    var isConfigurationCorrupted: Bool {
        defaults.data(forKey: Self.excludedApplicationsDefaultsKey) != nil && decodedApplications == nil
    }

    private var decodedApplications: [HistoryExcludedApplication]? {
        guard let data = defaults.data(forKey: Self.excludedApplicationsDefaultsKey) else { return [] }
        return try? JSONDecoder().decode([HistoryExcludedApplication].self, from: data)
    }

    func add(bundleIdentifier: String, displayName _: String? = nil) {
        guard let bundleIdentifier = Self.normalizedBundleIdentifier(bundleIdentifier) else { return }
        var applications = excludedApplications
        guard !applications.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        applications.append(HistoryExcludedApplication(bundleIdentifier: bundleIdentifier))
        persist(Self.normalizedApplications(applications))
    }

    func remove(bundleIdentifier: String) {
        guard let bundleIdentifier = Self.normalizedBundleIdentifier(bundleIdentifier) else { return }
        persist(excludedApplications.filter { $0.bundleIdentifier != bundleIdentifier })
    }

    func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier = Self.normalizedBundleIdentifier(bundleIdentifier) else { return false }
        return excludedApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    static func normalizedBundleIdentifier(_ bundleIdentifier: String?) -> String? {
        guard let normalized = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalized.isEmpty else { return nil }
        return normalized
    }

    private static func normalizedApplications(
        _ applications: [HistoryExcludedApplication]
    ) -> [HistoryExcludedApplication] {
        let bundleIdentifiers = Set(applications.compactMap {
            normalizedBundleIdentifier($0.bundleIdentifier)
        })
        return bundleIdentifiers.sorted().map(HistoryExcludedApplication.init(bundleIdentifier:))
    }

    private func persist(_ applications: [HistoryExcludedApplication]) {
        guard let data = try? JSONEncoder().encode(applications) else { return }
        defaults.set(data, forKey: Self.excludedApplicationsDefaultsKey)
    }
}

struct HistoryStorageMetrics: Equatable, Sendable {
    let itemCount: Int
    let imageBytes: Int64
    let indexBytes: Int64

    var screenshotBytes: Int64 { imageBytes }
    var metadataBytes: Int64 { indexBytes }
    var totalBytes: Int64 { imageBytes + indexBytes }
}

struct HistoryCleanupPreview: Equatable, Sendable {
    let cutoff: Date
    let candidateIDs: Set<UUID>
    let reclaimableBytes: Int64

    var itemCount: Int { candidateIDs.count }
}

struct HistoryOCRRequest: Hashable, Sendable {
    let itemID: UUID
    fileprivate let token: UUID
}

enum HistorySearchMatcher {
    static func matches(_ item: HistoryItem, query: String, displayName: String? = nil) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }
        if displayName?.localizedCaseInsensitiveContains(normalizedQuery) == true { return true }
        if item.recognizedText?.localizedCaseInsensitiveContains(normalizedQuery) == true { return true }
        return dimensions(for: item).localizedCaseInsensitiveContains(normalizedQuery)
    }

    static func summary(for item: HistoryItem, maximumLength: Int = 120) -> String {
        guard let text = item.recognizedText, !text.isEmpty else { return dimensions(for: item) }
        guard maximumLength > 0, text.count > maximumLength else { return text }
        return String(text.prefix(maximumLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func dimensions(for item: HistoryItem) -> String {
        "\(item.pixelWidth) × \(item.pixelHeight)"
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var activeOCRRequests: [UUID: UUID] = [:]

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
        cleanupStagedRemovals()
        loadIndex()
    }

    @discardableResult
    func add(
        _ image: NSImage,
        pngData suppliedPNG: Data? = nil,
        sourceApplicationBundleIdentifier: String? = nil
    ) throws -> HistoryItem? {
        guard HistorySettings.isEnabled(defaults: defaults) else { return nil }
        let privacySettings = HistoryPrivacySettings(defaults: defaults)
        guard !privacySettings.isConfigurationCorrupted else { return nil }
        let normalizedBundleIdentifier = HistoryPrivacySettings.normalizedBundleIdentifier(
            sourceApplicationBundleIdentifier
        )
        guard !privacySettings.hasExclusions || normalizedBundleIdentifier != nil else { return nil }
        guard !privacySettings.isExcluded(bundleIdentifier: normalizedBundleIdentifier) else { return nil }
        guard let data = suppliedPNG ?? image.pngData,
              let representation = NSBitmapImageRep(data: data) else {
            throw PinboardShotError.imageEncodingFailed
        }
        let id = UUID()
        let filename = "\(id.uuidString).png"
        try createHistoryDirectoryIfNeeded()
        try data.write(to: historyDirectory.appendingPathComponent(filename), options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: historyDirectory.appendingPathComponent(filename).path
        )

        let item = HistoryItem(
            id: id,
            createdAt: Date(),
            filename: filename,
            pixelWidth: representation.pixelsWide,
            pixelHeight: representation.pixelsHigh,
            sourceApplicationBundleIdentifier: normalizedBundleIdentifier
        )
        let previousItems = items
        items.insert(item, at: 0)
        let retained = retainedItems(from: items)
        let retainedIDs = Set(retained.map(\.id))
        let removedItems = items.filter { !retainedIDs.contains($0.id) }
        let stagedRemoval: StagedRemoval
        do {
            stagedRemoval = try stageFiles(for: removedItems)
        } catch {
            items = previousItems
            try? fileManager.removeItem(at: historyDirectory.appendingPathComponent(filename))
            throw error
        }
        items = retained
        do {
            try persistIndex()
        } catch {
            items = previousItems
            restore(stagedRemoval)
            try? fileManager.removeItem(at: historyDirectory.appendingPathComponent(filename))
            try? persistIndex()
            throw error
        }
        finalize(stagedRemoval)
        return item
    }

    func image(for item: HistoryItem) -> NSImage? {
        NSImage(contentsOf: fileURL(for: item))
    }

    func fileURL(for item: HistoryItem) -> URL {
        let canonicalFilename = "\(item.id.uuidString).png"
        guard item.filename == canonicalFilename else {
            return historyDirectory.appendingPathComponent(canonicalFilename)
        }
        return historyDirectory.appendingPathComponent(canonicalFilename)
    }

    func thumbnail(for item: HistoryItem, maxPixelSize: Int = 180) async -> NSImage? {
        let cacheKey = "\(item.filename)-\(maxPixelSize)" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }
        let url = fileURL(for: item)
        let image = await Task.detached(priority: .utility) {
            Self.makeThumbnail(from: url, maxPixelSize: maxPixelSize)
        }.value
        if let image {
            thumbnailCache.setObject(image, forKey: cacheKey)
        }
        return image
    }

    func clear() throws {
        if fileManager.fileExists(atPath: historyDirectory.path) {
            try fileManager.removeItem(at: historyDirectory)
        }
        thumbnailCache.removeAllObjects()
        items = []
    }

    func delete(_ item: HistoryItem) throws {
        _ = try removeItems(withIDs: [item.id])
    }

    func updateRecognizedText(itemID: UUID, text: String) throws {
        let normalizedText = HistoryOCRTextNormalizer.normalize(text)
        try updateOCRStatus(
            itemID: itemID,
            status: normalizedText == nil ? .empty : .indexed,
            text: normalizedText,
            indexedAt: Date()
        )
    }

    func beginOCRIndexing(itemID: UUID) throws -> HistoryOCRRequest? {
        guard items.contains(where: { $0.id == itemID }) else { return nil }
        let request = HistoryOCRRequest(itemID: itemID, token: UUID())
        activeOCRRequests[itemID] = request.token
        do {
            try updateOCRStatus(itemID: itemID, status: .pending)
            return request
        } catch {
            activeOCRRequests.removeValue(forKey: itemID)
            throw error
        }
    }

    func completeOCRIndexing(
        _ request: HistoryOCRRequest,
        status: HistoryOCRStatus,
        text: String? = nil,
        indexedAt: Date = Date()
    ) throws {
        guard activeOCRRequests[request.itemID] == request.token else { return }
        activeOCRRequests.removeValue(forKey: request.itemID)
        try updateOCRStatus(
            itemID: request.itemID,
            status: status,
            text: text,
            indexedAt: indexedAt
        )
    }

    func cancelOCRIndexing(_ request: HistoryOCRRequest) throws {
        guard activeOCRRequests[request.itemID] == request.token else { return }
        activeOCRRequests.removeValue(forKey: request.itemID)
        try updateOCRStatus(itemID: request.itemID, status: .notIndexed)
    }

    func updateOCRStatus(
        itemID: UUID,
        status: HistoryOCRStatus,
        text: String? = nil,
        indexedAt: Date? = nil
    ) throws {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let previous = items[index]
        let normalizedText = HistoryOCRTextNormalizer.normalize(text)
        let resolvedStatus: HistoryOCRStatus
        if status == .indexed, normalizedText == nil {
            resolvedStatus = .empty
        } else {
            resolvedStatus = status
        }
        items[index].recognizedText = resolvedStatus == .indexed ? normalizedText : nil
        items[index].ocrStatus = resolvedStatus
        items[index].ocrIndexedAt = [.indexed, .empty, .failed].contains(resolvedStatus)
            ? (indexedAt ?? Date())
            : nil
        do {
            try persistIndex()
        } catch {
            items[index] = previous
            try? persistIndex()
            throw error
        }
    }

    func clearOCRIndex() throws {
        activeOCRRequests.removeAll()
        let previousItems = items
        for index in items.indices {
            items[index].recognizedText = nil
            items[index].ocrStatus = .notIndexed
            items[index].ocrIndexedAt = nil
        }
        do {
            try persistIndex()
        } catch {
            items = previousItems
            try? persistIndex()
            throw error
        }
    }

    func storageMetrics() throws -> HistoryStorageMetrics {
        guard fileManager.fileExists(atPath: historyDirectory.path) else {
            return HistoryStorageMetrics(itemCount: items.count, imageBytes: 0, indexBytes: 0)
        }
        var imageBytes: Int64 = 0
        var indexBytes: Int64 = 0
        guard let enumerator = fileManager.enumerator(
            at: historyDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            return HistoryStorageMetrics(itemCount: items.count, imageBytes: 0, indexBytes: 0)
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let size = Int64(values.fileSize ?? 0)
            if url.lastPathComponent == indexURL.lastPathComponent {
                indexBytes += size
            } else {
                imageBytes += size
            }
        }
        return HistoryStorageMetrics(
            itemCount: items.count,
            imageBytes: imageBytes,
            indexBytes: indexBytes
        )
    }

    func cleanupPreview(olderThan cutoff: Date) throws -> HistoryCleanupPreview {
        let candidates = items.filter { $0.createdAt < cutoff }
        let reclaimableBytes = try candidates.reduce(into: Int64(0)) { total, item in
            total += try fileSize(at: fileURL(for: item))
        }
        return HistoryCleanupPreview(
            cutoff: cutoff,
            candidateIDs: Set(candidates.map(\.id)),
            reclaimableBytes: reclaimableBytes
        )
    }

    @discardableResult
    func clearItems(olderThan cutoff: Date) throws -> Int {
        try clearItems(matching: cleanupPreview(olderThan: cutoff))
    }

    @discardableResult
    func clearItems(matching preview: HistoryCleanupPreview) throws -> Int {
        try removeItems(withIDs: preview.candidateIDs)
    }

    func applyRetentionPolicy() throws {
        let retained = retainedItems(from: items)
        let retainedIDs = Set(retained.map(\.id))
        _ = try removeItems(withIDs: Set(items.lazy.filter { !retainedIDs.contains($0.id) }.map(\.id)))
    }

    private var historyDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PinboardShot/History", isDirectory: true)
    }

    private var indexURL: URL { historyDirectory.appendingPathComponent("index.json") }

    private func loadIndex() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            var seenIDs = Set<UUID>()
            var seenFilenames = Set<String>()
            items = decoded.filter { item in
                let canonicalFilename = "\(item.id.uuidString).png"
                return item.filename == canonicalFilename
                    && seenIDs.insert(item.id).inserted
                    && seenFilenames.insert(item.filename).inserted
                    && fileManager.fileExists(atPath: fileURL(for: item).path)
            }
            for index in items.indices where items[index].ocrStatus == .pending {
                items[index].ocrStatus = .notIndexed
                items[index].ocrIndexedAt = nil
            }
            return
        }
        rebuildIndexFromImages()
    }

    private func persistIndex() throws {
        let data = try JSONEncoder().encode(items)
        try createHistoryDirectoryIfNeeded()
        try data.write(to: indexURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
    }

    private func createHistoryDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: historyDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: historyDirectory.path)
    }

    private func rebuildIndexFromImages() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: historyDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        items = urls.compactMap { url in
            guard url.pathExtension.lowercased() == "png",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return HistoryItem(
                id: id,
                createdAt: date,
                filename: url.lastPathComponent,
                pixelWidth: representation.pixelsWide,
                pixelHeight: representation.pixelsHigh
            )
        }.sorted { $0.createdAt > $1.createdAt }
        items = retainedItems(from: items)
        try? persistIndex()
    }

    private func retainedItems(from candidates: [HistoryItem]) -> [HistoryItem] {
        let retentionDays = HistorySettings.retentionDays(defaults: defaults)
        let cutoff = retentionDays > 0
            ? Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())
            : nil
        return Array(
            candidates
                .filter { item in cutoff.map { item.createdAt >= $0 } ?? true }
                .prefix(HistorySettings.maximumItems(defaults: defaults))
        )
    }

    private struct StagedRemoval {
        let directory: URL?
        let items: [HistoryItem]
    }

    private func removeItems(withIDs ids: Set<UUID>) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        let removedItems = items.filter { ids.contains($0.id) }
        guard !removedItems.isEmpty else { return 0 }
        let previousItems = items
        let stagedRemoval = try stageFiles(for: removedItems)
        items.removeAll { ids.contains($0.id) }
        ids.forEach { activeOCRRequests.removeValue(forKey: $0) }
        do {
            try persistIndex()
        } catch {
            items = previousItems
            restore(stagedRemoval)
            try? persistIndex()
            throw error
        }
        thumbnailCache.removeAllObjects()
        finalize(stagedRemoval)
        return removedItems.count
    }

    private func stageFiles(for removedItems: [HistoryItem]) throws -> StagedRemoval {
        let existingItems = removedItems.filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
        guard !existingItems.isEmpty else {
            return StagedRemoval(directory: nil, items: [])
        }
        let stagingDirectory = historyDirectory.appendingPathComponent(
            ".deleting-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var stagedItems: [HistoryItem] = []
        do {
            for item in existingItems {
                try fileManager.moveItem(
                    at: fileURL(for: item),
                    to: stagingDirectory.appendingPathComponent(stagedFilename(for: item))
                )
                stagedItems.append(item)
            }
        } catch {
            restore(StagedRemoval(directory: stagingDirectory, items: stagedItems))
            throw error
        }
        return StagedRemoval(directory: stagingDirectory, items: stagedItems)
    }

    private func restore(_ stagedRemoval: StagedRemoval) {
        guard let directory = stagedRemoval.directory else { return }
        for item in stagedRemoval.items {
            let stagedURL = directory.appendingPathComponent(stagedFilename(for: item))
            guard fileManager.fileExists(atPath: stagedURL.path),
                  !fileManager.fileExists(atPath: fileURL(for: item).path) else { continue }
            try? fileManager.moveItem(at: stagedURL, to: fileURL(for: item))
        }
        try? fileManager.removeItem(at: directory)
    }

    private func finalize(_ stagedRemoval: StagedRemoval) {
        guard let directory = stagedRemoval.directory else { return }
        try? fileManager.removeItem(at: directory)
    }

    private func cleanupStagedRemovals() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: historyDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return }
        for url in contents where url.lastPathComponent.hasPrefix(".deleting-") {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func stagedFilename(for item: HistoryItem) -> String {
        "\(item.id.uuidString).png"
    }

    private func fileSize(at url: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try fileSizeIfPresent(at: url)
    }

    private func fileSizeIfPresent(at url: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private nonisolated static func makeThumbnail(from url: URL, maxPixelSize: Int) -> NSImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}
