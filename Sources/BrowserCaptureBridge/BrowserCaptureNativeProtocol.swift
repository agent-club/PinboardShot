import Foundation

public struct BrowserCaptureProtocolReply: Sendable {
    public let data: Data
    public let captureReadyToOpen: UUID?

    public init(data: Data, captureReadyToOpen: UUID? = nil) {
        self.data = data
        self.captureReadyToOpen = captureReadyToOpen
    }
}

/// Stateful command handler for one Chrome Native Messaging connection.
public final class BrowserCaptureProtocolProcessor {
    private let inbox: BrowserCaptureInbox
    private var writer: BrowserCaptureWriter?
    private var activeID: UUID?

    public init(inbox: BrowserCaptureInbox = BrowserCaptureInbox()) {
        self.inbox = inbox
    }

    public func process(_ data: Data) -> BrowserCaptureProtocolReply {
        var requestID = ""
        do {
            guard data.count <= BrowserCaptureConfiguration.maximumMessageBytes,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["requestId"] as? String, !id.isEmpty, id.utf8.count <= 128,
                  let command = object["command"] as? String else {
                throw BrowserCaptureBridgeError.invalidSession
            }
            requestID = id
            let response: [String: Any]
            var captureToOpen: UUID?
            switch command {
            case "hello":
                guard int(object["protocolVersion"]) == BrowserCaptureConfiguration.protocolVersion else {
                    throw BrowserCaptureBridgeError.invalidSession
                }
                response = ["requestId": id, "ok": true, "protocolVersion": BrowserCaptureConfiguration.protocolVersion,
                            "maxChunkBytes": BrowserCaptureLimits.maximumChunkBytes]
            case "begin":
                guard writer == nil else { throw BrowserCaptureBridgeError.invalidSession }
                let captureID = UUID()
                writer = try inbox.makeWriter(id: captureID)
                activeID = captureID
                response = ["requestId": id, "ok": true, "captureId": captureID.uuidString.lowercased()]
            case "tileBegin":
                let active = try requireActive(object)
                guard let tileIndex = int(object["index"]),
                      let scrollY = number(object["scrollY"]),
                      let viewportWidth = number(object["viewportWidth"]),
                      let viewportHeight = number(object["viewportHeight"]),
                      let documentHeight = number(object["documentHeight"]),
                      let base64Length = int(object["base64Length"]) else { throw BrowserCaptureBridgeError.invalidTile }
                try active.beginTile(index: tileIndex, scrollY: scrollY, viewportWidth: viewportWidth,
                                     viewportHeight: viewportHeight, documentHeight: documentHeight,
                                     base64Length: base64Length)
                response = ["requestId": id, "ok": true]
            case "tileChunk":
                let active = try requireActive(object)
                guard let index = int(object["index"]), let sequence = int(object["sequence"]),
                      let base64 = object["data"] as? String else { throw BrowserCaptureBridgeError.invalidChunk }
                try active.appendChunk(index: index, sequence: sequence, base64: base64)
                response = ["requestId": id, "ok": true]
            case "tileEnd":
                let active = try requireActive(object)
                guard let index = int(object["index"]) else { throw BrowserCaptureBridgeError.invalidTile }
                _ = try active.endTile(index: index)
                response = ["requestId": id, "ok": true]
            case "finish":
                let active = try requireActive(object)
                guard let height = number(object["capturedHeight"]) else { throw BrowserCaptureBridgeError.invalidManifest }
                _ = try active.finish(capturedHeight: height)
                captureToOpen = active.id
                writer = nil
                activeID = nil
                response = ["requestId": id, "ok": true, "captureId": captureToOpen!.uuidString.lowercased()]
            case "cancel":
                let active = try requireActive(object)
                try active.cancel()
                writer = nil
                activeID = nil
                response = ["requestId": id, "ok": true]
            default:
                throw BrowserCaptureBridgeError.invalidSession
            }
            return BrowserCaptureProtocolReply(data: try encode(response), captureReadyToOpen: captureToOpen)
        } catch {
            let response: [String: Any] = ["requestId": requestID, "ok": false, "error": errorCode(error)]
            return BrowserCaptureProtocolReply(data: (try? encode(response)) ?? Data("{}".utf8))
        }
    }

    public func cancelPartialSession() {
        try? writer?.cancel()
        writer = nil
        activeID = nil
    }

    private func requireActive(_ object: [String: Any]) throws -> BrowserCaptureWriter {
        guard let writer, let activeID,
              let rawID = object["captureId"] as? String,
              let supplied = UUID(uuidString: rawID), supplied == activeID else {
            throw BrowserCaptureBridgeError.invalidSession
        }
        return writer
    }

    private func encode(_ object: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= BrowserCaptureConfiguration.maximumMessageBytes else { throw BrowserCaptureBridgeError.sizeLimit }
        return data
    }

    private func errorCode(_ error: Error) -> String {
        guard let error = error as? BrowserCaptureBridgeError else { return "capture_failed" }
        switch error {
        case .invalidIdentifier, .invalidSession: return "invalid_session"
        case .expired: return "expired"
        case .unsafePath: return "storage_error"
        case .invalidManifest: return "invalid_manifest"
        case .missingTile: return "missing_tile"
        case .sizeLimit: return "size_limit"
        case .invalidImage: return "invalid_image"
        case .invalidTile: return "invalid_tile"
        case .invalidChunk: return "invalid_chunk"
        case .incompleteTile: return "incomplete_tile"
        case .noTiles: return "no_tiles"
        }
    }

    private func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let result = value.doubleValue
        return result.isFinite ? result : nil
    }

    private func int(_ value: Any?) -> Int? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let double = value.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return value.intValue
    }
}
