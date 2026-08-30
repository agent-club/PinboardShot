import AppKit
import CryptoKit
import Foundation
import Security

struct InvisibleWatermarkSettings: Sendable {
    static let enabledDefaultsKey = "invisibleWatermark.enabled"
    static let customTextDefaultsKey = "invisibleWatermark.customText"
    static let projectDefaultsKey = "invisibleWatermark.project"
    static let recipientDefaultsKey = "invisibleWatermark.recipient"

    let enabled: Bool
    let customText: String
    let project: String
    let recipient: String

    static func current(defaults: UserDefaults = .standard) -> Self {
        Self(
            enabled: defaults.bool(forKey: enabledDefaultsKey),
            customText: defaults.string(forKey: customTextDefaultsKey) ?? "",
            project: defaults.string(forKey: projectDefaultsKey) ?? "",
            recipient: defaults.string(forKey: recipientDefaultsKey) ?? ""
        )
    }
}

struct InvisibleWatermarkRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let customText: String
    let project: String
    let recipient: String
    let appVersion: String
    let protocolVersion: Int
    let imageSHA256: String
    let signature: Data
}

enum InvisibleWatermarkDetection: Sendable {
    case notFound
    case recordMissing(id: UUID)
    case invalidRecord(id: UUID)
    case verified(record: InvisibleWatermarkRecord, exactImage: Bool)
}

struct WatermarkedCapture {
    let image: NSImage
    let pngData: Data
}

@MainActor
/// 保存“随机截图 ID → 用户填写信息”的本地映射；密钥仅在首次签名或验签时从钥匙串加载。
final class InvisibleWatermarkStore: ObservableObject {
    @Published private(set) var records: [InvisibleWatermarkRecord] = []

    private let fileManager: FileManager
    private let directoryURL: URL
    private var signingKey: SymmetricKey?
    private let loadsKeychainKey: Bool

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        signingKeyData: Data? = nil
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
        signingKey = signingKeyData.map(SymmetricKey.init(data:))
        loadsKeychainKey = signingKeyData == nil
        loadRecords()
    }

    func add(
        id: UUID,
        createdAt: Date,
        settings: InvisibleWatermarkSettings,
        imageSHA256: String
    ) throws -> InvisibleWatermarkRecord {
        guard let signingKey = resolvedSigningKey() else { throw InvisibleWatermarkError.keyUnavailable }
        let unsigned = UnsignedWatermarkRecord(
            id: id,
            createdAt: createdAt,
            customText: settings.customText,
            project: settings.project,
            recipient: settings.recipient,
            appVersion: Self.appVersion,
            protocolVersion: InvisibleWatermarkCodec.protocolVersion,
            imageSHA256: imageSHA256
        )
        let signature = Data(HMAC<SHA256>.authenticationCode(for: try unsigned.signingData(), using: signingKey))
        let record = InvisibleWatermarkRecord(
            id: unsigned.id,
            createdAt: unsigned.createdAt,
            customText: unsigned.customText,
            project: unsigned.project,
            recipient: unsigned.recipient,
            appVersion: unsigned.appVersion,
            protocolVersion: unsigned.protocolVersion,
            imageSHA256: unsigned.imageSHA256,
            signature: signature
        )
        records.insert(record, at: 0)
        do {
            try persistRecords()
        } catch {
            records.removeAll { $0.id == id }
            throw error
        }
        return record
    }

    func record(for id: UUID) -> InvisibleWatermarkRecord? {
        records.first { $0.id == id }
    }

    func isAuthentic(_ record: InvisibleWatermarkRecord) -> Bool {
        guard let signingKey = resolvedSigningKey(),
              let signingData = try? UnsignedWatermarkRecord(record: record).signingData() else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(record.signature, authenticating: signingData, using: signingKey)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
        records = []
    }

    private var recordsURL: URL { directoryURL.appendingPathComponent("records.json") }

    private func resolvedSigningKey() -> SymmetricKey? {
        if let signingKey { return signingKey }
        guard loadsKeychainKey,
              let keyData = try? InvisibleWatermarkKeychain.loadOrCreateKey() else { return nil }
        let key = SymmetricKey(data: keyData)
        signingKey = key
        return key
    }

    private func loadRecords() {
        guard let data = try? Data(contentsOf: recordsURL),
              let decoded = try? JSONDecoder().decode([InvisibleWatermarkRecord].self, from: data) else { return }
        records = decoded
    }

    private func persistRecords() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: recordsURL, options: [.atomic, .completeFileProtection])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordsURL.path)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PinboardShot/InvisibleWatermarks", isDirectory: true)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}

@MainActor
final class InvisibleWatermarkService {
    let store: InvisibleWatermarkStore
    private let defaults: UserDefaults

    init(store: InvisibleWatermarkStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    convenience init(defaults: UserDefaults = .standard) {
        self.init(store: InvisibleWatermarkStore(), defaults: defaults)
    }

    func prepareCapture(_ image: NSImage) throws -> WatermarkedCapture {
        let settings = InvisibleWatermarkSettings.current(defaults: defaults)
        guard settings.enabled else {
            guard let pngData = image.pngData else { throw PinboardShotError.imageEncodingFailed }
            return WatermarkedCapture(
                image: try compressedImage(from: pngData, logicalSize: image.size),
                pngData: pngData
            )
        }

        // 先完成像素嵌入和本地签名记录，再把图片发布到剪贴板，避免静默输出未受保护的截图。
        let id = UUID()
        let createdAt = Date()
        let markedImage = try InvisibleWatermarkCodec.embed(id: id, in: image)
        guard let pngData = markedImage.pngData else { throw PinboardShotError.imageEncodingFailed }
        let hash = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()
        _ = try store.add(id: id, createdAt: createdAt, settings: settings, imageSHA256: hash)
        return WatermarkedCapture(
            image: try compressedImage(from: pngData, logicalSize: image.size),
            pngData: pngData
        )
    }

    func detect(in imageData: Data) -> InvisibleWatermarkDetection {
        guard let image = NSImage(data: imageData),
              let id = try? InvisibleWatermarkCodec.detect(in: image) else { return .notFound }
        guard let record = store.record(for: id) else { return .recordMissing(id: id) }
        guard store.isAuthentic(record) else { return .invalidRecord(id: id) }
        let hash = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        return .verified(record: record, exactImage: hash == record.imageSHA256)
    }

    private func compressedImage(from pngData: Data, logicalSize: CGSize) throws -> NSImage {
        guard let encodedImage = NSImage(data: pngData) else {
            throw PinboardShotError.imageEncodingFailed
        }
        encodedImage.size = logicalSize
        return encodedImage
    }
}

enum InvisibleWatermarkCodec {
    static let protocolVersion = 1
    static let minimumWidth = 320
    static let minimumHeight = 200

    private static let magic: [UInt8] = [0xB5, 0x7D]
    private static let payloadByteCount = 20
    private static let payloadBitCount = payloadByteCount * 8
    private static let tileColumns = 16
    private static let tileRows = 10
    private static let horizontalRepeats = 2
    private static let verticalRepeats = 2
    private static let patternDivisions = 4
    private static let strength = 4

    static func embed(id: UUID, in image: NSImage) throws -> NSImage {
        guard let source = cgImage(from: image), source.width >= minimumWidth, source.height >= minimumHeight else {
            throw InvisibleWatermarkError.imageTooSmall
        }
        let payload = makePayload(id: id)
        guard let context = rgbaContext(width: source.width, height: source.height) else {
            throw InvisibleWatermarkError.imageConversionFailed
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw InvisibleWatermarkError.imageConversionFailed
        }

        // 160 位载荷在画面中重复四次，并用低强度棋盘亮度扰动编码，兼顾不可见性与缩放/压缩恢复。
        let gridColumns = tileColumns * horizontalRepeats
        let gridRows = tileRows * verticalRepeats
        for y in 0..<source.height {
            let gridY = min(gridRows - 1, y * gridRows / source.height)
            let cellY = gridY % tileRows
            let localY = (y * gridRows * patternDivisions / source.height) % patternDivisions
            for x in 0..<source.width {
                let gridX = min(gridColumns - 1, x * gridColumns / source.width)
                let bitIndex = cellY * tileColumns + (gridX % tileColumns)
                let byte = payload[bitIndex / 8]
                let isOne = byte & (1 << (7 - bitIndex % 8)) != 0
                let localX = (x * gridColumns * patternDivisions / source.width) % patternDivisions
                let checkerSign = (localX + localY).isMultiple(of: 2) ? 1 : -1
                let delta = checkerSign * (isOne ? strength : -strength)
                let offset = (y * source.width + x) * 4
                bytes[offset] = adjusted(bytes[offset], by: delta)
                bytes[offset + 1] = adjusted(bytes[offset + 1], by: delta)
                bytes[offset + 2] = adjusted(bytes[offset + 2], by: delta)
            }
        }

        guard let marked = context.makeImage() else { throw InvisibleWatermarkError.imageConversionFailed }
        return NSImage(cgImage: marked, size: image.size)
    }

    static func detect(in image: NSImage) throws -> UUID? {
        guard let source = cgImage(from: image), source.width >= minimumWidth, source.height >= minimumHeight else {
            throw InvisibleWatermarkError.imageTooSmall
        }
        guard let context = rgbaContext(width: source.width, height: source.height) else {
            throw InvisibleWatermarkError.imageConversionFailed
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw InvisibleWatermarkError.imageConversionFailed
        }

        for transform in detectionTransforms {
            let payload = decodePayload(
                bytes: bytes,
                width: source.width,
                height: source.height,
                transform: transform
            )
            if let id = parsePayload(payload) { return id }
        }
        return nil
    }

    private static func makePayload(id: UUID) -> [UInt8] {
        var payload = magic + [UInt8(protocolVersion)]
        var uuid = id.uuid
        withUnsafeBytes(of: &uuid) { payload.append(contentsOf: $0) }
        payload.append(crc8(payload))
        return payload
    }

    private static func parsePayload(_ payload: [UInt8]) -> UUID? {
        guard payload.count == payloadByteCount,
              Array(payload.prefix(2)) == magic,
              payload[2] == UInt8(protocolVersion),
              crc8(Array(payload.dropLast())) == payload.last else { return nil }
        let uuidBytes = Array(payload[3..<19])
        return uuidBytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return NSUUID(uuidBytes: baseAddress) as UUID
        }
    }

    private static func decodePayload(
        bytes: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        transform: DetectionTransform
    ) -> [UInt8] {
        var scores = [Double](repeating: 0, count: payloadBitCount)
        let step = max(1, min(width / 640, height / 400))
        let gridColumns = tileColumns * horizontalRepeats
        let gridRows = tileRows * verticalRepeats

        for y in stride(from: 0, to: height, by: step) {
            let normalizedY = transform.top + (Double(y) + 0.5) / Double(height) * transform.heightSpan
            guard normalizedY >= 0, normalizedY < 1 else { continue }
            let scaledY = normalizedY * Double(gridRows)
            let gridY = min(gridRows - 1, Int(scaledY))
            let cellY = gridY % tileRows
            let localY = min(patternDivisions - 1, Int((scaledY - floor(scaledY)) * Double(patternDivisions)))
            for x in stride(from: 0, to: width, by: step) {
                let normalizedX = transform.left + (Double(x) + 0.5) / Double(width) * transform.widthSpan
                guard normalizedX >= 0, normalizedX < 1 else { continue }
                let scaledX = normalizedX * Double(gridColumns)
                let gridX = min(gridColumns - 1, Int(scaledX))
                let bitIndex = cellY * tileColumns + (gridX % tileColumns)
                let localX = min(patternDivisions - 1, Int((scaledX - floor(scaledX)) * Double(patternDivisions)))
                let checkerSign = (localX + localY).isMultiple(of: 2) ? 1.0 : -1.0
                let offset = (y * width + x) * 4
                let luminance = 0.2126 * Double(bytes[offset])
                    + 0.7152 * Double(bytes[offset + 1])
                    + 0.0722 * Double(bytes[offset + 2])
                scores[bitIndex] += luminance * checkerSign
            }
        }

        var payload = [UInt8](repeating: 0, count: payloadByteCount)
        for bitIndex in 0..<payloadBitCount where scores[bitIndex] > 0 {
            payload[bitIndex / 8] |= 1 << (7 - bitIndex % 8)
        }
        return payload
    }

    // 检测时尝试原图和至多 15% 的常见边缘裁剪映射；校验头与 CRC 共同过滤误报。
    private static let detectionTransforms: [DetectionTransform] = {
        var result = [DetectionTransform(left: 0, top: 0, widthSpan: 1, heightSpan: 1)]
        for widthSpan in [0.95, 0.90, 0.85] {
            for heightSpan in [1.0, 0.95, 0.90, 0.85] {
                let horizontalMargin = 1 - widthSpan
                let verticalMargin = 1 - heightSpan
                for left in [0.0, horizontalMargin / 2, horizontalMargin] {
                    for top in [0.0, verticalMargin / 2, verticalMargin] {
                        result.append(DetectionTransform(left: left, top: top, widthSpan: widthSpan, heightSpan: heightSpan))
                    }
                }
            }
        }
        return result
    }()

    private static func crc8(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(0) { partial, byte in
            var crc = partial ^ byte
            for _ in 0..<8 { crc = crc & 0x80 != 0 ? (crc << 1) ^ 0x07 : crc << 1 }
            return crc
        }
    }

    private static func adjusted(_ value: UInt8, by delta: Int) -> UInt8 {
        UInt8(clamping: Int(value) + delta)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func rgbaContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }
}

enum InvisibleWatermarkError: LocalizedError {
    case imageTooSmall
    case imageConversionFailed
    case keyUnavailable

    var errorDescription: String? {
        switch self {
        case .imageTooSmall: L10n.text("watermark.error.imageTooSmall")
        case .imageConversionFailed: L10n.text("watermark.error.imageConversionFailed")
        case .keyUnavailable: L10n.text("watermark.error.keyUnavailable")
        }
    }
}

private struct DetectionTransform {
    let left: Double
    let top: Double
    let widthSpan: Double
    let heightSpan: Double
}

private struct UnsignedWatermarkRecord: Codable {
    let id: UUID
    let createdAt: Date
    let customText: String
    let project: String
    let recipient: String
    let appVersion: String
    let protocolVersion: Int
    let imageSHA256: String

    init(
        id: UUID,
        createdAt: Date,
        customText: String,
        project: String,
        recipient: String,
        appVersion: String,
        protocolVersion: Int,
        imageSHA256: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.customText = customText
        self.project = project
        self.recipient = recipient
        self.appVersion = appVersion
        self.protocolVersion = protocolVersion
        self.imageSHA256 = imageSHA256
    }

    init(record: InvisibleWatermarkRecord) {
        self.init(
            id: record.id,
            createdAt: record.createdAt,
            customText: record.customText,
            project: record.project,
            recipient: record.recipient,
            appVersion: record.appVersion,
            protocolVersion: record.protocolVersion,
            imageSHA256: record.imageSHA256
        )
    }

    func signingData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }
}

private enum InvisibleWatermarkKeychain {
    private static let service = "com.agent-club.PinboardShot.invisible-watermark"
    private static let account = "local-signing-key-v1"

    static func loadOrCreateKey() throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        guard status == errSecItemNotFound else { throw InvisibleWatermarkError.keyUnavailable }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw InvisibleWatermarkError.keyUnavailable
        }
        let data = Data(bytes)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw InvisibleWatermarkError.keyUnavailable
        }
        return data
    }
}
