import CoreGraphics
import Testing
@testable import PinboardShot

@Suite("Selected scrolling window order")
struct ScrollCaptureWindowOrderTests {
    @Test("A Chrome window in front wins even when ScreenCaptureKit lists a covered app first")
    func overlappingApplications() {
        let coveredApp: CGWindowID = 10
        let chrome: CGWindowID = 20
        let screenshotOverlay: CGWindowID = 30
        #expect(ScrollCaptureWindowOrder.frontmostID(
            eligibleIDs: [coveredApp, chrome], frontToBackIDs: [screenshotOverlay, chrome, coveredApp]
        ) == chrome)
    }

    @Test("Only windows containing the selected point participate")
    func nonIntersectingWindows() {
        #expect(ScrollCaptureWindowOrder.frontmostID(eligibleIDs: [10], frontToBackIDs: [20, 10]) == 10)
    }

    @Test("A missing or changed display list never chooses an arbitrary covered window")
    func missingWindowOrder() {
        #expect(ScrollCaptureWindowOrder.frontmostID(eligibleIDs: [10, 20], frontToBackIDs: []) == nil)
        #expect(ScrollCaptureWindowOrder.frontmostID(eligibleIDs: [10, 20], frontToBackIDs: [30]) == nil)
    }
}
