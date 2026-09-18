import Foundation

/// Parse the external URL contract before dispatch, keeping output options attached to a capture request.
enum AutomationCommand: Equatable {
    case capture(CaptureAction, pinResult: Bool)
    case pinClipboard
    case togglePins
    case pinFile(URL)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "pinboardshot",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { query[item.name] = value }
        }
        let pinResult = query["after"]?.lowercased() == "pin"
        switch (url.host?.lowercased(), query["mode"]?.lowercased()) {
        case ("capture", "region"): self = .capture(.region, pinResult: pinResult)
        case ("capture", "delayed"): self = .capture(.delayedRegion, pinResult: pinResult)
        case ("capture", "repeat"): self = .capture(.repeatRegion, pinResult: pinResult)
        case ("capture", "scroll"): self = .capture(.scrollingRegion, pinResult: pinResult)
        case ("capture", "display"): self = .capture(.display, pinResult: pinResult)
        case ("capture", "window"): self = .capture(.window, pinResult: pinResult)
        case ("pin", "clipboard"), ("pin-clipboard", _): self = .pinClipboard
        case ("toggle-pins", _): self = .togglePins
        case ("pin-file", _):
            guard let path = query["path"], !path.isEmpty else { return nil }
            self = .pinFile(URL(fileURLWithPath: path))
        default: return nil
        }
    }
}
