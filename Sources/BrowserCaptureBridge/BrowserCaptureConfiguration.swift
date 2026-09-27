import Foundation

public enum BrowserCaptureConfiguration {
    public static let hostName = "com.ryanwang.pinboardshot.browser_capture"
    public static let extensionID = "olghjpagobkdfmiphmabpapcfgjfdeaf"
    public static let allowedOrigin = "chrome-extension://\(extensionID)/"
    public static let protocolVersion = 1
    public static let maximumMessageBytes = 1 * 1024 * 1024
}

public enum BrowserCaptureNativeMessageFraming {
    public static func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= BrowserCaptureConfiguration.maximumMessageBytes else {
            throw BrowserCaptureBridgeError.sizeLimit
        }
        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        return frame
    }

    public static func payload(from frame: Data) throws -> Data {
        guard frame.count >= 4 else { throw BrowserCaptureBridgeError.invalidSession }
        let length = frame.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        guard length > 0, length <= BrowserCaptureConfiguration.maximumMessageBytes,
              frame.count == Int(length) + 4 else { throw BrowserCaptureBridgeError.sizeLimit }
        return frame.suffix(Int(length))
    }
}
