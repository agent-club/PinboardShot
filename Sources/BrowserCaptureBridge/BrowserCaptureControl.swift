import Foundation
import Darwin

public enum BrowserCaptureControlStatus: String, Codable, Sendable {
    case preparing, capturing, pausing, paused, stopping, cancelling, complete
}

public struct BrowserCaptureControlState: Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let status: BrowserCaptureControlStatus
    public let progress: Int
}

public struct BrowserCaptureControlRequest: Codable, Sendable {
    public let paused: Bool
    public let stopped: Bool
}

/// App controls stay on disk beside the UUID-scoped native session. No page data
/// or network endpoint is needed, and each side owns a separate atomic file.
public struct BrowserCaptureControlStore: Sendable {
    private let inbox: BrowserCaptureInbox

    public init(inbox: BrowserCaptureInbox = BrowserCaptureInbox()) { self.inbox = inbox }

    public func begin(id: UUID, now: Date = .now) throws {
        try write(BrowserCaptureControlRequest(paused: false, stopped: false), id: id, file: "control-request.json")
        try write(BrowserCaptureControlState(id: id, createdAt: now, updatedAt: now,
                                            status: .preparing, progress: 0), id: id, file: "control-status.json")
    }

    public func state(id: UUID) throws -> BrowserCaptureControlState {
        let state: BrowserCaptureControlState = try read(id: id, file: "control-status.json")
        guard state.id == id, (0...100).contains(state.progress) else { throw BrowserCaptureBridgeError.invalidSession }
        return state
    }

    public func request(id: UUID) throws -> BrowserCaptureControlRequest {
        try read(id: id, file: "control-request.json")
    }

    public func setRequest(id: UUID, paused: Bool, stopped: Bool) throws {
        let directory = try inbox.checkedCaptureDirectory(id: id)
        let descriptor = open(directory.appendingPathComponent("control.lock").path,
                              O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw BrowserCaptureBridgeError.unsafePath }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              flock(descriptor, LOCK_EX) == 0 else { throw BrowserCaptureBridgeError.unsafePath }
        defer { flock(descriptor, LOCK_UN) }
        // App and popup commands are separate processes. Serialize their reads
        // and writes so a concurrent Resume can never overwrite a terminal Stop.
        let previous = try request(id: id)
        // Stop is terminal: a late Resume click cannot restart a finishing capture.
        try write(BrowserCaptureControlRequest(paused: paused, stopped: previous.stopped || stopped),
                  id: id, file: "control-request.json")
    }

    public func update(id: UUID, status: BrowserCaptureControlStatus, progress: Int, now: Date = .now) throws {
        let previous = try state(id: id)
        guard (0...100).contains(progress) else { throw BrowserCaptureBridgeError.invalidSession }
        try write(BrowserCaptureControlState(id: id, createdAt: previous.createdAt, updatedAt: now,
                                            status: status, progress: progress), id: id, file: "control-status.json")
    }

    public func activeStates(since: Date, now: Date = .now) throws -> [BrowserCaptureControlState] {
        guard FileManager.default.fileExists(atPath: inbox.rootURL.path) else { return [] }
        try inbox.ensureSecureRoot(create: false)
        let entries = try FileManager.default.contentsOfDirectory(at: inbox.rootURL, includingPropertiesForKeys: nil)
        return entries.compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent), let state = try? state(id: id),
                  state.createdAt >= since, state.updatedAt <= now,
                  now.timeIntervalSince(state.updatedAt) < 10, state.status != .complete else { return nil }
            return state
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func read<T: Decodable>(id: UUID, file: String) throws -> T {
        let directory = try inbox.checkedCaptureDirectory(id: id)
        let url = directory.appendingPathComponent(file)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw BrowserCaptureBridgeError.unsafePath }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= 4096 else { throw BrowserCaptureBridgeError.unsafePath }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
        guard count == bytes.count else { throw BrowserCaptureBridgeError.unsafePath }
        return try JSONDecoder().decode(T.self, from: Data(bytes))
    }

    private func write<T: Encodable>(_ value: T, id: UUID, file: String) throws {
        let directory = try inbox.checkedCaptureDirectory(id: id)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 4096 else { throw BrowserCaptureBridgeError.sizeLimit }
        let temporary = directory.appendingPathComponent(".\(file).\(UUID().uuidString).tmp")
        let destination = directory.appendingPathComponent(file)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw BrowserCaptureBridgeError.unsafePath }
        defer { close(descriptor); unlink(temporary.path) }
        let count = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard count == data.count, rename(temporary.path, destination.path) == 0 else {
            throw BrowserCaptureBridgeError.unsafePath
        }
    }
}
