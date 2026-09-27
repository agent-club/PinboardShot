import AppKit
@preconcurrency import ApplicationServices

enum BrowserCaptureLaunchError: LocalizedError {
    case chromeUnavailable, accessibilityRequired, activationFailed

    var errorDescription: String? {
        switch self {
        case .chromeUnavailable: L10n.text("browserExtension.chromeUnavailable")
        case .accessibilityRequired: L10n.text("browserExtension.accessibilityRequired")
        case .activationFailed: L10n.text("browserExtension.activationFailed")
        }
    }
}

enum BrowserCaptureRouting {
    static func usesChromeExtension(sourceApplicationBundleIdentifier: String?) -> Bool {
        sourceApplicationBundleIdentifier == "com.google.Chrome"
    }

    static func matches(windowFrame: CGRect, targetFrame: CGRect) -> Bool {
        abs(windowFrame.minX - targetFrame.minX) <= 2 && abs(windowFrame.minY - targetFrame.minY) <= 2 &&
        abs(windowFrame.width - targetFrame.width) <= 2 && abs(windowFrame.height - targetFrame.height) <= 2
    }
}

@MainActor
enum BrowserCaptureLauncher {
    static func start(windowFrame: CGRect? = nil) async throws {
        guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
            .first(where: { !$0.isTerminated }) else {
            throw BrowserCaptureLaunchError.chromeUnavailable
        }
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
            throw BrowserCaptureLaunchError.accessibilityRequired
        }
        guard chrome.activate(options: [.activateAllWindows]) else {
            throw BrowserCaptureLaunchError.activationFailed
        }
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier {
                if let windowFrame {
                    try raiseWindow(in: chrome, matching: windowFrame)
                    try await Task.sleep(for: .milliseconds(150))
                }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier else {
                    throw BrowserCaptureLaunchError.activationFailed
                }
                // Chrome grants activeTab on its extension command. Native Messaging
                // alone cannot grant page access, so invoke only this installed command.
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 16, keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: 16, keyDown: false) else {
                    throw BrowserCaptureLaunchError.activationFailed
                }
                down.flags = [.maskCommand, .maskShift]
                up.flags = [.maskCommand, .maskShift]
                // Deliver to the verified Chrome process, never whichever app gains focus next.
                down.postToPid(chrome.processIdentifier)
                up.postToPid(chrome.processIdentifier)
                return
            }
        }
        throw BrowserCaptureLaunchError.activationFailed
    }

    private static func raiseWindow(in chrome: NSRunningApplication, matching targetFrame: CGRect) throws {
        let application = AXUIElementCreateApplication(chrome.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { throw BrowserCaptureLaunchError.activationFailed }
        let matching = windows.filter { window in
            guard let frame = frame(of: window) else { return false }
            return BrowserCaptureRouting.matches(windowFrame: frame, targetFrame: targetFrame)
        }
        // A selection in another Chrome window must never silently capture the last active window.
        guard matching.count == 1,
              AXUIElementPerformAction(matching[0], kAXRaiseAction as CFString) == .success else {
            throw BrowserCaptureLaunchError.activationFailed
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
