import Foundation
import Testing
@testable import PinboardShot

@Suite("Capture automation isolation")
struct CaptureAutomationTests {
    @Test("所有公开截图模式均携带自己的贴屏选项")
    func captureModesKeepTheirOwnOptions() throws {
        let modes: [(String, CaptureAction)] = [
            ("region", .region), ("delayed", .delayedRegion), ("repeat", .repeatRegion),
            ("scroll", .scrollingRegion), ("display", .display), ("window", .window)
        ]
        for (mode, action) in modes {
            let pinnedURL = try #require(URL(string: "pinboardshot://capture?mode=\(mode)&after=pin"))
            let copyURL = try #require(URL(string: "pinboardshot://capture?mode=\(mode)"))
            #expect(AutomationCommand(url: pinnedURL) == .capture(action, pinResult: true))
            #expect(AutomationCommand(url: copyURL) == .capture(action, pinResult: false))
        }
    }

    @Test("取消或失败后，下一张普通截图不会被意外贴屏")
    func cancellationClearsRequestOptions() {
        var pipeline = CapturePipelineState()
        let transition1 = pipeline.beginCapture(pinWhenReady: true)
        #expect(transition1)
        pipeline.cancelCapture()
        #expect(!pipeline.isCapturing)
        #expect(!pipeline.shouldPinWhenReady)
        let transition2 = pipeline.beginCapture()
        #expect(transition2)
        let transition3 = pipeline.completeCapture(explicitPin: false)
        #expect(!transition3)
    }

    @Test("忙碌期间的新自动化请求不能改变当前结果")
    func rejectedCaptureDoesNotChangeCurrentOptions() {
        var pipeline = CapturePipelineState()
        let transition4 = pipeline.beginCapture()
        #expect(transition4)
        let transition5 = pipeline.beginCapture(pinWhenReady: true)
        #expect(!transition5)
        let transition6 = pipeline.completeCapture(explicitPin: false)
        #expect(!transition6)

        let transition7 = pipeline.beginCapture(pinWhenReady: true)
        #expect(transition7)
        let transition8 = pipeline.beginCapture()
        #expect(!transition8)
        let transition9 = pipeline.completeCapture(explicitPin: false)
        #expect(transition9)
    }

    @Test("延迟任务在等待前占用流程，期间贴图快捷键仍排队到同一结果")
    func reservedDelayRejectsDuplicateAndQueuesPin() {
        var pipeline = CapturePipelineState()
        let transition10 = pipeline.beginCapture()
        #expect(transition10)
        #expect(pipeline.isCapturing)
        let transition11 = pipeline.beginCapture()
        #expect(!transition11)
        let transition12 = pipeline.queuePinIfCapturing()
        #expect(transition12)
        let transition13 = pipeline.completeCapture(explicitPin: false)
        #expect(transition13)
        let transition14 = pipeline.beginCapture()
        #expect(transition14)
        let transition15 = pipeline.completeCapture(explicitPin: false)
        #expect(!transition15)
    }

    @Test("非截图指令忽略 after=pin，错误 URL 不产生指令")
    func nonCaptureCommandsCannotCarryPinIntent() throws {
        for value in ["pinboardshot://pin-clipboard?after=pin", "pinboardshot://pin?mode=clipboard&after=pin"] {
            #expect(AutomationCommand(url: try #require(URL(string: value))) == .pinClipboard)
        }
        #expect(AutomationCommand(url: try #require(URL(string: "pinboardshot://toggle-pins?after=pin"))) == .togglePins)
        for value in ["https://capture?mode=region", "pinboardshot://unknown?after=pin", "pinboardshot://capture?mode=invalid&after=pin", "pinboardshot://pin-file?path="] {
            #expect(AutomationCommand(url: try #require(URL(string: value))) == nil)
        }
    }

    @Test("文件路径只按 URL 编码解码一次，保留空格和中文")
    func filePathRoundTrip() throws {
        var components = URLComponents()
        components.scheme = "pinboardshot"
        components.host = "pin-file"
        let path = "/private/tmp/示例 image #1.png"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        #expect(AutomationCommand(url: try #require(components.url)) == .pinFile(URL(fileURLWithPath: path)))
    }
}
