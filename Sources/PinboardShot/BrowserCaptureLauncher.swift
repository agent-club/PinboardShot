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

@MainActor
enum BrowserCaptureLauncher {
    static func start() async throws {
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
}
