import Foundation
import BrowserCaptureBridge
import CryptoKit

enum BrowserExtensionSetup {
    struct HostRegistration: Encodable {
        let name: String
        let description: String
        let path: String
        let type = "stdio"
        let allowed_origins: [String]
    }

    static func prepare(bundle: Bundle = .main, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let applicationURL = URL(fileURLWithPath: "/Applications/PinboardShot.app", isDirectory: true)
        guard bundle.bundleURL.standardizedFileURL == applicationURL,
              let resources = bundle.resourceURL else { throw BrowserCaptureImportError.invalidImage }
        let extensionURL = resources.appendingPathComponent("ChromeExtension", isDirectory: true)
        let hostURL = applicationURL.appendingPathComponent("Contents/MacOS/PinboardShotBrowserHost")
        let manager = FileManager.default
        guard manager.isExecutableFile(atPath: hostURL.path),
              manager.fileExists(atPath: extensionURL.appendingPathComponent("manifest.json").path) else {
            throw BrowserCaptureImportError.invalidImage
        }
        let directory = home.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true)
        // Do not follow an externally substituted registration folder or manifest.
        var ancestor = directory
        while ancestor != home {
            if manager.fileExists(atPath: ancestor.path),
               try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw BrowserCaptureImportError.invalidGeometry
            }
            ancestor.deleteLastPathComponent()
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(BrowserCaptureConfiguration.hostName + ".json")
        if manager.fileExists(atPath: target.path),
           try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw BrowserCaptureImportError.invalidGeometry
        }
        let registration = HostRegistration(name: BrowserCaptureConfiguration.hostName,
            description: "PinboardShot local browser capture bridge", path: hostURL.path,
            allowed_origins: [BrowserCaptureConfiguration.allowedOrigin])
        try JSONEncoder().encode(registration).write(to: target, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return try exportExtension(from: extensionURL, downloads: home.appendingPathComponent("Downloads", isDirectory: true))
    }

    static func exportExtension(from source: URL, downloads: URL) throws -> URL {
        let files = ["manifest.json", "background.js", "capture.js", "popup.html", "popup.js", "popup.css",
                     "lib/planner.mjs", "lib/native-protocol.mjs", "lib/native-client.mjs",
                     "icons/icon16.png", "icons/icon32.png", "icons/icon48.png", "icons/icon128.png"]
        let manager = FileManager.default
        for directory in [source, source.appendingPathComponent("lib"), source.appendingPathComponent("icons")] {
            let info = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else { throw BrowserCaptureImportError.invalidGeometry }
        }
        guard try downloads.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              try downloads.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw BrowserCaptureImportError.invalidGeometry
        }
        var digest = SHA256()
        let contents = try files.map { name -> (String, Data) in
            let file = source.appendingPathComponent(name)
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else {
                throw BrowserCaptureImportError.invalidImage
            }
            let data = try Data(contentsOf: file)
            digest.update(data: Data(name.utf8))
            digest.update(data: data)
            return (name, data)
        }
        let suffix = digest.finalize().prefix(4).map { String(format: "%02x", $0) }.joined()
        let destination = downloads.appendingPathComponent("PinboardShot-Chrome-\(suffix)", isDirectory: true)
        // Keep an existing export intact: it may already be loaded by Chrome or edited by the user.
        if manager.fileExists(atPath: destination.path) {
            guard try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw BrowserCaptureImportError.invalidGeometry
            }
            for name in ["lib", "icons"] {
                let info = try destination.appendingPathComponent(name).resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isDirectory == true, info.isSymbolicLink != true else { throw BrowserCaptureImportError.invalidGeometry }
            }
            for (name, data) in contents {
                let file = destination.appendingPathComponent(name)
                let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true,
                      try Data(contentsOf: file) == data else { throw BrowserCaptureImportError.invalidImage }
            }
            return destination
        }
        try manager.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            try manager.createDirectory(at: destination.appendingPathComponent("lib"), withIntermediateDirectories: false)
            try manager.createDirectory(at: destination.appendingPathComponent("icons"), withIntermediateDirectories: false)
            for (name, data) in contents { try data.write(to: destination.appendingPathComponent(name), options: .withoutOverwriting) }
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
        return destination
    }
}
