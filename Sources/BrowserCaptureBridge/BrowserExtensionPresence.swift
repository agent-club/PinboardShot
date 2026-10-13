import Foundation
import Darwin

/// A short-lived handshake receipt, containing only the fixed extension ID and time.
/// Expiry prevents a removed extension from remaining marked as connected forever.
public struct BrowserExtensionPresenceStore: Sendable {
    private struct Receipt: Codable {
        let extensionID: String
        let updatedAt: Date
    }

    private let inbox: BrowserCaptureInbox
    public static let expiryInterval: TimeInterval = 150

    public init(inbox: BrowserCaptureInbox = BrowserCaptureInbox()) { self.inbox = inbox }

    public func record(extensionID: String, now: Date = .now) throws {
        guard knownIDs.contains(extensionID) else { throw BrowserCaptureBridgeError.invalidIdentifier }
        try inbox.ensureSecureRoot(create: true)
        let data = try JSONEncoder().encode(Receipt(extensionID: extensionID, updatedAt: now))
        let destination = receiptURL(extensionID)
        let temporary = inbox.rootURL.appendingPathComponent(".presence-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw BrowserCaptureBridgeError.unsafePath }
        defer { close(descriptor); unlink(temporary.path) }
        let count = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard count == data.count, rename(temporary.path, destination.path) == 0 else {
            throw BrowserCaptureBridgeError.unsafePath
        }
    }

    public func connectedExtensionIDs(now: Date = .now) throws -> [String] {
        guard FileManager.default.fileExists(atPath: inbox.rootURL.path) else { return [] }
        try inbox.ensureSecureRoot(create: false)
        return knownIDs.filter { id in
            let descriptor = open(receiptURL(id).path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { return false }
            defer { close(descriptor) }
            var info = stat()
            guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_size > 0, info.st_size <= 4096 else { return false }
            var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            guard count == bytes.count,
                  let receipt = try? JSONDecoder().decode(Receipt.self, from: Data(bytes)),
                  receipt.extensionID == id, receipt.updatedAt <= now,
                  now.timeIntervalSince(receipt.updatedAt) < Self.expiryInterval else { return false }
            return true
        }
    }

    private var knownIDs: [String] {
        [BrowserCaptureConfiguration.extensionID, BrowserCaptureConfiguration.localExtensionID]
    }

    private func receiptURL(_ id: String) -> URL {
        inbox.rootURL.appendingPathComponent("extension-\(id).json")
    }
}
