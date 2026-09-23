import Foundation

struct CaptureGuideRecoverySettings {
    static let defaultsKey = "captureGuideRecoveryEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }
}

actor CaptureGuideRecoveryStore {
    private struct Draft: Codable {
        let savedAt: Date
        let guide: CaptureGuide
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let retentionInterval: TimeInterval = 24 * 60 * 60

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support.appendingPathComponent("PinboardShot/GuideRecovery/draft.json")
        }
    }

    func save(_ guide: CaptureGuide, now: Date = .now) throws {
        // Images enter the editor through validated imports; avoid decoding every step after each text edit.
        try guide.validateStructure()
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(Draft(savedAt: now, guide: guide))
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func load(now: Date = .now) throws -> CaptureGuide? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.int64Value <= 256 * 1_024 * 1_024 else {
            try clear()
            return nil
        }
        let draft = try JSONDecoder().decode(Draft.self, from: Data(contentsOf: fileURL))
        guard draft.savedAt <= now,
              now.timeIntervalSince(draft.savedAt) <= retentionInterval else {
            try clear()
            return nil
        }
        try draft.guide.validate()
        return draft.guide
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
