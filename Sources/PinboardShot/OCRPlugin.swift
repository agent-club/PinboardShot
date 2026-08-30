import Foundation
import Security

enum OCRPluginConstants {
    static let localProviderID = "local"
    static let schemaVersion = 1
    static let maximumManifestBytes = 1_048_576
    static let maximumImageBytes = 20 * 1_024 * 1_024
    static let maximumResponseBytes = 5 * 1_024 * 1_024
}

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    func replacing(placeholders: [String: String]) -> JSONValue {
        switch self {
        case .object(let object):
            return .object(object.mapValues { $0.replacing(placeholders: placeholders) })
        case .array(let array):
            return .array(array.map { $0.replacing(placeholders: placeholders) })
        case .string(let string):
            return .string(placeholders.reduce(string) { value, replacement in
                value.replacingOccurrences(of: "{{\(replacement.key)}}", with: replacement.value)
            })
        case .number, .bool, .null:
            return self
        }
    }

    var foundationObject: Any {
        switch self {
        case .object(let object): return object.mapValues(\.foundationObject)
        case .array(let array): return array.map(\.foundationObject)
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        case .null: return NSNull()
        }
    }

    func string(at path: [String]) -> String? {
        guard let component = path.first else {
            if case .string(let value) = self { return value }
            return nil
        }
        let remainder = Array(path.dropFirst())
        switch self {
        case .object(let object):
            return object[component]?.string(at: remainder)
        case .array(let array):
            guard let index = Int(component), array.indices.contains(index) else { return nil }
            return array[index].string(at: remainder)
        case .string, .number, .bool, .null:
            return nil
        }
    }

    func containsPlaceholder(_ name: String) -> Bool {
        switch self {
        case .object(let object): return object.values.contains { $0.containsPlaceholder(name) }
        case .array(let array): return array.contains { $0.containsPlaceholder(name) }
        case .string(let string): return string.contains("{{\(name)}}")
        case .number, .bool, .null: return false
        }
    }

    var allPlaceholderNames: Set<String> {
        switch self {
        case .object(let object):
            return object.values.reduce(into: []) { $0.formUnion($1.allPlaceholderNames) }
        case .array(let array):
            return array.reduce(into: []) { $0.formUnion($1.allPlaceholderNames) }
        case .string(let string):
            let pattern = #"\{\{([A-Za-z][A-Za-z0-9]*)\}\}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(string.startIndex..<string.endIndex, in: string)
            return Set(regex.matches(in: string, range: range).compactMap { match in
                guard let nameRange = Range(match.range(at: 1), in: string) else { return nil }
                return String(string[nameRange])
            })
        case .number, .bool, .null:
            return []
        }
    }
}

struct OCRPluginAuthentication: Codable, Equatable, Sendable {
    let header: String
    let prefix: String
}

struct OCRPluginManifest: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: String
    let name: String
    let endpoint: String
    let authentication: OCRPluginAuthentication?
    let headers: [String: String]?
    let request: JSONValue
    let responseTextPath: String
    let defaultBaseURL: String?
    let defaultModel: String?

    static let openAICompatible = OCRPluginManifest(
        schemaVersion: OCRPluginConstants.schemaVersion,
        id: "builtin.openai-compatible",
        name: "OpenAI-compatible OCR",
        endpoint: "/chat/completions",
        authentication: OCRPluginAuthentication(header: "Authorization", prefix: "Bearer "),
        headers: nil,
        request: .object([
            "model": .string("{{model}}"),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string("Perform OCR on this image. Return only the recognized text, preserving reading order and line breaks.")
                        ]),
                        .object([
                            "type": .string("image_url"),
                            "image_url": .object(["url": .string("{{imageDataURL}}")])
                        ])
                    ])
                ])
            ])
        ]),
        responseTextPath: "choices.0.message.content",
        defaultBaseURL: "",
        defaultModel: ""
    )

    func validate() throws {
        guard schemaVersion == OCRPluginConstants.schemaVersion else {
            throw OCRPluginError.invalidManifest("unsupported schemaVersion \(schemaVersion)")
        }
        guard id.range(of: #"^[a-z0-9][a-z0-9.-]{2,79}$"#, options: .regularExpression) != nil,
              id != OCRPluginConstants.localProviderID else {
            throw OCRPluginError.invalidManifest("invalid plugin id")
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else {
            throw OCRPluginError.invalidManifest("invalid plugin name")
        }
        guard endpoint.hasPrefix("/"), !endpoint.hasPrefix("//"),
              let endpointComponents = URLComponents(string: endpoint),
              endpointComponents.scheme == nil, endpointComponents.host == nil,
              endpointComponents.fragment == nil,
              !endpointComponents.path.split(separator: "/").contains("..") else {
            throw OCRPluginError.invalidManifest("endpoint must be a relative absolute path")
        }
        let path = responseTextPath.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !path.isEmpty, !path.contains(where: \.isEmpty) else {
            throw OCRPluginError.invalidManifest("responseTextPath is required")
        }
        guard request.containsPlaceholder("imageDataURL") else {
            throw OCRPluginError.invalidManifest("request must contain {{imageDataURL}}")
        }
        let supportedPlaceholders: Set<String> = ["imageDataURL", "model"]
        let unsupported = request.allPlaceholderNames.subtracting(supportedPlaceholders)
        guard unsupported.isEmpty else {
            throw OCRPluginError.invalidManifest("unsupported placeholder: \(unsupported.sorted().joined(separator: ", "))")
        }
        if let authentication {
            try Self.validateHeaderName(authentication.header)
            guard !authentication.prefix.contains("\r"), !authentication.prefix.contains("\n") else {
                throw OCRPluginError.invalidManifest("invalid authentication prefix")
            }
            if headers?.keys.contains(where: { $0.caseInsensitiveCompare(authentication.header) == .orderedSame }) == true {
                throw OCRPluginError.invalidManifest("authentication header is duplicated")
            }
        }
        for (header, value) in headers ?? [:] {
            try Self.validateHeaderName(header)
            let lowered = header.lowercased()
            let forbiddenStaticHeaders = [
                "authorization", "cookie", "proxy-authorization", "host", "content-length",
                "connection", "transfer-encoding"
            ]
            guard !forbiddenStaticHeaders.contains(lowered) else {
                throw OCRPluginError.invalidManifest("sensitive static header is not allowed")
            }
            guard !value.contains("\r"), !value.contains("\n") else {
                throw OCRPluginError.invalidManifest("invalid HTTP header value")
            }
        }
    }

    private static func validateHeaderName(_ name: String) throws {
        guard name.range(of: #"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$"#, options: .regularExpression) != nil else {
            throw OCRPluginError.invalidManifest("invalid HTTP header name")
        }
    }
}

struct OCRPluginCatalogResult: Sendable {
    let plugins: [OCRPluginManifest]
    let errors: [String]
}

enum OCRPluginCatalog {
    static func pluginsDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw OCRPluginError.pluginsDirectoryUnavailable
        }
        return applicationSupport
            .appendingPathComponent("PinboardShot", isDirectory: true)
            .appendingPathComponent("OCRPlugins", isDirectory: true)
    }

    static func createPluginsDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try pluginsDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func load(fileManager: FileManager = .default) -> OCRPluginCatalogResult {
        var plugins = [OCRPluginManifest.openAICompatible]
        var errors: [String] = []
        guard let directory = try? pluginsDirectory(fileManager: fileManager),
              let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return OCRPluginCatalogResult(plugins: plugins, errors: errors)
        }

        let decoder = JSONDecoder()
        var identifiers = Set(plugins.map(\.id))
        for file in files.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, (values.fileSize ?? 0) <= OCRPluginConstants.maximumManifestBytes else {
                    throw OCRPluginError.invalidManifest("manifest is not a regular file or exceeds 1 MB")
                }
                let manifest = try decoder.decode(OCRPluginManifest.self, from: Data(contentsOf: file))
                try manifest.validate()
                guard identifiers.insert(manifest.id).inserted else {
                    throw OCRPluginError.invalidManifest("duplicate plugin id \(manifest.id)")
                }
                plugins.append(manifest)
            } catch {
                errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return OCRPluginCatalogResult(plugins: plugins, errors: errors)
    }
}

struct OCRPluginConfiguration: Equatable, Sendable {
    let baseURL: String
    let model: String
}

enum OCRPluginSettings {
    static let selectedProviderDefaultsKey = "ocr.selectedProvider"

    static func selectedProviderID(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: selectedProviderDefaultsKey) ?? OCRPluginConstants.localProviderID
    }

    static func configuration(for plugin: OCRPluginManifest, defaults: UserDefaults = .standard) -> OCRPluginConfiguration {
        OCRPluginConfiguration(
            baseURL: defaults.string(forKey: baseURLDefaultsKey(pluginID: plugin.id)) ?? plugin.defaultBaseURL ?? "",
            model: defaults.string(forKey: modelDefaultsKey(pluginID: plugin.id)) ?? plugin.defaultModel ?? ""
        )
    }

    static func save(
        providerID: String,
        configuration: OCRPluginConfiguration?,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(providerID, forKey: selectedProviderDefaultsKey)
        guard providerID != OCRPluginConstants.localProviderID, let configuration else { return }
        defaults.set(configuration.baseURL, forKey: baseURLDefaultsKey(pluginID: providerID))
        defaults.set(configuration.model, forKey: modelDefaultsKey(pluginID: providerID))
    }

    private static func baseURLDefaultsKey(pluginID: String) -> String { "ocr.plugin.\(pluginID).baseURL" }
    private static func modelDefaultsKey(pluginID: String) -> String { "ocr.plugin.\(pluginID).model" }
}

enum OCRPluginCredentialStore {
    private static let service = "com.ryanwang.PinboardShot.ocr-plugin"

    static func hasAPIKey(pluginID: String) throws -> Bool {
        try loadAPIKey(pluginID: pluginID) != nil
    }

    static func loadAPIKey(pluginID: String) throws -> String? {
        var query = baseQuery(pluginID: pluginID)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw OCRPluginError.keychain(status)
        }
        return value
    }

    static func saveAPIKey(_ apiKey: String, pluginID: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OCRPluginError.apiKeyRequired }
        guard !trimmed.contains("\r"), !trimmed.contains("\n") else {
            throw OCRPluginError.invalidAPIKey
        }
        let valueData = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(pluginID: pluginID) as CFDictionary,
            [kSecValueData: valueData] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw OCRPluginError.keychain(updateStatus) }

        var attributes = baseQuery(pluginID: pluginID)
        attributes[kSecValueData] = valueData
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw OCRPluginError.keychain(status) }
    }

    static func deleteAPIKey(pluginID: String) throws {
        let status = SecItemDelete(baseQuery(pluginID: pluginID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OCRPluginError.keychain(status)
        }
    }

    private static func baseQuery(pluginID: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: pluginID
        ]
    }
}

enum OCRPluginError: LocalizedError, Equatable {
    case invalidManifest(String)
    case pluginsDirectoryUnavailable
    case pluginNotFound
    case invalidBaseURL
    case insecureBaseURL
    case modelRequired
    case apiKeyRequired
    case invalidAPIKey
    case imageTooLarge
    case invalidResponse
    case responseTooLarge
    case httpStatus(Int)
    case crossOriginRedirect
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidManifest(let reason): L10n.text("ocr.error.invalidManifest", reason)
        case .pluginsDirectoryUnavailable: L10n.text("ocr.error.pluginsDirectoryUnavailable")
        case .pluginNotFound: L10n.text("ocr.error.pluginNotFound")
        case .invalidBaseURL: L10n.text("ocr.error.invalidBaseURL")
        case .insecureBaseURL: L10n.text("ocr.error.insecureBaseURL")
        case .modelRequired: L10n.text("ocr.error.modelRequired")
        case .apiKeyRequired: L10n.text("ocr.error.apiKeyRequired")
        case .invalidAPIKey: L10n.text("ocr.error.invalidAPIKey")
        case .imageTooLarge: L10n.text("ocr.error.imageTooLarge")
        case .invalidResponse: L10n.text("ocr.error.invalidResponse")
        case .responseTooLarge: L10n.text("ocr.error.responseTooLarge")
        case .httpStatus(let status): L10n.text("ocr.error.httpStatus", status)
        case .crossOriginRedirect: L10n.text("ocr.error.crossOriginRedirect")
        case .keychain(let status): L10n.text("ocr.error.keychain", status)
        }
    }
}
