import CoreGraphics
import Testing
@testable import PinboardShot

@Suite("Browser capture routing")
struct BrowserCaptureRoutingTests {
    @Test("Only a selected Chrome window uses the installed Chrome extension")
    func routesSelectedApplication() {
        #expect(BrowserCaptureRouting.usesChromeExtension(sourceApplicationBundleIdentifier: "com.google.Chrome"))
        for other in [nil, "com.ryanwang.PinboardShot", "com.apple.Safari", "com.microsoft.edgemac"] {
            #expect(!BrowserCaptureRouting.usesChromeExtension(sourceApplicationBundleIdentifier: other))
        }
    }

    @Test("Window matching retains display origin and viewport geometry")
    func matchesSelectedWindow() {
        let target = CGRect(x: -1200, y: 50, width: 1100, height: 800)
        #expect(BrowserCaptureRouting.matches(windowFrame: target.offsetBy(dx: 1, dy: -1), targetFrame: target))
        #expect(!BrowserCaptureRouting.matches(windowFrame: target.offsetBy(dx: 1200, dy: 0), targetFrame: target))
        #expect(!BrowserCaptureRouting.matches(windowFrame: CGRect(x: -1200, y: 50, width: 1000, height: 800), targetFrame: target))
    }
}
