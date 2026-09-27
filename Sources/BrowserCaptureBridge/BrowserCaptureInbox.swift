import CoreGraphics
import Foundation
import ImageIO

public struct BrowserCaptureTile: Codable, Equatable, Sendable {
    public let index: Int
    public let scrollY: Double
    public let viewportWidth: Double
    public let viewportHeight: Double
    public let documentHeight: Double
    public let pngPixelWidth: Int
    public let pngPixelHeight: Int
    public let fileName: String

    public init(index: Int, scrollY: Double, viewportWidth: Double, viewportHeight: Double,
                documentHeight: Double, pngPixelWidth: Int, pngPixelHeight: Int, fileName: String) {
        self.index = index
        self.scrollY = scrollY
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.documentHeight = documentHeight
        self.pngPixelWidth = pngPixelWidth
        self.pngPixelHeight = pngPixelHeight
        self.fileName = fileName
    }
}

public struct BrowserCaptureManifest: Codable, Equatable, Sendable {
    public let version: Int
    public let id: String
    public let createdAt: Date
    public let capturedHeight: Double
    public let tiles: [BrowserCaptureTile]

    public init(version: Int = 1, id: UUID, createdAt: Date = .now,
                capturedHeight: Double, tiles: [BrowserCaptureTile]) {
        self.version = version
        self.id = id.uuidString.lowercased()
        self.createdAt = createdAt
        self.capturedHeight = capturedHeight
        self.tiles = tiles
    }
}

public enum BrowserCaptureBridgeError: Error, Equatable {
    case invalidIdentifier
    case expired
    case unsafePath
    case invalidManifest
    case missingTile
    case sizeLimit
    case invalidImage
    case invalidSession
    case invalidTile
    case invalidChunk
    case incompleteTile
    case noTiles
}

public struct BrowserCaptureLimits: Sendable {
    public static let maximumTiles = 2_000
    public static let maximumTilePixels = 32_000_000
    public static let maximumTotalPixels = 250_000_000
    public static let maximumTileEncodedBytes = 128 * 1024 * 1024
    public static let maximumChunkBytes = 512 * 1024
    public static let maximumManifestBytes = 1 * 1024 * 1024
    public static let expiryInterval: TimeInterval = 24 * 60 * 60
}

/// Safe, UUID-scoped access to finalized browser captures and stale partial sessions.
public struct BrowserCaptureInbox: Sendable {
    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PinboardShot/BrowserCaptures", isDirectory: true)
    }

    public let rootURL: URL

    public init(rootURL: URL = BrowserCaptureInbox.defaultRootURL) {
        let requested = rootURL.standardizedFileURL
        let path = requested.path
        let canonicalPath: String
        if path.hasPrefix("/var/") || path == "/var" || path.hasPrefix("/tmp/") || path == "/tmp" {
            canonicalPath = "/private\(path)"
        } else {
            canonicalPath = path
        }
        self.rootURL = URL(fileURLWithPath: canonicalPath, isDirectory: true).standardizedFileURL
    }

    public func readManifest(id: UUID, now: Date = .now) throws -> BrowserCaptureManifest {
        let directory = try checkedCaptureDirectory(id: id)
        let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
        try requireRegularFile(manifestURL)
        let data = try readRegularFile(manifestURL, maximumBytes: BrowserCaptureLimits.maximumManifestBytes)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(BrowserCaptureManifest.self, from: data),
              manifest.version == 1,
              manifest.id.lowercased() == id.uuidString.lowercased(),
              manifest.createdAt <= now,
              now.timeIntervalSince(manifest.createdAt) <= BrowserCaptureLimits.expiryInterval,
              manifest.capturedHeight.isFinite, manifest.capturedHeight > 0,
              !manifest.tiles.isEmpty, manifest.tiles.count <= BrowserCaptureLimits.maximumTiles else {
            throw BrowserCaptureBridgeError.invalidManifest
        }
        var indices = Set<Int>()
        var totalPixels = 0
        for tile in manifest.tiles {
            guard valid(tile: tile), indices.insert(tile.index).inserted else { throw BrowserCaptureBridgeError.invalidManifest }
            let (pixels, overflow) = tile.pngPixelWidth.multipliedReportingOverflow(by: tile.pngPixelHeight)
            let (sum, sumOverflow) = totalPixels.addingReportingOverflow(pixels)
            guard !overflow, !sumOverflow, sum <= BrowserCaptureLimits.maximumTotalPixels else {
                throw BrowserCaptureBridgeError.sizeLimit
            }
            totalPixels = sum
            let tileURL = directory.appendingPathComponent(tile.fileName, isDirectory: false)
            try requireRegularFile(tileURL)
            let dimensions = try pngDimensions(at: tileURL)
            guard dimensions.0 == tile.pngPixelWidth, dimensions.1 == tile.pngPixelHeight else {
                throw BrowserCaptureBridgeError.invalidImage
            }
        }
        return manifest
    }

    public func readTile(id: UUID, index: Int, now: Date = .now) throws -> Data {
        let manifest = try readManifest(id: id, now: now)
        return try readTile(id: id, index: index, validatedBy: manifest)
    }

    /// Reads a tile after the caller has validated its manifest once, avoiding a full manifest/image scan per tile.
    public func readTile(id: UUID, index: Int, validatedBy manifest: BrowserCaptureManifest) throws -> Data {
        guard manifest.version == 1, manifest.id.lowercased() == id.uuidString.lowercased(),
              manifest.createdAt <= .now,
              Date.now.timeIntervalSince(manifest.createdAt) <= BrowserCaptureLimits.expiryInterval else {
            throw BrowserCaptureBridgeError.invalidManifest
        }
        guard let tile = manifest.tiles.first(where: { $0.index == index }) else { throw BrowserCaptureBridgeError.missingTile }
        guard valid(tile: tile) else { throw BrowserCaptureBridgeError.invalidManifest }
        let url = try checkedCaptureDirectory(id: id).appendingPathComponent(tile.fileName, isDirectory: false)
        let data = try readRegularFile(url, maximumBytes: BrowserCaptureLimits.maximumTileEncodedBytes)
        let dimensions = try pngDimensions(data: data)
        guard dimensions.0 == tile.pngPixelWidth, dimensions.1 == tile.pngPixelHeight else {
            throw BrowserCaptureBridgeError.invalidImage
        }
        return data
    }

    public func cleanup(id: UUID) throws {
        let directory = try checkedCaptureDirectory(id: id)
        try removeCaptureDirectory(directory)
    }

    public func cleanupExpired(before cutoff: Date = Date().addingTimeInterval(-BrowserCaptureLimits.expiryInterval)) throws {
        var rootInfo = stat()
        if lstat(rootURL.path, &rootInfo) != 0 && errno == ENOENT { return }
        try ensureSecureRoot(create: false)
        let urls = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
        for url in urls {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            let info = try lstatInfo(url)
            guard info.isDirectory else { throw BrowserCaptureBridgeError.unsafePath }
            let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date ?? .distantFuture
            if modified < cutoff { try cleanup(id: id) }
        }
    }

    func makeWriter(id: UUID) throws -> BrowserCaptureWriter {
        try ensureSecureRoot(create: true)
        let directory = rootURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        guard mkdir(directory.path, mode_t(0o700)) == 0 else { throw BrowserCaptureBridgeError.unsafePath }
        try chmod(directory.path, mode_t(0o700)).checkPOSIX()
        return BrowserCaptureWriter(id: id, directoryURL: directory)
    }

    func checkedCaptureDirectory(id: UUID) throws -> URL {
        try ensureSecureRoot(create: false)
        let directory = rootURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        guard try lstatInfo(directory).isDirectory else { throw BrowserCaptureBridgeError.unsafePath }
        return directory
    }

    func ensureSecureRoot(create: Bool) throws {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in rootURL.pathComponents.dropFirst() {
            current.appendPathComponent(component, isDirectory: true)
            if create {
                if mkdir(current.path, mode_t(0o700)) != 0 && errno != EEXIST {
                    throw BrowserCaptureBridgeError.unsafePath
                }
            }
            let info = try lstatInfo(current)
            guard info.isDirectory else { throw BrowserCaptureBridgeError.unsafePath }
            let isRoot = canonicalSystemPath(current.path) == canonicalSystemPath(rootURL.path)
            if create && (isRoot || current.lastPathComponent == "PinboardShot") {
                try chmod(current.path, mode_t(0o700)).checkPOSIX()
            }
            if !create && isRoot { break }
        }
        guard canonicalSystemPath(current.standardizedFileURL.path) == canonicalSystemPath(rootURL.path) else {
            throw BrowserCaptureBridgeError.unsafePath
        }
    }

    private func valid(tile: BrowserCaptureTile) -> Bool {
        tile.index >= 0 && tile.scrollY.isFinite && tile.scrollY >= 0 &&
        tile.viewportWidth.isFinite && tile.viewportWidth > 0 &&
        tile.viewportHeight.isFinite && tile.viewportHeight > 0 &&
        tile.documentHeight.isFinite && tile.documentHeight > 0 &&
        tile.pngPixelWidth > 0 && tile.pngPixelHeight > 0 &&
        tile.pngPixelWidth <= 32_768 && tile.pngPixelHeight <= 32_768 &&
        tile.pngPixelWidth.multipliedReportingOverflow(by: tile.pngPixelHeight).partialValue <= BrowserCaptureLimits.maximumTilePixels &&
        tile.fileName == String(format: "tile-%06d.png", tile.index)
    }

    private func requireRegularFile(_ url: URL) throws {
        let info = try lstatInfo(url)
        guard info.isRegularFile else { throw BrowserCaptureBridgeError.unsafePath }
    }

    private func pngDimensions(at url: URL) throws -> (Int, Int) {
        let data = try readRegularFile(url, maximumBytes: BrowserCaptureLimits.maximumTileEncodedBytes)
        let dimensions = try pngDimensions(data: data)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) == "public.png" as CFString,
              let image = CGImageSourceCreateImageAtIndex(source, 0, sourceOptions),
              image.width == dimensions.0, image.height == dimensions.1 else { throw BrowserCaptureBridgeError.invalidImage }
        return dimensions
    }

    private func pngDimensions(data: Data) throws -> (Int, Int) {
        guard data.count >= 24 else { throw BrowserCaptureBridgeError.invalidImage }
        let header = Array(data.prefix(24))
        guard Array(header[0..<8]) == [137, 80, 78, 71, 13, 10, 26, 10],
              Array(header[12..<16]) == Array("IHDR".utf8) else { throw BrowserCaptureBridgeError.invalidImage }
        let width = Int(header[16]) << 24 | Int(header[17]) << 16 | Int(header[18]) << 8 | Int(header[19])
        let height = Int(header[20]) << 24 | Int(header[21]) << 16 | Int(header[22]) << 8 | Int(header[23])
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, width > 0, height > 0, width <= 32_768, height <= 32_768,
              pixels <= BrowserCaptureLimits.maximumTilePixels else { throw BrowserCaptureBridgeError.sizeLimit }
        return (width, height)
    }

    private func readRegularFile(_ url: URL, maximumBytes: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw BrowserCaptureBridgeError.unsafePath }
        defer { _ = close(fd) }
        var value = stat()
        guard fstat(fd, &value) == 0, (value.st_mode & S_IFMT) == S_IFREG,
              value.st_size >= 0, value.st_size <= maximumBytes else { throw BrowserCaptureBridgeError.sizeLimit }
        var data = Data()
        data.reserveCapacity(Int(value.st_size))
        var buffer = [UInt8](repeating: 0, count: 128 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count >= 0 else { throw BrowserCaptureBridgeError.unsafePath }
            if count == 0 { break }
            guard data.count <= maximumBytes - count else { throw BrowserCaptureBridgeError.sizeLimit }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private func removeCaptureDirectory(_ directory: URL) throws {
        let allowed = Set(["manifest.json", ".manifest.tmp", "tile-*.png", "control-request.json", "control-status.json", "control.lock"])
        let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
        for child in children {
            let name = child.lastPathComponent
            guard allowed.contains(name) || name.hasPrefix("tile-") && (name.hasSuffix(".part") || name.hasSuffix(".png")) else {
                throw BrowserCaptureBridgeError.unsafePath
            }
            let info = try lstatInfo(child)
            guard info.isRegularFile else { throw BrowserCaptureBridgeError.unsafePath }
            try FileManager.default.removeItem(at: child)
        }
        try FileManager.default.removeItem(at: directory)
    }
}

/// Incrementally decodes Base64 chunks to one private temporary PNG without retaining the image in RAM.
public final class BrowserCaptureWriter {
    public let id: UUID
    private let directoryURL: URL
    private var tiles: [BrowserCaptureTile] = []
    private var openTile: OpenTile?
    private var finished = false

    init(id: UUID, directoryURL: URL) { self.id = id; self.directoryURL = directoryURL }

    public func beginTile(index: Int, scrollY: Double, viewportWidth: Double, viewportHeight: Double,
                          documentHeight: Double, base64Length: Int) throws {
        guard !finished, openTile == nil, index >= 0, index < BrowserCaptureLimits.maximumTiles,
              !tiles.contains(where: { $0.index == index }), base64Length > 0,
              base64Length <= BrowserCaptureLimits.maximumTileEncodedBytes * 4 / 3 + 8,
              scrollY.isFinite, scrollY >= 0, viewportWidth.isFinite, viewportWidth > 0,
              viewportHeight.isFinite, viewportHeight > 0, documentHeight.isFinite, documentHeight > 0 else {
            throw BrowserCaptureBridgeError.invalidTile
        }
        let temporary = directoryURL.appendingPathComponent(String(format: "tile-%06d.part", index), isDirectory: false)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw BrowserCaptureBridgeError.unsafePath }
        openTile = OpenTile(index: index, scrollY: scrollY, viewportWidth: viewportWidth,
                            viewportHeight: viewportHeight, documentHeight: documentHeight,
                            expectedBase64Length: base64Length, fileDescriptor: fd)
    }

    public func appendChunk(index: Int, sequence: Int, base64: String) throws {
        guard var tile = openTile, tile.index == index, sequence == tile.nextSequence,
              !base64.isEmpty, base64.utf8.count <= BrowserCaptureLimits.maximumChunkBytes,
              tile.receivedBase64 <= tile.expectedBase64Length - base64.utf8.count else {
            throw BrowserCaptureBridgeError.invalidChunk
        }
        let input = Data(base64.utf8)
        guard input.allSatisfy({ Self.isBase64Byte($0) }) else { throw BrowserCaptureBridgeError.invalidChunk }
        tile.pendingBase64.append(input)
        let completeLength = (tile.pendingBase64.count / 4) * 4
        if completeLength > 0 {
            let group = Data(tile.pendingBase64.prefix(completeLength))
            guard let decoded = Data(base64Encoded: group), decoded.count <= BrowserCaptureLimits.maximumTileEncodedBytes else {
                throw BrowserCaptureBridgeError.invalidChunk
            }
            try writeAll(fd: tile.fileDescriptor, data: decoded)
            tile.pendingBase64.removeFirst(completeLength)
            tile.decodedBytes += decoded.count
        }
        tile.receivedBase64 += input.count
        tile.nextSequence += 1
        openTile = tile
    }

    public func endTile(index: Int) throws -> BrowserCaptureTile {
        guard let open = openTile, open.index == index,
              open.receivedBase64 == open.expectedBase64Length,
              open.pendingBase64.isEmpty, open.decodedBytes > 0 else { throw BrowserCaptureBridgeError.incompleteTile }
        openTile = nil
        _ = close(open.fileDescriptor)
        let temporary = directoryURL.appendingPathComponent(String(format: "tile-%06d.part", index), isDirectory: false)
        let final = directoryURL.appendingPathComponent(String(format: "tile-%06d.png", index), isDirectory: false)
        let inbox = BrowserCaptureInbox(rootURL: directoryURL.deletingLastPathComponent())
        let dimensions = try inbox.pngDimensionsForWriter(at: temporary)
        let width = dimensions.0
        let height = dimensions.1
        guard rename(temporary.path, final.path) == 0 else { throw BrowserCaptureBridgeError.unsafePath }
        let tile = BrowserCaptureTile(index: index, scrollY: open.scrollY, viewportWidth: open.viewportWidth,
                                      viewportHeight: open.viewportHeight, documentHeight: open.documentHeight,
                                      pngPixelWidth: width, pngPixelHeight: height,
                                      fileName: String(format: "tile-%06d.png", index))
        tiles.append(tile)
        return tile
    }

    public func finish(capturedHeight: Double, createdAt: Date = .now) throws -> BrowserCaptureManifest {
        guard !finished, openTile == nil, !tiles.isEmpty, tiles.count <= BrowserCaptureLimits.maximumTiles,
              capturedHeight.isFinite, capturedHeight > 0 else { throw BrowserCaptureBridgeError.noTiles }
        var totalPixels = 0
        for tile in tiles {
            let pixels = tile.pngPixelWidth * tile.pngPixelHeight
            let (sum, overflow) = totalPixels.addingReportingOverflow(pixels)
            guard !overflow, sum <= BrowserCaptureLimits.maximumTotalPixels else { throw BrowserCaptureBridgeError.sizeLimit }
            totalPixels = sum
        }
        let manifest = BrowserCaptureManifest(id: id, createdAt: createdAt, capturedHeight: capturedHeight,
                                              tiles: tiles.sorted { $0.index < $1.index })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        guard data.count <= BrowserCaptureLimits.maximumManifestBytes else { throw BrowserCaptureBridgeError.sizeLimit }
        let temporary = directoryURL.appendingPathComponent(".manifest.tmp", isDirectory: false)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw BrowserCaptureBridgeError.unsafePath }
        do {
            try writeAll(fd: fd, data: data)
            guard fsync(fd) == 0 else { throw BrowserCaptureBridgeError.unsafePath }
            _ = close(fd)
            let destination = directoryURL.appendingPathComponent("manifest.json", isDirectory: false)
            guard rename(temporary.path, destination.path) == 0 else { throw BrowserCaptureBridgeError.unsafePath }
        } catch {
            _ = close(fd)
            throw error
        }
        finished = true
        return manifest
    }

    public func cancel() throws {
        if let tile = openTile { _ = close(tile.fileDescriptor); openTile = nil }
        let inbox = BrowserCaptureInbox(rootURL: directoryURL.deletingLastPathComponent())
        try inbox.removeWriterDirectory(directoryURL)
        finished = true
    }

    private static func isBase64Byte(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ||
        (byte >= 48 && byte <= 57) || byte == 43 || byte == 47 || byte == 61
    }
}

private struct OpenTile {
    let index: Int
    let scrollY: Double
    let viewportWidth: Double
    let viewportHeight: Double
    let documentHeight: Double
    let expectedBase64Length: Int
    let fileDescriptor: Int32
    var receivedBase64 = 0
    var decodedBytes = 0
    var nextSequence = 0
    var pendingBase64 = Data()
}

private struct LStatInfo {
    let isDirectory: Bool
    let isRegularFile: Bool
}

private func lstatInfo(_ url: URL) throws -> LStatInfo {
    var value = stat()
    guard lstat(url.path, &value) == 0 else { throw BrowserCaptureBridgeError.unsafePath }
    if (value.st_mode & S_IFMT) == S_IFLNK {
        // macOS exposes root-owned /var and /tmp aliases; reject any redirected target.
        guard url.path == "/var" || url.path == "/tmp" else { throw BrowserCaptureBridgeError.unsafePath }
        let expectedLink = url.path == "/var" ? "private/var" : "private/tmp"
        var linkBytes = [CChar](repeating: 0, count: 64)
        let linkLength = url.path.withCString { readlink($0, &linkBytes, linkBytes.count) }
        guard value.st_uid == 0, linkLength > 0,
              String(decoding: linkBytes.prefix(linkLength).map { UInt8(bitPattern: $0) }, as: UTF8.self) == expectedLink else {
            throw BrowserCaptureBridgeError.unsafePath
        }
        var target = stat()
        let canonicalTarget = url.path == "/var" ? "/private/var" : "/private/tmp"
        guard stat(canonicalTarget, &target) == 0, target.st_uid == 0,
              (target.st_mode & S_IFMT) == S_IFDIR else {
            throw BrowserCaptureBridgeError.unsafePath
        }
        value = target
    }
    guard (value.st_mode & S_IFMT) != S_IFLNK else {
        throw BrowserCaptureBridgeError.unsafePath
    }
    return LStatInfo(isDirectory: (value.st_mode & S_IFMT) == S_IFDIR,
                     isRegularFile: (value.st_mode & S_IFMT) == S_IFREG)
}

private func canonicalSystemPath(_ path: String) -> String {
    if path == "/var" || path.hasPrefix("/var/") { return "/private\(path)" }
    if path == "/tmp" || path.hasPrefix("/tmp/") { return "/private\(path)" }
    return path
}

private func writeAll(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let written = write(fd, base.advanced(by: offset), bytes.count - offset)
            guard written > 0 else { throw BrowserCaptureBridgeError.unsafePath }
            offset += written
        }
    }
}

private extension Int32 {
    func checkPOSIX() throws {
        guard self == 0 else { throw BrowserCaptureBridgeError.unsafePath }
    }
}

private extension BrowserCaptureInbox {
    func pngDimensionsForWriter(at url: URL) throws -> (Int, Int) { try pngDimensions(at: url) }
    func removeWriterDirectory(_ url: URL) throws { try removeCaptureDirectory(url) }
}
