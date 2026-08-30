import AppKit
import Foundation

struct PinWorkspaceWindowState: Codable, Equatable, Sendable {
    var frame: CGRect
    var opacity: Double
    var ignoresMouseEvents: Bool
    var isPositionLocked: Bool
    var appearsOnAllSpaces: Bool
    var visibilityBundleIdentifier: String?
    var isAutoFadeOnHoverEnabled: Bool

    var isValid: Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0 && opacity.isFinite
    }
}

struct PinMetadata: Codable, Equatable, Hashable, Sendable {
    static let maximumNoteLength = 2_000
    static let maximumTagCount = 12
    static let maximumTagLength = 32
    static let empty = PinMetadata(normalizedNote: "", normalizedTags: [])

    let note: String
    let tags: [String]

    var isEmpty: Bool { note.isEmpty && tags.isEmpty }

    init(note: String = "", tags: [String] = []) throws {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedNote.count <= Self.maximumNoteLength else {
            throw PinWorkspaceStoreError.invalidMetadata
        }
        var normalizedTags: [String] = []
        var seenTags: Set<String> = []
        for rawTag in tags {
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard tag.count <= Self.maximumTagLength else {
                throw PinWorkspaceStoreError.invalidMetadata
            }
            guard !tag.isEmpty else { continue }
            let key = Self.comparisonKey(for: tag)
            guard seenTags.insert(key).inserted else { continue }
            normalizedTags.append(tag)
        }
        guard normalizedTags.count <= Self.maximumTagCount else {
            throw PinWorkspaceStoreError.invalidMetadata
        }
        self.init(normalizedNote: normalizedNote, normalizedTags: normalizedTags)
    }

    static func validated(note: String, tags: [String]) throws -> PinMetadata {
        try PinMetadata(note: note, tags: tags)
    }

    private init(normalizedNote: String, normalizedTags: [String]) {
        note = normalizedNote
        tags = normalizedTags
    }

    private static func comparisonKey(for tag: String) -> String {
        tag.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private enum CodingKeys: String, CodingKey { case note, tags }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            self = try PinMetadata(
                note: container.decodeIfPresent(String.self, forKey: .note) ?? "",
                tags: container.decodeIfPresent([String].self, forKey: .tags) ?? []
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .tags,
                in: container,
                debugDescription: "Pin metadata exceeds its storage limits."
            )
        }
    }
}

struct PinWorkspaceCapture {
    let image: NSImage
    let state: PinWorkspaceWindowState
    let metadata: PinMetadata

    init(image: NSImage, state: PinWorkspaceWindowState, metadata: PinMetadata = .empty) {
        self.image = image
        self.state = state
        self.metadata = metadata
    }
}

struct PinWorkspaceSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let pinCount: Int
    let lastRestoredAt: Date?
    let aggregateTags: [String]
    let noteCount: Int
    let searchableNotes: [String]

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        pinCount: Int,
        lastRestoredAt: Date? = nil,
        aggregateTags: [String] = [],
        noteCount: Int = 0,
        searchableNotes: [String] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinCount = pinCount
        self.lastRestoredAt = lastRestoredAt
        self.aggregateTags = aggregateTags
        self.noteCount = noteCount
        self.searchableNotes = searchableNotes
    }

    func matchesSearch(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return true }
        let values = [name] + aggregateTags + searchableNotes
        return terms.allSatisfy { term in
            values.contains { value in
                value.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ) != nil
            }
        }
    }
}

enum PinWorkspaceSort: Sendable {
    case updatedNewest
    case nameAscending
    case recentlyRestored

    func sorted(_ summaries: [PinWorkspaceSummary]) -> [PinWorkspaceSummary] {
        summaries.sorted { lhs, rhs in
            switch self {
            case .updatedNewest:
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            case .nameAscending:
                let result = lhs.name.localizedStandardCompare(rhs.name)
                if result != .orderedSame { return result == .orderedAscending }
            case .recentlyRestored:
                switch (lhs.lastRestoredAt, rhs.lastRestoredAt) {
                case let (left?, right?) where left != right: return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

struct PinWorkspaceRestoreEntry {
    let image: NSImage
    let state: PinWorkspaceWindowState
    let metadata: PinMetadata
}

struct PinWorkspaceLoadResult {
    let workspace: PinWorkspaceSummary
    let entries: [PinWorkspaceRestoreEntry]
    let skippedPinCount: Int
}

struct PinWorkspaceMetadataItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let metadata: PinMetadata
}

struct PinWorkspaceRestoreReport: Equatable, Sendable {
    let restoredPinCount: Int
    let skippedPinCount: Int
    let clearedApplicationBindingCount: Int
}

struct PinSessionRecoverySettings {
    static let defaultIsEnabled = false
    static let defaultsKey = "pinSessionRecoveryEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool {
        get {
            guard defaults.object(forKey: Self.defaultsKey) != nil else {
                return Self.defaultIsEnabled
            }
            return defaults.bool(forKey: Self.defaultsKey)
        }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }
}

struct PinSessionCapture {
    let id: UUID
    let image: NSImage
    let state: PinWorkspaceWindowState
    let metadata: PinMetadata

    init(id: UUID, image: NSImage, state: PinWorkspaceWindowState, metadata: PinMetadata = .empty) {
        self.id = id
        self.image = image
        self.state = state
        self.metadata = metadata
    }
}

struct PinSessionRecoverySummary: Equatable, Sendable {
    let savedAt: Date
    let pinCount: Int
    let pinsAreVisible: Bool
    let storageBytes: Int64
}

typealias RecoverySummary = PinSessionRecoverySummary

struct PinSessionRecoveryLoadResult {
    let summary: PinSessionRecoverySummary
    let entries: [PinWorkspaceRestoreEntry]
    let skippedPinCount: Int
    let pinsAreVisible: Bool
}

struct PinWorkspaceStorageMetrics: Equatable, Sendable {
    let workspaceCount: Int
    let pinCount: Int
    let workspaceBytes: Int64
    let recoveryBytes: Int64

    var totalBytes: Int64 { workspaceBytes + recoveryBytes }
}

enum PinWorkspaceStoreError: LocalizedError, Equatable {
    case invalidName
    case invalidMetadata
    case noPins
    case tooManyPins
    case storageLimitExceeded
    case imageEncodingFailed
    case workspaceUnavailable
    case unsupportedSchema
    case noRestorablePins

    var errorDescription: String? {
        switch self {
        case .invalidName: L10n.text("pinWorkspace.error.invalidName")
        case .noPins: L10n.text("pinWorkspace.error.noPins")
        case .imageEncodingFailed: L10n.text("pinWorkspace.error.imageEncoding")
        case .noRestorablePins: L10n.text("pinWorkspace.error.noRestorablePins")
        case .invalidMetadata, .tooManyPins, .storageLimitExceeded,
             .workspaceUnavailable, .unsupportedSchema:
            L10n.text("pinWorkspace.error.unavailable")
        }
    }
}

private struct PinWorkspaceManifest: Codable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let lastRestoredAt: Date?
    let pins: [PinWorkspacePinRecord]

    var summary: PinWorkspaceSummary {
        var tags: [String] = []
        var seen: Set<String> = []
        for tag in pins.flatMap(\.metadata.tags) {
            let key = tag.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            if seen.insert(key).inserted { tags.append(tag) }
        }
        return PinWorkspaceSummary(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pinCount: pins.count,
            lastRestoredAt: lastRestoredAt,
            aggregateTags: tags,
            noteCount: pins.count { !$0.metadata.note.isEmpty },
            searchableNotes: pins.map(\.metadata.note).filter { !$0.isEmpty }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, createdAt, updatedAt, lastRestoredAt, pins
    }

    init(
        schemaVersion: Int,
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        lastRestoredAt: Date?,
        pins: [PinWorkspacePinRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRestoredAt = lastRestoredAt
        self.pins = pins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastRestoredAt = try container.decodeIfPresent(Date.self, forKey: .lastRestoredAt)
        pins = try container.decode([PinWorkspacePinRecord].self, forKey: .pins)
    }
}

private struct PinWorkspacePinRecord: Codable {
    let id: UUID
    let imageFilename: String
    let state: PinWorkspaceWindowState
    let metadata: PinMetadata

    private enum CodingKeys: String, CodingKey { case id, imageFilename, state, metadata }

    init(id: UUID, imageFilename: String, state: PinWorkspaceWindowState, metadata: PinMetadata) {
        self.id = id
        self.imageFilename = imageFilename
        self.state = state
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        imageFilename = try container.decode(String.self, forKey: .imageFilename)
        state = try container.decode(PinWorkspaceWindowState.self, forKey: .state)
        if container.contains(.metadata) {
            metadata = (try? container.decode(PinMetadata.self, forKey: .metadata)) ?? .empty
        } else {
            metadata = .empty
        }
    }
}

private struct PinSessionRecoveryManifest: Codable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let savedAt: Date
    let pinsAreVisible: Bool
    let pins: [PinSessionRecoveryRecord]
}

private struct PinSessionRecoveryRecord: Codable {
    let id: UUID
    let imageFilename: String
    let state: PinWorkspaceWindowState
    let metadata: PinMetadata

    private enum CodingKeys: String, CodingKey { case id, imageFilename, state, metadata }

    init(id: UUID, imageFilename: String, state: PinWorkspaceWindowState, metadata: PinMetadata) {
        self.id = id
        self.imageFilename = imageFilename
        self.state = state
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        imageFilename = try container.decode(String.self, forKey: .imageFilename)
        state = try container.decode(PinWorkspaceWindowState.self, forKey: .state)
        metadata = (try? container.decode(PinMetadata.self, forKey: .metadata)) ?? .empty
    }
}

@MainActor
final class PinWorkspaceStore: ObservableObject {
    static let maximumPinCount = 50
    static let maximumPNGBytes = 256 * 1_024 * 1_024
    static let defaultRecoveryMaxAge: TimeInterval = 24 * 60 * 60

    @Published private(set) var workspaces: [PinWorkspaceSummary] = []
    @Published private(set) var loadWarningCount = 0

    private let fileManager: FileManager
    private let rootDirectory: URL

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootDirectory = base.appendingPathComponent("PinboardShot/PinWorkspaces", isDirectory: true)
        }
        refresh()
    }

    @discardableResult
    func save(name: String, captures: [PinWorkspaceCapture]) throws -> PinWorkspaceSummary {
        let normalizedName = try Self.normalizedName(name)
        guard !captures.isEmpty else { throw PinWorkspaceStoreError.noPins }
        guard captures.count <= Self.maximumPinCount else { throw PinWorkspaceStoreError.tooManyPins }

        var encodedCaptures: [(capture: PinWorkspaceCapture, data: Data)] = []
        var totalBytes = 0
        for capture in captures {
            guard let data = capture.image.pngData else {
                throw PinWorkspaceStoreError.imageEncodingFailed
            }
            totalBytes = try Self.checkedPNGByteCount(adding: data.count, to: totalBytes)
            encodedCaptures.append((capture, data))
        }

        try createRootDirectoryIfNeeded()
        let id = UUID()
        let temporaryDirectory = rootDirectory.appendingPathComponent(".pending-\(id.uuidString)", isDirectory: true)
        try createPrivateDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        var records: [PinWorkspacePinRecord] = []
        for encodedCapture in encodedCaptures {
            let pinID = UUID()
            let filename = "\(pinID.uuidString).png"
            try writePrivateData(encodedCapture.data, to: temporaryDirectory.appendingPathComponent(filename))
            records.append(PinWorkspacePinRecord(
                id: pinID,
                imageFilename: filename,
                state: encodedCapture.capture.state,
                metadata: encodedCapture.capture.metadata
            ))
        }

        let now = Date()
        let manifest = PinWorkspaceManifest(
            schemaVersion: PinWorkspaceManifest.currentSchemaVersion,
            id: id,
            name: normalizedName,
            createdAt: now,
            updatedAt: now,
            lastRestoredAt: nil,
            pins: records
        )
        try writeManifest(manifest, to: temporaryDirectory.appendingPathComponent("manifest.json"))
        try fileManager.moveItem(at: temporaryDirectory, to: workspaceDirectory(for: id))
        refresh()
        return manifest.summary
    }

    func load(_ workspace: PinWorkspaceSummary) throws -> PinWorkspaceLoadResult {
        let directory = workspaceDirectory(for: workspace.id)
        let manifest = try readManifest(at: directory)
        guard manifest.id == workspace.id else { throw PinWorkspaceStoreError.workspaceUnavailable }

        var entries: [PinWorkspaceRestoreEntry] = []
        var skippedPinCount = 0
        for record in manifest.pins {
            guard record.state.isValid,
                  Self.isSafeImageFilename(record.imageFilename),
                  let data = readSafeRegularData(
                    at: directory.appendingPathComponent(record.imageFilename),
                    inside: directory
                  ),
                  let image = NSImage(data: data) else {
                skippedPinCount += 1
                continue
            }
            entries.append(PinWorkspaceRestoreEntry(
                image: image,
                state: record.state,
                metadata: record.metadata
            ))
        }
        guard !entries.isEmpty else { throw PinWorkspaceStoreError.noRestorablePins }
        return PinWorkspaceLoadResult(
            workspace: manifest.summary,
            entries: entries,
            skippedPinCount: skippedPinCount
        )
    }

    @discardableResult
    func rename(_ workspace: PinWorkspaceSummary, to name: String) throws -> PinWorkspaceSummary {
        let directory = workspaceDirectory(for: workspace.id)
        let manifest = try readManifest(at: directory)
        let renamed = PinWorkspaceManifest(
            schemaVersion: manifest.schemaVersion,
            id: manifest.id,
            name: try Self.normalizedName(name),
            createdAt: manifest.createdAt,
            updatedAt: Date(),
            lastRestoredAt: manifest.lastRestoredAt,
            pins: manifest.pins
        )
        try writeManifest(renamed, to: directory.appendingPathComponent("manifest.json"))
        refresh()
        return renamed.summary
    }

    @discardableResult
    func duplicate(_ workspace: PinWorkspaceSummary, name: String? = nil) throws -> PinWorkspaceSummary {
        let sourceDirectory = workspaceDirectory(for: workspace.id)
        let sourceManifest = try readManifest(at: sourceDirectory)
        let duplicateName = try Self.normalizedName(name ?? sourceManifest.name)

        var sourceImages: [(record: PinWorkspacePinRecord, data: Data)] = []
        var totalBytes = 0
        for record in sourceManifest.pins {
            guard Self.isSafeImageFilename(record.imageFilename) else {
                throw PinWorkspaceStoreError.workspaceUnavailable
            }
            guard let data = readSafeRegularData(
                at: sourceDirectory.appendingPathComponent(record.imageFilename),
                inside: sourceDirectory
            ) else {
                throw PinWorkspaceStoreError.workspaceUnavailable
            }
            guard NSImage(data: data) != nil else { throw PinWorkspaceStoreError.workspaceUnavailable }
            totalBytes = try Self.checkedPNGByteCount(adding: data.count, to: totalBytes)
            sourceImages.append((record, data))
        }
        guard !sourceImages.isEmpty else { throw PinWorkspaceStoreError.noPins }

        try createRootDirectoryIfNeeded()
        let duplicateID = UUID()
        let temporaryDirectory = rootDirectory.appendingPathComponent(
            ".pending-\(duplicateID.uuidString)", isDirectory: true
        )
        try createPrivateDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        var duplicateRecords: [PinWorkspacePinRecord] = []
        for sourceImage in sourceImages {
            let pinID = UUID()
            let filename = "\(pinID.uuidString).png"
            try writePrivateData(sourceImage.data, to: temporaryDirectory.appendingPathComponent(filename))
            duplicateRecords.append(PinWorkspacePinRecord(
                id: pinID,
                imageFilename: filename,
                state: sourceImage.record.state,
                metadata: sourceImage.record.metadata
            ))
        }

        let now = Date()
        let duplicateManifest = PinWorkspaceManifest(
            schemaVersion: PinWorkspaceManifest.currentSchemaVersion,
            id: duplicateID,
            name: duplicateName,
            createdAt: now,
            updatedAt: now,
            lastRestoredAt: nil,
            pins: duplicateRecords
        )
        try writeManifest(duplicateManifest, to: temporaryDirectory.appendingPathComponent("manifest.json"))
        try fileManager.moveItem(at: temporaryDirectory, to: workspaceDirectory(for: duplicateID))
        refresh()
        return duplicateManifest.summary
    }

    @discardableResult
    func markRestored(_ workspace: PinWorkspaceSummary, at date: Date = Date()) throws -> PinWorkspaceSummary {
        let directory = workspaceDirectory(for: workspace.id)
        let manifest = try readManifest(at: directory)
        let updated = PinWorkspaceManifest(
            schemaVersion: manifest.schemaVersion,
            id: manifest.id,
            name: manifest.name,
            createdAt: manifest.createdAt,
            updatedAt: manifest.updatedAt,
            lastRestoredAt: date,
            pins: manifest.pins
        )
        try writeManifest(updated, to: directory.appendingPathComponent("manifest.json"))
        refresh()
        return updated.summary
    }

    func metadataItems(for workspace: PinWorkspaceSummary) throws -> [PinWorkspaceMetadataItem] {
        try readManifest(at: workspaceDirectory(for: workspace.id)).pins.map {
            PinWorkspaceMetadataItem(id: $0.id, metadata: $0.metadata)
        }
    }

    @discardableResult
    func updateMetadata(
        for pinID: UUID,
        in workspace: PinWorkspaceSummary,
        metadata: PinMetadata
    ) throws -> PinWorkspaceSummary {
        let directory = workspaceDirectory(for: workspace.id)
        let manifest = try readManifest(at: directory)
        guard manifest.pins.contains(where: { $0.id == pinID }) else {
            throw PinWorkspaceStoreError.workspaceUnavailable
        }
        let pins = manifest.pins.map { record in
            guard record.id == pinID else { return record }
            return PinWorkspacePinRecord(
                id: record.id,
                imageFilename: record.imageFilename,
                state: record.state,
                metadata: metadata
            )
        }
        let updated = PinWorkspaceManifest(
            schemaVersion: manifest.schemaVersion,
            id: manifest.id,
            name: manifest.name,
            createdAt: manifest.createdAt,
            updatedAt: Date(),
            lastRestoredAt: manifest.lastRestoredAt,
            pins: pins
        )
        try writeManifest(updated, to: directory.appendingPathComponent("manifest.json"))
        refresh()
        return updated.summary
    }

    func exportPlan(for workspace: PinWorkspaceSummary) throws -> PinWorkspaceExportPlan {
        let directory = workspaceDirectory(for: workspace.id)
        let manifest = try readManifest(at: directory)
        var items: [PinWorkspaceExportItem] = []
        var skippedPinCount = 0
        for (index, record) in manifest.pins.enumerated() {
            guard Self.isSafeImageFilename(record.imageFilename),
                  let data = readSafeRegularData(
                    at: directory.appendingPathComponent(record.imageFilename),
                    inside: directory
                  ),
                  NSImage(data: data) != nil else {
                skippedPinCount += 1
                continue
            }
            items.append(PinWorkspaceExportItem(
                ordinal: index + 1,
                pngData: data,
                metadata: record.metadata
            ))
        }
        guard !items.isEmpty else { throw PinWorkspaceStoreError.noRestorablePins }
        return PinWorkspaceExportPlan(
            workspace: manifest.summary,
            items: items,
            skippedPinCount: skippedPinCount
        )
    }

    func matchingWorkspaces(
        query: String = "",
        sort: PinWorkspaceSort = .updatedNewest
    ) -> [PinWorkspaceSummary] {
        sort.sorted(workspaces.filter { $0.matchesSearch(query) })
    }

    func delete(_ workspace: PinWorkspaceSummary) throws {
        let directory = workspaceDirectory(for: workspace.id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw PinWorkspaceStoreError.workspaceUnavailable
        }
        try fileManager.removeItem(at: directory)
        refresh()
    }

    @discardableResult
    func saveRecoverySession(
        captures: [PinSessionCapture],
        pinsAreVisible: Bool
    ) throws -> PinSessionRecoverySummary? {
        guard captures.count <= Self.maximumPinCount else { throw PinWorkspaceStoreError.tooManyPins }
        guard Set(captures.map(\.id)).count == captures.count else {
            throw PinWorkspaceStoreError.workspaceUnavailable
        }
        if captures.isEmpty {
            try clearRecoverySession()
            return nil
        }

        try createRecoveryDirectoryIfNeeded()
        try invalidateRecoverySession()

        var preparedAssets: [(data: Data, url: URL, needsWrite: Bool)] = []
        preparedAssets.reserveCapacity(captures.count)
        var records: [PinSessionRecoveryRecord] = []
        var totalBytes = 0
        for capture in captures {
            let filename = "\(capture.id.uuidString).png"
            let imageURL = recoveryAssetsDirectory.appendingPathComponent(filename)
            let data: Data
            let needsWrite: Bool
            if let existing = readSafeRegularData(at: imageURL, inside: recoveryAssetsDirectory),
               NSImage(data: existing) != nil {
                data = existing
                needsWrite = false
            } else {
                guard let encoded = capture.image.pngData else {
                    throw PinWorkspaceStoreError.imageEncodingFailed
                }
                data = encoded
                needsWrite = true
            }
            totalBytes = try Self.checkedPNGByteCount(adding: data.count, to: totalBytes)
            let record = PinSessionRecoveryRecord(
                id: capture.id,
                imageFilename: filename,
                state: capture.state,
                metadata: capture.metadata
            )
            records.append(record)
            preparedAssets.append((data, imageURL, needsWrite))
        }
        for asset in preparedAssets {
            if asset.needsWrite {
                try writePrivateData(asset.data, to: asset.url)
            } else {
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: asset.url.path)
            }
        }

        let savedAt = Date()
        let manifest = PinSessionRecoveryManifest(
            schemaVersion: PinSessionRecoveryManifest.currentSchemaVersion,
            savedAt: savedAt,
            pinsAreVisible: pinsAreVisible,
            pins: records
        )
        try writeManifest(manifest, to: recoveryManifestURL)

        let referenced = Set(records.map(\.imageFilename))
        if let assets = try? fileManager.contentsOfDirectory(
            at: recoveryAssetsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for asset in assets where !referenced.contains(asset.lastPathComponent) {
                try? fileManager.removeItem(at: asset)
            }
        }
        return PinSessionRecoverySummary(
            savedAt: savedAt,
            pinCount: records.count,
            pinsAreVisible: pinsAreVisible,
            storageBytes: Int64(totalBytes)
        )
    }

    func loadRecoverySession(
        maxAge: TimeInterval = PinWorkspaceStore.defaultRecoveryMaxAge,
        now: Date = Date()
    ) -> PinSessionRecoveryLoadResult? {
        guard maxAge >= 0,
              isSafeDirectory(recoveryDirectory, inside: rootDirectory),
              isSafeDirectory(recoveryAssetsDirectory, inside: recoveryDirectory),
              let data = readSafeRegularData(at: recoveryManifestURL, inside: recoveryDirectory),
              let manifest = try? JSONDecoder().decode(PinSessionRecoveryManifest.self, from: data),
              manifest.schemaVersion == PinSessionRecoveryManifest.currentSchemaVersion,
              manifest.pins.count <= Self.maximumPinCount else {
            try? clearRecoverySession()
            return nil
        }
        let age = now.timeIntervalSince(manifest.savedAt)
        guard age >= 0, age <= maxAge else {
            try? clearRecoverySession()
            return nil
        }

        var entries: [PinWorkspaceRestoreEntry] = []
        var skippedPinCount = 0
        var totalBytes = 0
        var seenIDs: Set<UUID> = []
        for record in manifest.pins {
            guard seenIDs.insert(record.id).inserted,
                  record.state.isValid,
                  Self.isSafeImageFilename(record.imageFilename),
                  record.imageFilename == "\(record.id.uuidString).png",
                  let imageData = readSafeRegularData(
                    at: recoveryAssetsDirectory.appendingPathComponent(record.imageFilename),
                    inside: recoveryAssetsDirectory
                  ),
                  let nextTotal = try? Self.checkedPNGByteCount(adding: imageData.count, to: totalBytes),
                  let image = NSImage(data: imageData) else {
                skippedPinCount += 1
                continue
            }
            totalBytes = nextTotal
            entries.append(PinWorkspaceRestoreEntry(
                image: image,
                state: record.state,
                metadata: record.metadata
            ))
        }
        guard !entries.isEmpty else {
            try? clearRecoverySession()
            return nil
        }

        let summary = PinSessionRecoverySummary(
            savedAt: manifest.savedAt,
            pinCount: manifest.pins.count,
            pinsAreVisible: manifest.pinsAreVisible,
            storageBytes: Int64(totalBytes)
        )
        return PinSessionRecoveryLoadResult(
            summary: summary,
            entries: entries,
            skippedPinCount: skippedPinCount,
            pinsAreVisible: manifest.pinsAreVisible
        )
    }

    func invalidateRecoverySession() throws {
        guard fileManager.fileExists(atPath: recoveryManifestURL.path) else { return }
        try fileManager.removeItem(at: recoveryManifestURL)
    }

    func clearRecoverySession() throws {
        guard fileManager.fileExists(atPath: recoveryDirectory.path) else { return }
        try fileManager.removeItem(at: recoveryDirectory)
    }

    func recoveryStorageBytes() -> Int64 {
        directoryByteCount(at: recoveryDirectory)
    }

    func storageBytes() -> Int64 {
        (try? storageMetrics().totalBytes) ?? 0
    }

    func storageMetrics() throws -> PinWorkspaceStorageMetrics {
        let recoveryBytes = recoveryStorageBytes()
        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return PinWorkspaceStorageMetrics(
                workspaceCount: 0,
                pinCount: 0,
                workspaceBytes: 0,
                recoveryBytes: 0
            )
        }
        let workspaceDirectories = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let workspaceBytes = workspaceDirectories.reduce(into: Int64(0)) { total, directory in
            guard isSafeDirectory(directory, inside: rootDirectory) else { return }
            total += directoryByteCount(at: directory)
        }
        return PinWorkspaceStorageMetrics(
            workspaceCount: workspaces.count,
            pinCount: workspaces.reduce(0) { $0 + $1.pinCount },
            workspaceBytes: workspaceBytes,
            recoveryBytes: recoveryBytes
        )
    }

    func refresh() {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            workspaces = []
            loadWarningCount = 0
            return
        }

        var summaries: [PinWorkspaceSummary] = []
        var warnings = 0
        for directory in directories {
            guard isSafeDirectory(directory, inside: rootDirectory) else {
                warnings += 1
                continue
            }
            do {
                summaries.append(try readManifest(at: directory).summary)
            } catch {
                warnings += 1
            }
        }
        workspaces = PinWorkspaceSort.updatedNewest.sorted(summaries)
        loadWarningCount = warnings
    }

    private func readManifest(at directory: URL) throws -> PinWorkspaceManifest {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard isSafeDirectory(directory, inside: rootDirectory),
              let data = readSafeRegularData(at: manifestURL, inside: directory) else {
            throw PinWorkspaceStoreError.workspaceUnavailable
        }
        let manifest: PinWorkspaceManifest
        do {
            manifest = try JSONDecoder().decode(PinWorkspaceManifest.self, from: data)
        } catch {
            throw PinWorkspaceStoreError.workspaceUnavailable
        }
        guard manifest.schemaVersion == PinWorkspaceManifest.currentSchemaVersion else {
            throw PinWorkspaceStoreError.unsupportedSchema
        }
        guard directory.lastPathComponent == manifest.id.uuidString,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 80,
              !manifest.pins.isEmpty,
              manifest.pins.count <= Self.maximumPinCount,
              Set(manifest.pins.map(\.id)).count == manifest.pins.count else {
            throw PinWorkspaceStoreError.workspaceUnavailable
        }
        return manifest
    }

    private func createRootDirectoryIfNeeded() throws {
        try createPrivateDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    private func createRecoveryDirectoryIfNeeded() throws {
        try createRootDirectoryIfNeeded()
        try createPrivateDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        try createPrivateDirectory(at: recoveryAssetsDirectory, withIntermediateDirectories: true)
    }

    private func createPrivateDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: withIntermediateDirectories,
            attributes: [.posixPermissions: 0o700]
        )
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw PinWorkspaceStoreError.workspaceUnavailable
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func writePrivateData(_ data: Data, to url: URL) throws {
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            throw PinWorkspaceStoreError.workspaceUnavailable
        }
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func writeManifest<T: Encodable>(_ manifest: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try writePrivateData(try encoder.encode(manifest), to: url)
    }

    private func directoryByteCount(at directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            ) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true, let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    private func isSafeDirectory(_ directory: URL, inside parent: URL) -> Bool {
        guard directory.standardizedFileURL.deletingLastPathComponent() == parent.standardizedFileURL,
              let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func readSafeRegularData(at url: URL, inside directory: URL) -> Data? {
        guard url.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func workspaceDirectory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private var recoveryDirectory: URL {
        rootDirectory.appendingPathComponent(".session-recovery", isDirectory: true)
    }

    private var recoveryAssetsDirectory: URL {
        recoveryDirectory.appendingPathComponent("assets", isDirectory: true)
    }

    private var recoveryManifestURL: URL {
        recoveryDirectory.appendingPathComponent("current.json")
    }

    private static func normalizedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw PinWorkspaceStoreError.invalidName }
        return name
    }

    private static func checkedPNGByteCount(adding byteCount: Int, to total: Int) throws -> Int {
        let (newTotal, overflow) = total.addingReportingOverflow(byteCount)
        guard !overflow, newTotal <= maximumPNGBytes else {
            throw PinWorkspaceStoreError.storageLimitExceeded
        }
        return newTotal
    }

    private static func isSafeImageFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename == URL(fileURLWithPath: filename).lastPathComponent
            && filename.lowercased().hasSuffix(".png")
    }
}
