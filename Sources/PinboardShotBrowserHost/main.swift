import AppKit
import BrowserCaptureBridge
import Foundation

@main
struct PinboardShotBrowserHost {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count == 2,
              CommandLine.arguments[1] == BrowserCaptureConfiguration.allowedOrigin else {
            FileHandle.standardError.write(Data("PinboardShot browser host: extension origin denied\n".utf8))
            exit(EXIT_FAILURE)
        }

        let inbox = BrowserCaptureInbox()
        try? inbox.cleanupExpired()
        let processor = BrowserCaptureProtocolProcessor(inbox: inbox)
        do {
            while let message = try readMessage() {
                let reply = processor.process(message)
                if let captureID = reply.captureReadyToOpen {
                    if !openCaptureInInstalledApp(captureID) {
                        try writeMessage(appOpenFailureResponse(from: reply.data, id: captureID))
                        continue
                    }
                }
                try writeMessage(reply.data)
            }
        } catch {
            processor.cancelPartialSession()
            FileHandle.standardError.write(Data("PinboardShot browser host: native messaging stream failed\n".utf8))
            exit(EXIT_FAILURE)
        }
        processor.cancelPartialSession()
    }

    private static func readMessage() throws -> Data? {
        guard let header = try readExactly(4, allowEOF: true) else { return nil }
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        guard length > 0, length <= BrowserCaptureConfiguration.maximumMessageBytes else {
            throw BrowserCaptureBridgeError.sizeLimit
        }
        guard let message = try readExactly(Int(length), allowEOF: false) else {
            throw BrowserCaptureBridgeError.invalidSession
        }
        return message
    }

    private static func readExactly(_ count: Int, allowEOF: Bool) throws -> Data? {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            guard let part = try FileHandle.standardInput.read(upToCount: count - result.count), !part.isEmpty else {
                if result.isEmpty && allowEOF { return nil }
                throw BrowserCaptureBridgeError.invalidSession
            }
            result.append(part)
        }
        return result
    }

    private static func writeMessage(_ message: Data) throws {
        let frame = try BrowserCaptureNativeMessageFraming.frame(message)
        try FileHandle.standardOutput.write(contentsOf: frame)
    }

    @MainActor
    private static func openCaptureInInstalledApp(_ id: UUID) -> Bool {
        var components = URLComponents()
        components.scheme = "pinboardshot"
        components.host = "browser-import"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString.lowercased())]
        guard let captureURL = components.url else { return false }

        let appURL = URL(fileURLWithPath: "/Applications/PinboardShot.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Contents/MacOS/PinboardShot").path) else {
            return false
        }
        let result = OpenCompletionResult()
        NSWorkspace.shared.open([captureURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { application, error in
            result.resolve(application != nil && error == nil)
        }
        let deadline = Date(timeIntervalSinceNow: 20)
        while !result.isComplete && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return result.didSucceed
    }

    private static func appOpenFailureResponse(from data: Data, id: UUID) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        object["ok"] = false
        object["error"] = "app_open_failed"
        object["captureSaved"] = true
        object["captureId"] = id.uuidString.lowercased()
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private final class OpenCompletionResult: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var success = false

    var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    var didSucceed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return success
    }

    func resolve(_ value: Bool) {
        lock.lock()
        success = value
        completed = true
        lock.unlock()
    }
}
