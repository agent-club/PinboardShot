import AppKit
import Foundation

enum OCRPluginRequestBuilder {
    static func endpointURL(baseURL: String, endpoint: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var base = URLComponents(string: trimmed),
              let scheme = base.scheme?.lowercased(),
              let host = base.host?.lowercased(),
              !host.isEmpty,
              base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil,
              let endpointComponents = URLComponents(string: endpoint),
              endpointComponents.scheme == nil, endpointComponents.host == nil,
              endpointComponents.path.hasPrefix("/") else {
            throw OCRPluginError.invalidBaseURL
        }
        let localHosts = ["localhost", "127.0.0.1", "::1"]
        guard scheme == "https" || (scheme == "http" && localHosts.contains(host)) else {
            throw OCRPluginError.insecureBaseURL
        }

        let basePath = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = endpointComponents.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        base.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        base.queryItems = endpointComponents.queryItems
        guard let url = base.url else { throw OCRPluginError.invalidBaseURL }
        return url
    }

    static func validate(
        manifest: OCRPluginManifest,
        configuration: OCRPluginConfiguration,
        hasAPIKey: Bool
    ) throws {
        try manifest.validate()
        _ = try endpointURL(baseURL: configuration.baseURL, endpoint: manifest.endpoint)
        if manifest.request.containsPlaceholder("model"),
           configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OCRPluginError.modelRequired
        }
        if manifest.authentication != nil, !hasAPIKey {
            throw OCRPluginError.apiKeyRequired
        }
    }

    static func request(
        manifest: OCRPluginManifest,
        configuration: OCRPluginConfiguration,
        apiKey: String?,
        imageData: Data
    ) throws -> URLRequest {
        try validate(
            manifest: manifest,
            configuration: configuration,
            hasAPIKey: apiKey?.isEmpty == false
        )
        guard imageData.count <= OCRPluginConstants.maximumImageBytes else {
            throw OCRPluginError.imageTooLarge
        }

        let url = try endpointURL(baseURL: configuration.baseURL, endpoint: manifest.endpoint)
        let imageDataURL = "data:image/png;base64,\(imageData.base64EncodedString())"
        let body = manifest.request.replacing(placeholders: [
            "imageDataURL": imageDataURL,
            "model": configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        let bodyData = try JSONSerialization.data(withJSONObject: body.foundationObject)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (header, value) in manifest.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: header)
        }
        if let authentication = manifest.authentication, let apiKey {
            guard !apiKey.contains("\r"), !apiKey.contains("\n") else {
                throw OCRPluginError.invalidAPIKey
            }
            request.setValue(authentication.prefix + apiKey, forHTTPHeaderField: authentication.header)
        }
        return request
    }

    static func parseResponse(_ data: Data, manifest: OCRPluginManifest) throws -> String {
        guard data.count <= OCRPluginConstants.maximumResponseBytes else {
            throw OCRPluginError.responseTooLarge
        }
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw OCRPluginError.invalidResponse
        }
        let path = manifest.responseTextPath.split(separator: ".").map(String.init)
        guard let text = root.string(at: path) else { throw OCRPluginError.invalidResponse }
        return text
    }
}

private struct OCRRequestOrigin: Equatable, Sendable {
    let scheme: String
    let host: String
    let port: Int?

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        self.scheme = scheme
        self.host = host
        port = url.port
    }
}

private final class OCRRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: OCRRequestOrigin
    private let lock = NSLock()
    private var rejectedCrossOriginRedirect = false

    init(origin: OCRRequestOrigin) {
        self.origin = origin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
              OCRRequestOrigin(url: redirectedURL) == origin else {
            lock.withLock { rejectedCrossOriginRedirect = true }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    var didRejectCrossOriginRedirect: Bool {
        lock.withLock { rejectedCrossOriginRedirect }
    }
}

enum RemoteOCRPluginClient {
    static func recognize(
        image: CGImage,
        manifest: OCRPluginManifest,
        configuration: OCRPluginConfiguration,
        apiKey: String?
    ) async throws -> String {
        guard let imageData = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw PinboardShotError.imageEncodingFailed
        }
        let request = try OCRPluginRequestBuilder.request(
            manifest: manifest,
            configuration: configuration,
            apiKey: apiKey,
            imageData: imageData
        )
        guard let url = request.url, let origin = OCRRequestOrigin(url: url) else {
            throw OCRPluginError.invalidBaseURL
        }

        let redirectDelegate = OCRRedirectDelegate(origin: origin)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        if redirectDelegate.didRejectCrossOriginRedirect {
            throw OCRPluginError.crossOriginRedirect
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OCRPluginError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw OCRPluginError.httpStatus(httpResponse.statusCode)
        }
        return try OCRPluginRequestBuilder.parseResponse(data, manifest: manifest)
    }
}

enum InteractiveOCRService {
    static func recognizeText(in image: CGImage, defaults: UserDefaults = .standard) async throws -> String {
        let providerID = OCRPluginSettings.selectedProviderID(defaults: defaults)
        guard providerID != OCRPluginConstants.localProviderID else {
            return try TextRecognitionService.recognizeText(in: image)
        }
        let catalog = OCRPluginCatalog.load()
        guard let plugin = catalog.plugins.first(where: { $0.id == providerID }) else {
            throw OCRPluginError.pluginNotFound
        }
        let configuration = OCRPluginSettings.configuration(for: plugin, defaults: defaults)
        let apiKey = try OCRPluginCredentialStore.loadAPIKey(pluginID: plugin.id)
        return try await RemoteOCRPluginClient.recognize(
            image: image,
            manifest: plugin,
            configuration: configuration,
            apiKey: apiKey
        )
    }
}
