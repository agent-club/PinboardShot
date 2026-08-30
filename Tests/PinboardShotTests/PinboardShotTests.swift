import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import PinboardShot

private final class FakeSelectionOverlayWindow {}

private final class TestApplicationSupportFileManager: FileManager {
    let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        super.init()
    }

    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        if directory == .applicationSupportDirectory, domainMask == .userDomainMask {
            return [applicationSupportDirectory]
        }
        return super.urls(for: directory, in: domainMask)
    }
}

@MainActor
private final class SelectionCompletionRecorder: SelectionOverlayViewDelegate {
    private(set) var completedRect: CGRect?
    private(set) var completedAsCopy = false
    private(set) var completedAsScrollingCapture = false
    private(set) var actionPhaseCount = 0
    private(set) var cancellationCount = 0

    func selectionViewDidPrepareActions(_ view: SelectionOverlayView) {
        actionPhaseCount += 1
    }

    func selectionView(
        _ view: SelectionOverlayView,
        completed rect: CGRect?,
        disposition: SelectionDisposition
    ) {
        completedRect = rect
        if rect == nil { cancellationCount += 1 }
        if case .copy = disposition { completedAsCopy = true }
        if case .scrollingCapture = disposition { completedAsScrollingCapture = true }
    }
}

private func mouseEvent(
    _ type: NSEvent.EventType,
    at point: CGPoint,
    timestamp: TimeInterval,
    clickCount: Int = 1
) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: timestamp,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: clickCount,
        pressure: 1
    )!
}

private func keyEvent(
    keyCode: UInt16,
    characters: String,
    modifierFlags: NSEvent.ModifierFlags = []
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 1,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    )!
}

private func solidImage(size: CGSize, color: NSColor) -> NSImage {
    let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(color.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    return NSImage(cgImage: context.makeImage()!, size: size)
}

@MainActor
private func containsScrollView(_ view: NSView) -> Bool {
    view is NSScrollView || view.subviews.contains(where: containsScrollView)
}

@Test("托盘高度使用内容测量值并受屏幕可用高度约束")
func trayPanelHeightFollowsContentAndScreen() {
    #expect(TrayPanelMetrics.width == 340)
    #expect(TrayPanelMetrics.height(preferredHeight: 627.2, availableHeight: 900) == 628)
    #expect(TrayPanelMetrics.height(preferredHeight: 809, availableHeight: 700) == 676)
}

@Test("托盘普通状态按首选高度完整展示，无需滚动")
@MainActor
func trayPanelShowsAllContentWithoutScrolling() {
    let sizingPanel = TrayPanelView(
        permissionGranted: true,
        failedHotKeyCount: 0,
        canCheckForUpdates: true,
        lastUpdateCheckDate: nil,
        updateNotice: nil,
        pinCount: 0,
        pinsAreVisible: false,
        height: nil,
        onPinShadowChanged: { _ in },
        onDismissUpdateNotice: {},
        onCommand: { _ in }
    )
    let sizingController = NSHostingController(rootView: sizingPanel)
    let preferredHeight = ceil(
        sizingController.sizeThatFits(
            in: NSSize(
                width: TrayPanelMetrics.width,
                height: TrayPanelMetrics.measurementHeightLimit
            )
        ).height
    )

    #expect(preferredHeight > 0)
    // 托盘不再展示截图快捷入口区，但其余内容仍应计入首选高度并完整显示。
    #expect(preferredHeight > 500)
    #expect(preferredHeight < TrayPanelMetrics.measurementHeightLimit)

    let panel = TrayPanelView(
        permissionGranted: true,
        failedHotKeyCount: 0,
        canCheckForUpdates: true,
        lastUpdateCheckDate: nil,
        updateNotice: nil,
        pinCount: 0,
        pinsAreVisible: false,
        height: preferredHeight,
        onPinShadowChanged: { _ in },
        onDismissUpdateNotice: {},
        onCommand: { _ in }
    )
    let hostingView = NSHostingView(rootView: panel)
    hostingView.frame = NSRect(
        origin: .zero,
        size: NSSize(width: TrayPanelMetrics.width, height: preferredHeight)
    )

    hostingView.layoutSubtreeIfNeeded()

    #expect(!containsScrollView(hostingView))
}

@Test("托盘仅在屏幕高度不足时启用滚动")
@MainActor
func trayPanelScrollsOnlyWhenHeightIsConstrained() {
    let constrainedHeight: CGFloat = 420
    let panel = TrayPanelView(
        permissionGranted: true,
        failedHotKeyCount: 0,
        canCheckForUpdates: true,
        lastUpdateCheckDate: nil,
        updateNotice: nil,
        pinCount: 0,
        pinsAreVisible: false,
        height: constrainedHeight,
        onPinShadowChanged: { _ in },
        onDismissUpdateNotice: {},
        onCommand: { _ in }
    )
    let hostingView = NSHostingView(rootView: panel)
    hostingView.frame = NSRect(
        origin: .zero,
        size: NSSize(width: TrayPanelMetrics.width, height: constrainedHeight)
    )

    hostingView.layoutSubtreeIfNeeded()

    #expect(containsScrollView(hostingView))
}

@Test("偏好设置导航可直接打开指定分区")
@MainActor
func preferencesNavigationTargetsSpecificSection() {
    let navigation = PreferencesNavigationModel()
    #expect(PreferencesWindowMetrics.width == 840)
    #expect(PreferencesWindowMetrics.height == 580)
    #expect(navigation.selectedSection == .shortcuts)

    navigation.selectedSection = .history
    #expect(navigation.selectedSection == .history)

    navigation.selectedSection = .watermark
    #expect(navigation.selectedSection == .watermark)
}

@Test("偏好设置窗口按可见屏幕区域居中")
func preferencesWindowCentersInVisibleScreenFrame() {
    let origin = PreferencesWindowMetrics.centeredOrigin(
        windowSize: CGSize(width: 840, height: 612),
        in: CGRect(x: 0, y: 77, width: 1_512, height: 872)
    )

    #expect(origin == CGPoint(x: 336, y: 207))
}

@Test("工具栏取色面板锚定在颜色按钮附近并限制在可见屏幕内")
func anchoredColorWellPositionsPanelNearControl() {
    let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    let panelSize = CGSize(width: 260, height: 320)

    let bottomToolbarOrigin = AnchoredColorWell.preferredPanelOrigin(
        for: panelSize,
        anchoredTo: CGRect(x: 780, y: 24, width: 24, height: 24),
        in: screen
    )
    #expect(bottomToolbarOrigin == CGPoint(x: 540, y: 56))

    let topToolbarOrigin = AnchoredColorWell.preferredPanelOrigin(
        for: panelSize,
        anchoredTo: CGRect(x: 380, y: 550, width: 24, height: 24),
        in: screen
    )
    #expect(topToolbarOrigin == CGPoint(x: 262, y: 222))
}

@Test("Retina 截图按点像素比例输出原生尺寸")
func nativeCaptureResolution() {
    let retina = CaptureResolution.pixelDimensions(
        for: CGSize(width: 363, height: 137),
        pointPixelScale: 2
    )
    #expect(retina.width == 726)
    #expect(retina.height == 274)

    let fallback = CaptureResolution.pixelDimensions(
        for: CGSize(width: 363, height: 137),
        pointPixelScale: 0
    )
    #expect(fallback.width == 363)
    #expect(fallback.height == 137)
}

@Test("截图输出级别默认 1080p 且保持比例只放大")
func captureQualityResolutionLevels() {
    let source = CGSize(width: 726, height: 274)
    let native = CaptureExportResolution.pixelDimensions(for: source, quality: .native)
    #expect(native.width == 726)
    #expect(native.height == 274)

    let fullHD = CaptureExportResolution.pixelDimensions(for: source, quality: .fullHD1080)
    #expect(fullHD.width == 1920)
    #expect(fullHD.height == 725)

    let ultraHD = CaptureExportResolution.pixelDimensions(for: source, quality: .uhd8K)
    #expect(ultraHD.width == 7680)
    #expect(ultraHD.height == 2899)

    let portrait = CaptureExportResolution.pixelDimensions(
        for: CGSize(width: 274, height: 726),
        quality: .fullHD1080
    )
    #expect(portrait.width == 725)
    #expect(portrait.height == 1920)

    let alreadyLarger = CaptureExportResolution.pixelDimensions(
        for: CGSize(width: 3024, height: 1964),
        quality: .fullHD1080
    )
    #expect(alreadyLarger.width == 3024)
    #expect(alreadyLarger.height == 1964)

    let square8K = CaptureExportResolution.pixelDimensions(
        for: CGSize(width: 100, height: 100),
        quality: .uhd8K
    )
    #expect(square8K.width == 4320)
    #expect(square8K.height == 4320)
}

@Test("截图输出级别持久化默认值")
func captureQualityDefaults() {
    let suiteName = "PinboardShotQualityTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(CaptureQuality.current(defaults: defaults) == .fullHD1080)
    defaults.set(CaptureQuality.uhd4K.rawValue, forKey: CaptureQuality.userDefaultsKey)
    #expect(CaptureQuality.current(defaults: defaults) == .uhd4K)
    defaults.set("unknown", forKey: CaptureQuality.userDefaultsKey)
    #expect(CaptureQuality.current(defaults: defaults) == .fullHD1080)
}

@Test("OCR 插件配置默认保持本机识别并按插件隔离")
func ocrPluginSettingsDefaultToLocalAndIsolateConfigurations() {
    let suiteName = "PinboardShotOCRPluginSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(OCRPluginSettings.selectedProviderID(defaults: defaults) == OCRPluginConstants.localProviderID)
    let plugin = OCRPluginManifest.openAICompatible
    let configuration = OCRPluginConfiguration(baseURL: "https://example.com/v1", model: "vision-model")
    OCRPluginSettings.save(providerID: plugin.id, configuration: configuration, defaults: defaults)

    #expect(OCRPluginSettings.selectedProviderID(defaults: defaults) == plugin.id)
    #expect(OCRPluginSettings.configuration(for: plugin, defaults: defaults) == configuration)
}

@Test("OCR 插件请求只向用户配置的同源 HTTPS 地址注入鉴权")
func ocrPluginBuildsControlledRequest() throws {
    let manifest = OCRPluginManifest.openAICompatible
    let request = try OCRPluginRequestBuilder.request(
        manifest: manifest,
        configuration: OCRPluginConfiguration(baseURL: "https://example.com/v1/", model: "vision-model"),
        apiKey: "test-secret",
        imageData: Data([0x01, 0x02, 0x03])
    )

    #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret")
    let body = try #require(request.httpBody)
    let bodyText = try #require(String(data: body, encoding: .utf8))
    let decodedBody = try JSONDecoder().decode(JSONValue.self, from: body)
    #expect(decodedBody.string(at: ["messages", "0", "content", "1", "image_url", "url"]) == "data:image/png;base64,AQID")
    #expect(bodyText.contains("vision-model"))
    #expect(!bodyText.contains("test-secret"))
}

@Test("OCR 插件拒绝非本机 HTTP 与跨主机 endpoint")
func ocrPluginRejectsUnsafeEndpoints() throws {
    #expect(throws: OCRPluginError.insecureBaseURL) {
        try OCRPluginRequestBuilder.endpointURL(
            baseURL: "http://example.com/v1",
            endpoint: "/chat/completions"
        )
    }
    #expect(throws: OCRPluginError.invalidBaseURL) {
        try OCRPluginRequestBuilder.endpointURL(
            baseURL: "https://example.com/v1",
            endpoint: "https://attacker.example/ocr"
        )
    }
    #expect(try OCRPluginRequestBuilder.endpointURL(
        baseURL: "http://localhost:8080/v1",
        endpoint: "/ocr"
    ).absoluteString == "http://localhost:8080/v1/ocr")
    #expect(throws: OCRPluginError.invalidAPIKey) {
        try OCRPluginRequestBuilder.request(
            manifest: .openAICompatible,
            configuration: OCRPluginConfiguration(baseURL: "https://example.com/v1", model: "vision-model"),
            apiKey: "invalid\nheader",
            imageData: Data([0x01])
        )
    }
}

@Test("OCR 插件按声明路径解析文字响应")
func ocrPluginParsesDeclaredResponsePath() throws {
    let response = Data(#"{"choices":[{"message":{"content":"line one\nline two"}}]}"#.utf8)
    let text = try OCRPluginRequestBuilder.parseResponse(
        response,
        manifest: OCRPluginManifest.openAICompatible
    )
    #expect(text == "line one\nline two")

    #expect(throws: OCRPluginError.invalidResponse) {
        try OCRPluginRequestBuilder.parseResponse(Data(#"{"text":"missing path"}"#.utf8), manifest: .openAICompatible)
    }
}

@Test("OCR 插件目录只载入通过校验且 ID 不冲突的 manifest")
func ocrPluginCatalogValidatesUserManifests() throws {
    let suiteDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PinboardShotOCRPluginCatalogTests.\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: suiteDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: suiteDirectory) }
    let fileManager = TestApplicationSupportFileManager(applicationSupportDirectory: suiteDirectory)
    let pluginsDirectory = try OCRPluginCatalog.createPluginsDirectory(fileManager: fileManager)
    let customPlugin = OCRPluginManifest(
        schemaVersion: 1,
        id: "example.custom-ocr",
        name: "Example OCR",
        endpoint: "/ocr",
        authentication: OCRPluginAuthentication(header: "X-API-Key", prefix: ""),
        headers: nil,
        request: .object(["image": .string("{{imageDataURL}}")]),
        responseTextPath: "result.text",
        defaultBaseURL: "https://example.com",
        defaultModel: nil
    )
    let manifestData = try JSONEncoder().encode(customPlugin)
    try manifestData.write(to: pluginsDirectory.appendingPathComponent("custom.json"))
    try Data(#"{"schemaVersion":99}"#.utf8).write(to: pluginsDirectory.appendingPathComponent("invalid.json"))

    let result = OCRPluginCatalog.load(fileManager: fileManager)
    #expect(result.plugins.map(\.id) == ["builtin.openai-compatible", "example.custom-ocr"])
    #expect(result.errors.count == 1)
}

@Test("菜单栏图标选项可持久化且异常值回退到默认")
func trayIconChoiceDefaults() {
    let suiteName = "PinboardShotTrayIconTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(TrayIconChoice.current(defaults: defaults) == .rectangularViewfinder)
    defaults.set(TrayIconChoice.pinFilled.rawValue, forKey: TrayIconChoice.userDefaultsKey)
    #expect(TrayIconChoice.current(defaults: defaults) == .pinFilled)
    defaults.set("unknown", forKey: TrayIconChoice.userDefaultsKey)
    #expect(TrayIconChoice.current(defaults: defaults) == .rectangularViewfinder)
}

@Test("标注线宽可持久化且异常值夹到可用范围")
func annotationBrushPixelWidthDefaults() {
    let suiteName = "PinboardShotAnnotationWidthTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(AnnotationStyleSettings.brushPixelWidth(for: .mosaic, defaults: defaults) == 14)
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .arrow, defaults: defaults) == 4)
    AnnotationStyleSettings.setBrushPixelWidth(18, for: .mosaic, defaults: defaults)
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .mosaic, defaults: defaults) == 18)
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .arrow, defaults: defaults) == 4)
    defaults.set(99, forKey: AnnotationStyleSettings.brushPixelWidthKey(for: .mosaic))
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .mosaic, defaults: defaults) == 36)
    defaults.set(-4, forKey: AnnotationStyleSettings.brushPixelWidthKey(for: .mosaic))
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .mosaic, defaults: defaults) == 2)

    AnnotationStyleSettings.setBrushPixelWidth(9, defaults: defaults)
    #expect(AnnotationStyleSettings.brushPixelWidth(defaults: defaults) == 9)
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .pen, defaults: defaults) == 9)
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .rectangle, defaults: defaults) == 3)
}

@Test("取色器颜色格式可持久化并格式化为常用文本")
func colorSampleFormatPersistsAndFormatsText() {
    let suiteName = "PinboardShotColorFormatTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let color = NSColor(red: 1, green: 0.5, blue: 0, alpha: 0.25)
    #expect(ColorSampleFormat.current(defaults: defaults) == .hex)
    ColorSampleFormat.set(.rgba, defaults: defaults)
    #expect(ColorSampleFormat.current(defaults: defaults) == .rgba)
    defaults.set("unknown", forKey: ColorSampleFormat.userDefaultsKey)
    #expect(ColorSampleFormat.current(defaults: defaults) == .hex)

    #expect(ColorSampleFormat.hex.string(for: color) == "#FF8000")
    #expect(ColorSampleFormat.hexa.string(for: color) == "#FF800040")
    #expect(ColorSampleFormat.rgb.string(for: color) == "rgb(255, 128, 0)")
    #expect(ColorSampleFormat.rgba.string(for: color) == "rgba(255, 128, 0, 0.25)")
    #expect(ColorSampleFormat.hsl.string(for: color) == "hsl(30deg, 100%, 50%)")
    #expect(ColorSampleFormat.swiftUI.string(for: color) == "Color(red: 1, green: 0.5, blue: 0, opacity: 0.25)")
    #expect(ColorSampleFormat.nsColor.string(for: color) == "NSColor(red: 1, green: 0.5, blue: 0, alpha: 0.25)")
}

@Test("历史缩略图异步生成小图而不解码列表原图")
@MainActor
func historyThumbnailLoadsDownsampledImage() async throws {
    let suiteDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PinboardShotHistoryThumbnailTests.\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: suiteDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: suiteDirectory) }

    let fileManager = TestApplicationSupportFileManager(applicationSupportDirectory: suiteDirectory)
    let historyStore = HistoryStore(fileManager: fileManager)
    try historyStore.add(solidImage(size: CGSize(width: 1_200, height: 800), color: .systemRed))

    let item = try #require(historyStore.items.first)
    let thumbnail = try #require(await historyStore.thumbnail(for: item, maxPixelSize: 180))

    #expect(thumbnail.size.width <= 180)
    #expect(thumbnail.size.height <= 180)
}

@Test("历史设置采用隐私友好的默认值并校验范围")
func historySettingsDefaultsAndValidation() {
    let suiteName = "PinboardShotHistorySettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(HistorySettings.isEnabled(defaults: defaults))
    #expect(HistorySettings.maximumItems(defaults: defaults) == 50)
    #expect(HistorySettings.retentionDays(defaults: defaults) == 0)
    #expect(HistorySettings.ocrIndexingEnabled(defaults: defaults))
    #expect(QuickCaptureOverlaySettings.isEnabled(defaults: defaults))

    defaults.set(100, forKey: HistorySettings.maximumItemsDefaultsKey)
    defaults.set(30, forKey: HistorySettings.retentionDaysDefaultsKey)
    defaults.set(false, forKey: HistorySettings.ocrIndexingDefaultsKey)
    defaults.set(false, forKey: QuickCaptureOverlaySettings.enabledDefaultsKey)
    #expect(HistorySettings.maximumItems(defaults: defaults) == 100)
    #expect(HistorySettings.retentionDays(defaults: defaults) == 30)
    #expect(!HistorySettings.ocrIndexingEnabled(defaults: defaults))
    #expect(!QuickCaptureOverlaySettings.isEnabled(defaults: defaults))

    defaults.set(999, forKey: HistorySettings.maximumItemsDefaultsKey)
    defaults.set(365, forKey: HistorySettings.retentionDaysDefaultsKey)
    #expect(HistorySettings.maximumItems(defaults: defaults) == 50)
    #expect(HistorySettings.retentionDays(defaults: defaults) == 0)
}

@Test("历史按配置裁剪并持久化 OCR 文本")
@MainActor
func historyRetentionAndRecognizedText() throws {
    let suiteName = "PinboardShotHistoryRetentionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(10, forKey: HistorySettings.maximumItemsDefaultsKey)

    let suiteDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(suiteName, isDirectory: true)
    try FileManager.default.createDirectory(at: suiteDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: suiteDirectory) }
    let fileManager = TestApplicationSupportFileManager(applicationSupportDirectory: suiteDirectory)
    let store = HistoryStore(fileManager: fileManager, defaults: defaults)

    for index in 0..<12 {
        try store.add(solidImage(size: CGSize(width: 16 + index, height: 12), color: .systemBlue))
    }
    #expect(store.items.count == 10)
    let item = try #require(store.items.first)
    try store.updateRecognizedText(itemID: item.id, text: "local searchable text")

    let reloaded = HistoryStore(fileManager: fileManager, defaults: defaults)
    #expect(reloaded.items.count == 10)
    #expect(reloaded.items.first?.recognizedText == "local searchable text")
}

@Test("上次选区按屏幕比例恢复并裁剪到目标屏幕")
func lastCaptureRegionRoundTrip() throws {
    let suiteName = "PinboardShotLastRegionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    LastCaptureRegionStore.save(
        selection: CGRect(x: 100, y: 80, width: 400, height: 240),
        in: CGRect(x: 0, y: 0, width: 1_000, height: 800),
        defaults: defaults
    )
    let restored = try #require(LastCaptureRegionStore.selection(
        in: CGRect(x: 0, y: 0, width: 2_000, height: 1_200),
        defaults: defaults
    ))
    #expect(restored == CGRect(x: 200, y: 120, width: 800, height: 360))
}

@Test("截图拼板按布局、间距和边距生成确定尺寸")
@MainActor
func compositionRendererUsesConfiguredLayout() throws {
    let images = [
        solidImage(size: CGSize(width: 100, height: 50), color: .systemRed),
        solidImage(size: CGSize(width: 80, height: 60), color: .systemBlue),
    ]
    var options = CompositionOptions()
    options.layout = .horizontal
    options.background = .transparent
    options.padding = 10
    options.spacing = 5
    options.cornerRadius = 0
    options.showsShadow = false

    let output = try #require(CompositionRenderer.render(images: images, options: options))
    #expect(output.size == CGSize(width: 205, height: 80))
}

@Test("所有菜单栏图标选项在当前最低系统版本可用")
func trayIconSymbolsAreAvailable() {
    #expect(TrayIconChoice.allCases.allSatisfy {
        $0.animationSymbolNames.allSatisfy {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
    })
}

@Test("菜单栏图标按单色和彩色完整分组")
func trayIconChoicesAreGroupedByColorStyle() {
    let groupedChoices = TrayIconChoice.monochromeChoices + TrayIconChoice.colorChoices

    #expect(Set(groupedChoices) == Set(TrayIconChoice.allCases))
    #expect(TrayIconChoice.monochromeChoices.allSatisfy { !$0.usesColor })
    #expect(TrayIconChoice.colorChoices.allSatisfy { $0.usesColor })
}

@Test("新增的单色和彩色动态图标具备多帧变化")
func animatedTrayIconChoicesHaveMultipleFrames() {
    let animatedChoices: [TrayIconChoice] = [
        .animatedViewfinder,
        .animatedCamera,
        .colorfulViewfinder,
        .colorfulCamera,
        .solCrafted
    ]

    #expect(animatedChoices.allSatisfy { $0.isAnimated })
    #expect(TrayIconChoice.animatedViewfinder.animationSymbolNames.count > 1)
    #expect(TrayIconChoice.animatedCamera.animationSymbolNames.count > 1)
    #expect(TrayIconChoice.colorfulViewfinder.animationColors.count > 1)
    #expect(TrayIconChoice.colorfulCamera.animationColors.count > 1)
    #expect(TrayIconChoice.solCrafted.animationColors.count > 1)
}

@Test("菜单栏单色图标使用模板渲染而彩色图标保留颜色")
func trayIconRenderingModesAreDistinct() {
    #expect(TrayIconChoice.animatedViewfinder.statusBarImage()?.isTemplate == true)
    #expect(TrayIconChoice.colorfulViewfinder.statusBarImage()?.isTemplate == false)
    #expect(TrayIconChoice.solCrafted.statusBarImage()?.isTemplate == false)
    #expect(TrayIconChoice.solCrafted.statusBarImage()?.size == NSSize(width: 18, height: 18))
    #expect(TrayIconChoice.colorChoices.contains(.solCrafted))
}

@Test("高质量缩放生成目标像素尺寸")
func captureImageScaling() throws {
    let context = CGContext(
        data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))

    let scaled = try CaptureImageScaler.scaled(context.makeImage()!, quality: .hd720)
    #expect(scaled.width == 1280)
    #expect(scaled.height == 640)

    let image = NSImage(cgImage: scaled, size: CGSize(width: 4, height: 2))
    let encoded = try #require(image.pngData)
    let representation = try #require(NSBitmapImageRep(data: encoded))
    #expect(representation.pixelsWide == 1280)
    #expect(representation.pixelsHigh == 640)
}

@Test("8K 生成和剪贴板 TIFF 有明确内存边界")
func captureMemoryBoundaries() {
    #expect(CaptureImageScaler.canGenerate(width: 7680, height: 4320))
    #expect(!CaptureImageScaler.canGenerate(width: 7681, height: 4320))
    #expect(ClipboardImagePolicy.shouldProvideTIFF(width: 3840, height: 2160))
    #expect(!ClipboardImagePolicy.shouldProvideTIFF(width: 7680, height: 4320))
}

@Test("滚动截图能识别相邻帧的纵向重叠")
func scrollCaptureFindsVerticalOverlap() throws {
    let width = 36
    let documentHeight = 140
    let viewportHeight = 60
    let shift = 17
    let document = (0..<(width * documentHeight)).map { index in
        let x = index % width
        let y = index / width
        return UInt8((x * 13 + y * 7 + (y / 5) * 19) % 251)
    }
    let previous = Array(document[0..<(width * viewportHeight)])
    let currentStart = shift * width
    let current = Array(document[currentStart..<(currentStart + width * viewportHeight)])

    let match = try #require(ScrollFrameMatcher.match(
        previous: previous,
        current: current,
        width: width,
        height: viewportHeight
    ))

    #expect(match.verticalShift == shift)
    #expect(match.score == 0)
}

@Test("滚动截图能识别向上返回的有符号位移")
func scrollCaptureFindsBackwardVerticalOverlap() throws {
    let width = 36
    let documentHeight = 140
    let viewportHeight = 60
    let shift = 17
    let document = (0..<(width * documentHeight)).map { index in
        let x = index % width
        let y = index / width
        return UInt8((x * 13 + y * 7 + (y / 5) * 19) % 251)
    }
    let previousStart = shift * width
    let previous = Array(document[previousStart..<(previousStart + width * viewportHeight)])
    let current = Array(document[0..<(width * viewportHeight)])

    let match = try #require(ScrollFrameMatcher.match(
        previous: previous,
        current: current,
        width: width,
        height: viewportHeight
    ))

    #expect(match.verticalShift == -shift)
    #expect(match.score == 0)
}

@Test("滚动截图忽略完全重复的帧")
func scrollCaptureIgnoresDuplicateFrame() throws {
    let pixels = (0..<(24 * 40)).map { UInt8($0 % 255) }
    let match = try #require(ScrollFrameMatcher.match(
        previous: pixels,
        current: pixels,
        width: 24,
        height: 40
    ))

    #expect(match == ScrollFrameMatch(verticalShift: 0, score: 0))
}

@Test("滚动截图不会把重复 CGImage 帧追加成新像素")
func scrollCaptureIgnoresDuplicateCGImage() throws {
    let context = try #require(CGContext(
        data: nil,
        width: 80,
        height: 60,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
    let image = try #require(context.makeImage())
    let accumulator = ScrollCaptureAccumulator()

    #expect(accumulator.append(image) == .initial)
    #expect(accumulator.append(image) == .duplicate)
    #expect(accumulator.pixelHeight == 60)
}

@Test("滚动截图会追加轻微但真实的滚动位移")
func scrollCaptureAppendsSmallRealMovement() throws {
    let width = 80
    let documentHeight = 120
    let viewportHeight = 64
    let smallShift = 4
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: documentHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for y in 0..<documentHeight {
        for x in stride(from: 0, to: width, by: 4) {
            let value = CGFloat((x * 9 + y * 11 + (y / 6) * 17) % 251) / 255
            context.setFillColor(red: value, green: CGFloat(y % 13) / 13, blue: 1 - value, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: 4, height: 1))
        }
    }
    let document = try #require(context.makeImage())
    let first = try #require(document.cropping(to: CGRect(x: 0, y: 0, width: width, height: viewportHeight)))
    let second = try #require(document.cropping(to: CGRect(x: 0, y: smallShift, width: width, height: viewportHeight)))
    let accumulator = ScrollCaptureAccumulator()

    #expect(accumulator.append(first) == .initial)
    guard case .appended(let pixelHeight, _) = accumulator.append(second) else {
        Issue.record("轻微但真实的滚动位移应追加成新像素")
        return
    }
    #expect(pixelHeight == smallShift)
    #expect(accumulator.pixelHeight == viewportHeight + smallShift)
}

@Test("滚动截图从真实 CGImage 帧识别滚动距离")
func scrollCaptureMatchesCGImageFrames() throws {
    let width = 96
    let documentHeight = 180
    let viewportHeight = 80
    let shift = 21
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: documentHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for y in 0..<documentHeight {
        for x in stride(from: 0, to: width, by: 8) {
            let value = CGFloat((x * 11 + y * 7 + (y / 9) * 23) % 251) / 255
            context.setFillColor(red: value, green: 1 - value, blue: CGFloat(y % 17) / 17, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: 8, height: 1))
        }
    }
    let document = try #require(context.makeImage())
    let previous = try #require(document.cropping(to: CGRect(x: 0, y: 0, width: width, height: viewportHeight)))
    let current = try #require(document.cropping(to: CGRect(x: 0, y: shift, width: width, height: viewportHeight)))
    let match = try #require(ScrollFrameMatcher.match(previous: previous, current: current))

    #expect(abs(match.verticalShift - shift) <= 1)
}

@Test("滚动截图按视觉顺序追加新出现的底部内容")
func scrollCaptureAppendsBottomContentInOrder() throws {
    let width = 72
    let documentHeight = 150
    let viewportHeight = 64
    let shift = 19
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: documentHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for y in 0..<documentHeight {
        for x in stride(from: 0, to: width, by: 6) {
            let value = CGFloat((x * 17 + y * 13 + (y / 7) * 29) % 251) / 255
            context.setFillColor(red: value, green: CGFloat(x % 19) / 19, blue: 1 - value, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: 6, height: 1))
        }
    }
    let document = try #require(context.makeImage())
    let first = try #require(document.cropping(to: CGRect(x: 0, y: 0, width: width, height: viewportHeight)))
    let second = try #require(document.cropping(to: CGRect(x: 0, y: shift, width: width, height: viewportHeight)))
    let expected = try #require(document.cropping(to: CGRect(x: 0, y: 0, width: width, height: viewportHeight + shift)))
    let accumulator = ScrollCaptureAccumulator()

    #expect(accumulator.append(first) == .initial)
    guard case .appended = accumulator.append(second) else {
        Issue.record("第二帧没有成功追加")
        return
    }
    let stitched = try #require(accumulator.makeImage())
    let comparison = try #require(ScrollFrameMatcher.match(previous: expected, current: stitched))

    #expect(stitched.height == viewportHeight + shift)
    #expect(comparison.verticalShift <= 1)
    #expect(comparison.score <= 1)
    let encodedImage = NSImage(
        cgImage: stitched,
        size: CGSize(width: stitched.width, height: stitched.height)
    )
    #expect(encodedImage.pngData != nil)
}

@Test("滚动截图向上重访再向下时不重复追加")
func scrollCaptureRevisitsCoveredContentWithoutDuplicatingRows() throws {
    let width = 96
    let documentHeight = 220
    let viewportHeight = 80
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: documentHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for y in 0..<documentHeight {
        for x in stride(from: 0, to: width, by: 6) {
            let value = CGFloat((x * 17 + y * 13 + (y / 7) * 29) % 251) / 255
            context.setFillColor(
                red: value,
                green: CGFloat((x + y) % 23) / 23,
                blue: 1 - value,
                alpha: 1
            )
            context.fill(CGRect(x: x, y: y, width: 6, height: 1))
        }
    }
    let document = try #require(context.makeImage())
    func frame(at position: Int) throws -> CGImage {
        try #require(document.cropping(to: CGRect(
            x: 0,
            y: position,
            width: width,
            height: viewportHeight
        )))
    }

    let accumulator = ScrollCaptureAccumulator()
    #expect(accumulator.append(try frame(at: 0)) == .initial)
    guard case .appended(let firstHeight, _) = accumulator.append(try frame(at: 23)) else {
        Issue.record("首次向下滚动应追加新内容")
        return
    }
    #expect(firstHeight == 23)
    guard case .appended(let secondHeight, _) = accumulator.append(try frame(at: 46)) else {
        Issue.record("第二次向下滚动应追加新内容")
        return
    }
    #expect(secondHeight == 23)

    guard case .revisited(let firstReturnOffset, _) = accumulator.append(try frame(at: 23)) else {
        Issue.record("向上返回已捕获区域时不应追加")
        return
    }
    #expect(firstReturnOffset == 23)
    guard case .revisited(let topOffset, _) = accumulator.append(try frame(at: 0)) else {
        Issue.record("返回起始位置时不应追加")
        return
    }
    #expect(topOffset == 0)
    guard case .revisited = accumulator.append(try frame(at: 23)) else {
        Issue.record("再次向下经过已捕获区域时不应追加")
        return
    }
    guard case .revisited = accumulator.append(try frame(at: 46)) else {
        Issue.record("再次抵达历史最深位置时不应追加")
        return
    }
    guard case .appended(let resumedHeight, _) = accumulator.append(try frame(at: 69)) else {
        Issue.record("超过历史最深位置后应无缝恢复追加")
        return
    }
    #expect(resumedHeight == 23)
    #expect(accumulator.pixelHeight == viewportHeight + 69)

    let stitched = try #require(accumulator.makeImage())
    let expected = try #require(document.cropping(to: CGRect(
        x: 0,
        y: 0,
        width: width,
        height: viewportHeight + 69
    )))
    let comparison = try #require(ScrollFrameMatcher.match(previous: expected, current: stitched))
    #expect(comparison.verticalShift == 0)
    #expect(comparison.score == 0)
}

@Test("滚动截图丢失相邻帧后可通过历史关键帧重新定位")
func scrollCaptureRelocalizesAfterDroppedFrames() throws {
    let width = 96
    let documentHeight = 220
    let viewportHeight = 80
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: documentHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for y in 0..<documentHeight {
        for x in stride(from: 0, to: width, by: 8) {
            let value = CGFloat((x * 11 + y * 7 + (y / 9) * 23) % 251) / 255
            context.setFillColor(
                red: value,
                green: 1 - value,
                blue: CGFloat((x + y) % 29) / 29,
                alpha: 1
            )
            context.fill(CGRect(x: x, y: y, width: 8, height: 1))
        }
    }
    let document = try #require(context.makeImage())
    func frame(at position: Int) throws -> CGImage {
        try #require(document.cropping(to: CGRect(
            x: 0,
            y: position,
            width: width,
            height: viewportHeight
        )))
    }

    let accumulator = ScrollCaptureAccumulator()
    #expect(accumulator.append(try frame(at: 0)) == .initial)
    guard case .appended = accumulator.append(try frame(at: 20)) else {
        Issue.record("应记录第一个关键帧")
        return
    }
    guard case .appended = accumulator.append(try frame(at: 40)) else {
        Issue.record("应记录第二个关键帧")
        return
    }
    guard case .revisited = accumulator.append(try frame(at: 20)) else {
        Issue.record("应先回到已捕获区域")
        return
    }
    guard case .appended(let recoveredHeight, _) = accumulator.append(try frame(at: 90)) else {
        Issue.record("相邻帧位移过大时应通过历史关键帧重新定位")
        return
    }
    #expect(recoveredHeight == 50)
    #expect(accumulator.pixelHeight == 170)
}

@Test("滚动截图从中段开始向上时可前插未覆盖内容")
func scrollCapturePrependsNewContentAboveInitialViewport() throws {
    let width = 96
    let documentHeight = 180
    let viewportHeight = 80
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: documentHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for y in 0..<documentHeight {
        for x in stride(from: 0, to: width, by: 8) {
            let value = CGFloat((x * 7 + y * 19 + (y / 5) * 17) % 251) / 255
            context.setFillColor(
                red: value,
                green: CGFloat((x + y) % 31) / 31,
                blue: 1 - value,
                alpha: 1
            )
            context.fill(CGRect(x: x, y: y, width: 8, height: 1))
        }
    }
    let document = try #require(context.makeImage())
    func frame(at position: Int) throws -> CGImage {
        try #require(document.cropping(to: CGRect(
            x: 0,
            y: position,
            width: width,
            height: viewportHeight
        )))
    }

    let accumulator = ScrollCaptureAccumulator()
    #expect(accumulator.append(try frame(at: 40)) == .initial)
    guard case .appended(let firstPrependHeight, _) = accumulator.append(try frame(at: 20)) else {
        Issue.record("向上滚动应前插第一段未覆盖内容")
        return
    }
    #expect(firstPrependHeight == 20)
    guard case .appended(let secondPrependHeight, _) = accumulator.append(try frame(at: 0)) else {
        Issue.record("继续向上滚动应前插第二段未覆盖内容")
        return
    }
    #expect(secondPrependHeight == 20)
    #expect(accumulator.pixelHeight == 120)

    let stitched = try #require(accumulator.makeImage())
    let expected = try #require(document.cropping(to: CGRect(
        x: 0,
        y: 0,
        width: width,
        height: 120
    )))
    let comparison = try #require(ScrollFrameMatcher.match(previous: expected, current: stitched))
    #expect(comparison.verticalShift == 0)
    #expect(comparison.score == 0)
}

@Test("滚动截图在高度重复内容没有唯一位置时拒绝扩展")
func scrollCaptureDoesNotGuessOnPerfectlyRepeatedContent() throws {
    let width = 80
    let viewportHeight = 60
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: viewportHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for y in 0..<viewportHeight {
        let repeatedRow = y % 20
        for x in stride(from: 0, to: width, by: 5) {
            let value = CGFloat((x * 11 + repeatedRow * 17) % 251) / 255
            context.setFillColor(red: value, green: 1 - value, blue: 0.5, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: 5, height: 1))
        }
    }
    let repeatedViewport = try #require(context.makeImage())
    let accumulator = ScrollCaptureAccumulator()

    #expect(accumulator.append(repeatedViewport) == .initial)
    #expect(accumulator.append(repeatedViewport) == .duplicate)
    #expect(accumulator.pixelHeight == viewportHeight)
}

@Test("滚动截图匹配可排除少量固定区域干扰")
func scrollCaptureMatcherToleratesFixedBand() throws {
    let width = 120
    let documentHeight = 180
    let viewportHeight = 80
    let shift = 18
    let fixedBandHeight = 12
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: documentHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for y in 0..<documentHeight {
        for x in stride(from: 0, to: width, by: 6) {
            let value = CGFloat((x * 19 + y * 11 + (y / 7) * 31) % 251) / 255
            context.setFillColor(red: value, green: 1 - value, blue: CGFloat(y % 17) / 17, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: 6, height: 1))
        }
    }
    let document = try #require(context.makeImage())
    func frame(at position: Int) throws -> CGImage {
        let content = try #require(document.cropping(to: CGRect(
            x: 0,
            y: position,
            width: width,
            height: viewportHeight
        )))
        let frameContext = try #require(CGContext(
            data: nil,
            width: width,
            height: viewportHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        frameContext.draw(content, in: CGRect(x: 0, y: 0, width: width, height: viewportHeight))
        for x in stride(from: 0, to: width, by: 8) {
            let value = CGFloat((x * 23) % 251) / 255
            frameContext.setFillColor(red: value, green: 0.2, blue: 1 - value, alpha: 1)
            frameContext.fill(CGRect(x: x, y: 0, width: 8, height: fixedBandHeight))
        }
        return try #require(frameContext.makeImage())
    }

    let match = try #require(ScrollFrameMatcher.match(
        previous: try frame(at: 0),
        current: try frame(at: shift)
    ))
    #expect(abs(match.verticalShift - shift) <= 1)
}

@Test("滚动截图使用磁盘后备存储扩展长图边界")
func scrollCaptureHasBackingStoreBoundary() {
    #expect(ScrollCaptureAccumulator.canAppend(
        width: 1_600,
        currentHeight: 155_000,
        appendedHeight: 1_250
    ))
    #expect(!ScrollCaptureAccumulator.canAppend(
        width: 1_600,
        currentHeight: 156_250,
        appendedHeight: 1
    ))
}

@Test("滚动截图预览保持正向并渲染超长图的可见区域")
@MainActor
func scrollCapturePreviewRendersLongImageUpright() throws {
    _ = NSApplication.shared
    let previewWidth = 5
    let previewHeight = 4_096
    let context = try #require(CGContext(
        data: nil,
        width: previewWidth,
        height: previewHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(NSColor.systemRed.cgColor)
    context.fill(CGRect(
        x: 0,
        y: previewHeight / 2,
        width: previewWidth,
        height: previewHeight / 2
    ))
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(
        x: 0,
        y: 0,
        width: previewWidth,
        height: previewHeight / 2
    ))
    let image = NSImage(
        cgImage: try #require(context.makeImage()),
        size: CGSize(width: previewWidth, height: previewHeight)
    )
    let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 260, height: 420))
    let imageView = ScrollCapturePreviewImageView()
    scrollView.documentView = imageView
    imageView.scrollView = scrollView
    imageView.image = image
    imageView.updateDocumentSize()

    #expect(imageView.frame.height > 200_000)
    #expect(scrollView.documentVisibleRect.minY == 0)
    let drawingRects = try #require(imageView.drawingRects(for: imageView.bounds))
    #expect(drawingRects.destination.height <= scrollView.documentVisibleRect.height)
    #expect(drawingRects.source.height < image.size.height)

    let rendered = try #require(
        scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds)
    )
    scrollView.cacheDisplay(in: scrollView.bounds, to: rendered)
    let visibleColor = try #require(rendered.colorAt(
        x: rendered.pixelsWide / 2,
        y: rendered.pixelsHigh / 2
    ))

    #expect(visibleColor.blueComponent > visibleColor.redComponent)
}

@Test("区域坐标转换")
func regionCoordinateConversion() {
    let geometry = CaptureGeometry(
        screenFrame: CGRect(x: -1440, y: 0, width: 1440, height: 900),
        selection: CGRect(x: -1300, y: 200, width: 640, height: 360)
    )
    #expect(geometry.sourceRect == CGRect(x: 140, y: 340, width: 640, height: 360))
    #expect(geometry.pixelCropRect(for: CGSize(width: 2880, height: 1800)) == CGRect(x: 280, y: 680, width: 1280, height: 720))
}

@Test("滚动截图把 AppKit 选区转换为窗口内坐标")
func scrollCaptureCoordinateConversion() {
    let geometry = ScrollCaptureGeometry(
        screenFrame: CGRect(x: -1440, y: 0, width: 1440, height: 900),
        displayBounds: CGRect(x: -1440, y: 0, width: 1440, height: 900),
        selection: CGRect(x: -1200, y: 180, width: 600, height: 500),
        windowFrame: CGRect(x: -1260, y: 120, width: 760, height: 680)
    )

    #expect(geometry.quartzSelectionRect == CGRect(x: -1200, y: 220, width: 600, height: 500))
    #expect(geometry.selectionInWindow == CGRect(x: 60, y: 100, width: 600, height: 500))
}

@Test("新安装默认不创建快捷键")
@MainActor
func newInstallStartsWithoutShortcuts() {
    let suiteName = "PinboardShotEmptyShortcutTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = ShortcutStore(defaults: defaults)

    #expect(store.bindings.isEmpty)
    #expect(store.shortcut(for: .region) == nil)
}

@Test("快捷键显示文本稳定")
func shortcutDisplayText() {
    let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: [.command, .shift])
    #expect(shortcut.displayText == "⇧⌘P")
}

@Test("功能键快捷键按用户习惯显示 fn")
func functionShortcutDisplayText() {
    let shortcut = Shortcut(keyCode: UInt32(kVK_F1), carbonModifiers: 0)
    #expect(shortcut.isSafeGlobalShortcut)
    #expect(shortcut.displayText == "fn F1")
}

@Test("快捷键存储拒绝内部冲突")
@MainActor
func shortcutConflictDetection() {
    let suiteName = "PinboardShotTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = ShortcutStore(defaults: defaults)
    let duplicate = Shortcut(keyCode: UInt32(kVK_F4), carbonModifiers: 0)
    #expect(store.add(action: .region, shortcut: duplicate) != nil)
    #expect(store.add(action: .display, shortcut: duplicate) == nil)

    let initialCount = store.bindings.count
    let additional = Shortcut(keyCode: UInt32(kVK_F5), carbonModifiers: 0)
    let addedID = store.add(action: .display, shortcut: additional)
    #expect(addedID != nil)
    #expect(store.bindings.count == initialCount + 1)
    #expect(store.bindings.contains { $0.action == .display && $0.shortcut == additional })

    if let addedID { store.remove(bindingID: addedID) }
    #expect(store.bindings.count == initialCount)
}

@Test("重新创建快捷键存储后保留用户绑定")
@MainActor
func shortcutBindingsPersistAcrossStoreRecreation() {
    let suiteName = "PinboardShotPersistenceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let shortcut = Shortcut(keyCode: UInt32(kVK_F7), carbonModifiers: 0)

    let originalStore = ShortcutStore(defaults: defaults)
    #expect(originalStore.add(action: .region, shortcut: shortcut) != nil)

    let reloadedStore = ShortcutStore(defaults: defaults)
    #expect(reloadedStore.shortcut(for: .region) == shortcut)
    #expect(reloadedStore.bindings.count == 1)
}

@Test("旧版固定快捷键配置只迁移用户自定义绑定")
@MainActor
func legacyShortcutMigration() throws {
    let suiteName = "PinboardShotMigrationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let legacyRegion = Shortcut(keyCode: UInt32(kVK_F7), carbonModifiers: 0)
    let legacy = [CaptureAction.region.rawValue: legacyRegion]
    defaults.set(try JSONEncoder().encode(legacy), forKey: "shortcuts.v1")

    let store = ShortcutStore(defaults: defaults)
    #expect(store.shortcut(for: .region) == legacyRegion)
    #expect(store.bindings.count == 1)
}

@Test("旧版内置默认快捷键升级后为空")
@MainActor
func legacyDefaultsUpgrade() throws {
    let suiteName = "PinboardShotLegacyDefaultsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let legacy: [String: Shortcut] = [
        CaptureAction.region.rawValue: Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: [.command, .shift]),
        CaptureAction.clipboardPin.rawValue: Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift])
    ]
    defaults.set(try JSONEncoder().encode(legacy), forKey: "shortcuts.v1")

    let store = ShortcutStore(defaults: defaults)
    #expect(store.bindings.isEmpty)
}

@Test("v2 配置升级时移除内置默认并保留用户自定义绑定")
@MainActor
func versionTwoBindingsUpgrade() throws {
    let suiteName = "PinboardShotVersionTwoTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let builtIn = ShortcutBinding(
        action: .regionAndPin,
        shortcut: Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: [.command, .shift])
    )
    let custom = ShortcutBinding(
        action: .display,
        shortcut: Shortcut(keyCode: UInt32(kVK_F7), carbonModifiers: 0)
    )
    defaults.set(try JSONEncoder().encode([builtIn, custom]), forKey: "shortcutBindings.v2")

    let store = ShortcutStore(defaults: defaults)

    #expect(store.bindings == [custom])
}

@Test("重置快捷键会恢复为空")
@MainActor
func resetShortcutsClearsBindings() {
    let suiteName = "PinboardShotResetShortcutTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = ShortcutStore(defaults: defaults)
    _ = store.add(action: .region, shortcut: Shortcut(keyCode: UInt32(kVK_F7), carbonModifiers: 0))

    store.reset()

    #expect(store.bindings.isEmpty)
}

@Test("贴图管理器同时保留多张图片")
@MainActor
func multiplePinnedImages() {
    _ = NSApplication.shared
    let manager = PinWindowManager()
    let image = NSImage(size: CGSize(width: 120, height: 80))
    manager.pin(image: image, near: CGPoint(x: 200, y: 200))
    manager.pin(image: image, near: CGPoint(x: 260, y: 260))
    #expect(manager.count == 2)
    #expect(manager.pinsAreVisible)
    manager.toggleAll()
    #expect(!manager.pinsAreVisible)
    manager.toggleAll()
    #expect(manager.pinsAreVisible)
    manager.restoreInteraction()
    manager.closeAll()
    #expect(manager.count == 0)
}

@Test("截图遮罩保留系统逃生能力")
@MainActor
func overlaySafetyInvariants() {
    _ = NSApplication.shared
    let window = SelectionOverlayWindow(
        contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    #expect(window.canBecomeKey)
    #expect(OverlaySafetyPolicy.windowLevel.rawValue < NSWindow.Level.screenSaver.rawValue)
    #expect(OverlaySafetyPolicy.timeout <= .seconds(12))
    #expect(OverlaySafetyPolicy.warningLead > .zero)
    #expect(OverlaySafetyPolicy.warningLead < OverlaySafetyPolicy.timeout)
    #expect(OverlaySafetyPolicy.actionTimeout > OverlaySafetyPolicy.timeout)
    #expect(OverlaySafetyPolicy.awaitingActionDimAlpha < OverlaySafetyPolicy.selectingDimAlpha)
}

@Test("截图窗口把用户操作转发给空闲超时续期")
@MainActor
func overlayWindowForwardsUserActivity() {
    _ = NSApplication.shared
    let window = SelectionOverlayWindow(
        contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    var activity: [NSEvent.EventType] = []
    window.onUserActivity = { activity.append($0) }

    window.sendEvent(mouseEvent(.mouseMoved, at: CGPoint(x: 20, y: 20), timestamp: 1))

    #expect(activity == [.mouseMoved])
}

@Test("截图遮罩完成至多一次并复用隐藏窗口")
func overlayLifecycleIsIdempotentAndReusable() throws {
    var lifecycle = SelectionOverlayLifecycle<FakeSelectionOverlayWindow>()
    var creationCount = 0
    let first = try #require(lifecycle.begin {
        creationCount += 1
        return FakeSelectionOverlayWindow()
    })

    #expect(!first.reused)
    #expect(lifecycle.isActive)
    let firstFinish = lifecycle.finish()
    #expect(firstFinish === first.window)
    #expect(lifecycle.finish() == nil)
    #expect(!lifecycle.isActive)
    #expect(lifecycle.retainedWindow === first.window)

    let second = try #require(lifecycle.begin {
        creationCount += 1
        return FakeSelectionOverlayWindow()
    })
    #expect(second.reused)
    #expect(second.window === first.window)
    #expect(creationCount == 1)
    _ = lifecycle.finish()
}

@Test("截图诊断只记录阶段与错误类型")
func captureDiagnosticsPhases() {
    let suiteName = "PinboardShotDiagnosticsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    CaptureDiagnostics.begin(defaults: defaults)
    #expect(defaults.string(forKey: "captureDiagnostics.lastPhase") == "captureStarted")
    #expect(defaults.object(forKey: "captureDiagnostics.lastRejectedCrop") == nil)

    CaptureDiagnostics.recordPhase("selectionCompleted", defaults: defaults)
    CaptureDiagnostics.recordError(PinboardShotError.emptyCaptureFrame, defaults: defaults)
    #expect(defaults.string(forKey: "captureDiagnostics.lastPhase") == "selectionCompleted")
    #expect(defaults.string(forKey: "captureDiagnostics.lastErrorType")?.contains("PinboardShotError") == true)
    let report = CaptureDiagnostics.report(defaults: defaults)
    #expect(report.contains("Last capture phase: selectionCompleted"))
    #expect(report.contains("Last error type:"))
    #expect(report.contains("No screenshot pixels, file paths, or user content are included."))
}

@Test("截图完成前的贴图请求会排队")
func clipboardPinQueuesDuringCapture() {
    var state = CapturePipelineState()
    let began = state.beginCapture()
    let queued = state.queuePinIfCapturing()
    let shouldPin = state.completeCapture(explicitPin: false)
    #expect(began)
    #expect(queued)
    #expect(shouldPin)
    #expect(!state.isCapturing)
    #expect(!state.shouldPinWhenReady)
}

@Test("截图进行中再次请求不会开始新截图")
func duplicateCaptureIsRejected() {
    var state = CapturePipelineState()
    let first = state.beginCapture()
    let duplicate = state.beginCapture()
    #expect(first)
    #expect(!duplicate)
    state.cancelCapture()
    let afterCancellation = state.beginCapture()
    #expect(afterCancellation)
}

@Test("连续贴图使用可预测的级联偏移")
func pinCascadeOffsets() {
    #expect(PinWindowCascade.offset(for: 0) == 0)
    #expect(PinWindowCascade.offset(for: 1) == 24)
    #expect(PinWindowCascade.offset(for: 7) == 168)
    #expect(PinWindowCascade.offset(for: 8) == 0)
}

@Test("CGImage 截图会显式写入 PNG 和 TIFF 并可读回")
@MainActor
func imagePasteboardRoundTrip() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("PinboardShotTests.\(UUID().uuidString)"))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: 12,
        height: 12,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
    let image = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 12, height: 12))
    let clipboard = ImageClipboard(pasteboard: pasteboard)

    #expect(clipboard.write(image))
    #expect(pasteboard.data(forType: .png) != nil)
    #expect(pasteboard.data(forType: .tiff) != nil)
    let restored = clipboard.read()
    #expect(restored != nil)
}

@Test("选区双击不依赖 AppKit clickCount")
func selectionDoubleClickTracking() {
    var tracker = SelectionDoubleClickTracker()
    let first = tracker.registerClick(timestamp: 10.0, point: CGPoint(x: 40, y: 50), maximumInterval: 0.5)
    let second = tracker.registerClick(timestamp: 10.2, point: CGPoint(x: 42, y: 51), maximumInterval: 0.5)
    let late = tracker.registerClick(timestamp: 11.0, point: CGPoint(x: 40, y: 50), maximumInterval: 0.5)
    let distant = tracker.registerClick(timestamp: 11.2, point: CGPoint(x: 80, y: 90), maximumInterval: 0.5)
    #expect(!first)
    #expect(second)
    #expect(!late)
    #expect(!distant)
}

@Test("选区四边和四角都可命中拉伸")
func selectionResizeHandleHitTesting() {
    let rect = CGRect(x: 100, y: 80, width: 400, height: 300)
    #expect(SelectionResizeGeometry.handle(at: CGPoint(x: 100, y: 380), in: rect) == .topLeft)
    #expect(SelectionResizeGeometry.handle(at: CGPoint(x: 300, y: 380), in: rect) == .top)
    #expect(SelectionResizeGeometry.handle(at: CGPoint(x: 500, y: 230), in: rect) == .right)
    #expect(SelectionResizeGeometry.handle(at: CGPoint(x: 300, y: 230), in: rect) == nil)
}

@Test("选区拉伸受屏幕边界和最小尺寸约束")
func selectionResizeGeometryConstraints() {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    let rect = CGRect(x: 100, y: 100, width: 400, height: 300)
    let expanded = SelectionResizeGeometry.resizedRect(
        rect,
        using: .topRight,
        translation: CGPoint(x: 500, y: 500),
        constrainedTo: bounds
    )
    #expect(expanded == CGRect(x: 100, y: 100, width: 700, height: 500))

    let minimum = SelectionResizeGeometry.resizedRect(
        rect,
        using: .bottomLeft,
        translation: CGPoint(x: 1000, y: 1000),
        constrainedTo: bounds
    )
    #expect(minimum.width == SelectionResizeGeometry.minimumDimension)
    #expect(minimum.height == SelectionResizeGeometry.minimumDimension)
}

@Test("精确尺寸在锁定比例时实时联动并等比适配屏幕")
func selectionExactSizePreservesAspectRatio() {
    let fromWidth = SelectionSizeGeometry.constrainedSize(
        width: 1_600,
        height: 200,
        aspectRatio: 16 / 9,
        editedDimension: .width,
        maximumSize: CGSize(width: 1_920, height: 1_080)
    )
    #expect(fromWidth == CGSize(width: 1_600, height: 900))

    let fromHeight = SelectionSizeGeometry.constrainedSize(
        width: 200,
        height: 900,
        aspectRatio: 4 / 3,
        editedDimension: .height,
        maximumSize: CGSize(width: 1_920, height: 1_080)
    )
    #expect(fromHeight == CGSize(width: 1_200, height: 900))

    let fitted = SelectionSizeGeometry.constrainedSize(
        width: 3_840,
        height: 100,
        aspectRatio: 16 / 9,
        editedDimension: .width,
        maximumSize: CGSize(width: 1_920, height: 1_080)
    )
    #expect(fitted == CGSize(width: 1_920, height: 1_080))
}

@Test("连续输入宽高时只联动另一输入框且不打断当前内容")
@MainActor
func selectionSizeEditorKeepsActiveFieldStable() {
    let editor = SelectionSizeEditorCoordinator(
        size: CGSize(width: 1_280, height: 720),
        currentRatio: 16 / 9,
        lockedRatio: 16 / 9,
        maximumSize: CGSize(width: 1_920, height: 1_080)
    )

    for (typedWidth, linkedHeight) in [("8", "5"), ("80", "45"), ("800", "450")] {
        editor.widthField.stringValue = typedWidth
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.widthField))
        #expect(editor.widthField.stringValue == typedWidth)
        #expect(editor.heightField.stringValue == linkedHeight)
    }

    editor.heightField.stringValue = "900"
    editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.heightField))
    #expect(editor.heightField.stringValue == "900")
    #expect(editor.widthField.stringValue == "1600")

    editor.widthField.stringValue = "not-a-number"
    #expect(editor.resultSize() == nil)

    let content = editor.makePopoverContent(onApply: { _, _ in }, onCancel: {})
    content.layoutSubtreeIfNeeded()
    let widthFrame = editor.widthField.convert(editor.widthField.bounds, to: content)
    let heightFrame = editor.heightField.convert(editor.heightField.bounds, to: content)
    let ratioFrame = editor.ratioControl.convert(editor.ratioControl.bounds, to: content)
    #expect(content.bounds.size == CGSize(width: 440, height: 292))
    #expect(content.bounds.contains(widthFrame))
    #expect(content.bounds.contains(heightFrame))
    #expect(content.bounds.contains(ratioFrame))
    #expect(widthFrame.maxX < heightFrame.minX)
    #expect(ratioFrame.width > 390)
    #expect(ratioFrame.maxY < min(widthFrame.minY, heightFrame.minY))
}

@Test("工具条尺寸浮层可以完成输入、联动和应用")
@MainActor
func selectionSizePopoverCompletesInteraction() throws {
    let editor = SelectionSizeEditorCoordinator(
        size: CGSize(width: 1_280, height: 720),
        currentRatio: 16 / 9,
        lockedRatio: 16 / 9,
        maximumSize: CGSize(width: 1_920, height: 1_080)
    )
    var appliedResult: (size: CGSize, aspectRatio: CGFloat?)?
    _ = editor.makePopoverContent(
        onApply: { size, aspectRatio in appliedResult = (size, aspectRatio) },
        onCancel: {}
    )
    editor.widthField.stringValue = "800"
    editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.widthField))
    editor.applyPanel()
    let result = try #require(appliedResult)
    #expect(result.size == CGSize(width: 800, height: 450))
    #expect(abs((result.aspectRatio ?? 0) - CGFloat(16) / 9) < 0.001)
}

@Test("比例预设和值映射完整")
func selectionAspectRatioPresets() {
    #expect(SelectionAspectRatioPreset.free.ratio(currentRatio: 1.37) == nil)
    #expect(SelectionAspectRatioPreset.current.ratio(currentRatio: 1.37) == 1.37)
    #expect(SelectionAspectRatioPreset.square.ratio(currentRatio: 1.37) == 1)
    #expect(SelectionAspectRatioPreset.fourThree.ratio(currentRatio: 1.37) == CGFloat(4) / 3)
    #expect(SelectionAspectRatioPreset.threeTwo.ratio(currentRatio: 1.37) == CGFloat(3) / 2)
    #expect(SelectionAspectRatioPreset.sixteenNine.ratio(currentRatio: 1.37) == CGFloat(16) / 9)
    #expect(SelectionAspectRatioPreset.nineSixteen.ratio(currentRatio: 1.37) == CGFloat(9) / 16)
}

@Test("比例锁定后重新拖画选区也保持比例并限制在屏幕内")
func selectionAspectLockedCreationGeometry() {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    let endpoint = SelectionSizeGeometry.aspectLockedEndpoint(
        from: CGPoint(x: 100, y: 100),
        to: CGPoint(x: 760, y: 500),
        aspectRatio: 16 / 9,
        constrainedTo: bounds
    )
    let width = endpoint.x - 100
    let height = endpoint.y - 100
    #expect(bounds.contains(endpoint))
    #expect(abs(width / height - CGFloat(16) / 9) < 0.001)
}

@Test("锁定比例后拖动边和角都保持比例与锚点")
func selectionAspectLockedResizeGeometry() {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    let rect = CGRect(x: 100, y: 100, width: 400, height: 300)
    let fromRight = SelectionResizeGeometry.resizedRect(
        rect,
        using: .right,
        translation: CGPoint(x: 200, y: 0),
        constrainedTo: bounds,
        aspectRatio: 4 / 3
    )
    #expect(fromRight == CGRect(x: 100, y: 25, width: 600, height: 450))

    let fromTopRight = SelectionResizeGeometry.resizedRect(
        rect,
        using: .topRight,
        translation: CGPoint(x: 200, y: 0),
        constrainedTo: bounds,
        aspectRatio: 4 / 3
    )
    #expect(fromTopRight == CGRect(x: 100, y: 100, width: 600, height: 450))

    let bounded = SelectionResizeGeometry.resizedRect(
        rect,
        using: .topRight,
        translation: CGPoint(x: 900, y: 900),
        constrainedTo: bounds,
        aspectRatio: 4 / 3
    )
    #expect(bounds.contains(bounded))
    #expect(abs(bounded.width / bounded.height - 4 / 3) < 0.01)
}

@Test("选区边角和内部映射到对应鼠标指针")
func selectionCursorKinds() {
    let rect = CGRect(x: 100, y: 80, width: 400, height: 300)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 100, y: 380), in: rect) == .diagonalNorthWestSouthEast)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 300, y: 380), in: rect) == .verticalResize)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 500, y: 380), in: rect) == .diagonalNorthEastSouthWest)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 500, y: 230), in: rect) == .horizontalResize)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 500, y: 80), in: rect) == .diagonalNorthWestSouthEast)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 300, y: 80), in: rect) == .verticalResize)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 100, y: 80), in: rect) == .diagonalNorthEastSouthWest)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 100, y: 230), in: rect) == .horizontalResize)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 300, y: 230), in: rect) == .move)
    #expect(SelectionResizeGeometry.cursorKind(at: CGPoint(x: 40, y: 40), in: rect) == .crosshair)
}

@Test("选区整体移动受屏幕边界约束")
func selectionMoveGeometryConstraints() {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    let rect = CGRect(x: 100, y: 100, width: 400, height: 300)
    #expect(
        SelectionResizeGeometry.movedRect(
            rect,
            translation: CGPoint(x: 120, y: 80),
            constrainedTo: bounds
        ) == CGRect(x: 220, y: 180, width: 400, height: 300)
    )
    #expect(
        SelectionResizeGeometry.movedRect(
            rect,
            translation: CGPoint(x: 900, y: -900),
            constrainedTo: bounds
        ) == CGRect(x: 400, y: 0, width: 400, height: 300)
    )
}

@Test("截图覆盖层把透明选区保留为鼠标交互区域")
@MainActor
func selectionOverlayKeepsTransparentRegionInteractive() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    #expect(view.hitTest(CGPoint(x: 400, y: 300)) === view)
    #expect(view.acceptsFirstMouse(for: nil))
}

@Test("右键不会关闭截图而 Esc 仍会取消")
@MainActor
func rightClickIsConsumedAndEscapeStillCancels() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder

    view.rightMouseDown(with: mouseEvent(.rightMouseDown, at: CGPoint(x: 300, y: 250), timestamp: 1))
    #expect(recorder.cancellationCount == 0)

    view.keyDown(with: keyEvent(keyCode: UInt16(kVK_Escape), characters: "\u{1b}"))
    #expect(recorder.cancellationCount == 1)
}

@Test("在截图选区内双击会直接确认复制")
@MainActor
func doubleClickInsideSelectionCompletesCapture() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 50, y: 50), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 700, y: 500), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 700, y: 500), timestamp: 1.2))

    let insideSelection = CGPoint(x: 300, y: 250)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 2))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: insideSelection, timestamp: 2.05))
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 2.2, clickCount: 2))

    #expect(recorder.completedRect != nil)
    #expect(recorder.completedAsCopy)
}

@Test("已框选区域可从右边缘贴边拉伸后继续完成截图")
@MainActor
func resizeExistingSelectionFromEdge() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 400), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 400), timestamp: 1.2))

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 500, y: 250), timestamp: 2))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 650, y: 250), timestamp: 2.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 650, y: 250), timestamp: 2.2))

    let insideSelection = CGPoint(x: 300, y: 250)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 3))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: insideSelection, timestamp: 3.05))
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 3.2, clickCount: 2))

    #expect(recorder.completedRect == CGRect(x: 100, y: 100, width: 550, height: 300))
    #expect(recorder.completedAsCopy)
}

@Test("已框选区域可整体拖动后继续完成截图")
@MainActor
func moveExistingSelection() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 400), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 400), timestamp: 1.2))

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 300, y: 250), timestamp: 2))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 420, y: 330), timestamp: 2.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 420, y: 330), timestamp: 2.2))

    let insideSelection = CGPoint(x: 420, y: 330)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 3))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: insideSelection, timestamp: 3.05))
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 3.2, clickCount: 2))

    #expect(recorder.completedRect == CGRect(x: 220, y: 180, width: 400, height: 300))
    #expect(recorder.completedAsCopy)
}

@Test("从已有选区外拖动会重新框选")
@MainActor
func dragOutsideExistingSelectionStartsNewSelection() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 400), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 400), timestamp: 1.2))

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 620, y: 450), timestamp: 2))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 760, y: 560), timestamp: 2.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 760, y: 560), timestamp: 2.2))
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 700, y: 500), timestamp: 3, clickCount: 2))

    #expect(recorder.completedRect == CGRect(x: 620, y: 450, width: 140, height: 110))
    #expect(recorder.completedAsCopy)
}

@Test("选区工具栏直接展示具体标注工具且不需要外层标注模式")
@MainActor
func selectionToolbarUsesCenteredAccessibleIcons() throws {
    let suiteName = "PinboardShotToolbarDefaultsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let image = solidImage(size: CGSize(width: 800, height: 600), color: .white)
    var proposedRect = CGRect(x: 0, y: 0, width: 800, height: 600)
    view.previewSourceImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    view.previewImage = image
    view.annotationStyleDefaults = defaults
    view.toolbarConfigurationDefaults = defaults
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 150), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 450), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 450), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let buttons = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
    let visibleButtons = buttons.filter { !$0.isHidden }
    let separators = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarSeparator }
    let dragHandle = try #require(stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarDragHandleView }.first)
    let copy = try #require(buttons.first { $0.toolTip == L10n.text("overlay.copyTooltip") })
    let mosaic = try #require(buttons.first { $0.toolTip == L10n.text(AnnotationTool.mosaic.titleKey) })
    let pen = try #require(buttons.first { $0.toolTip == L10n.text(AnnotationTool.pen.titleKey) })
    let clear = try #require(buttons.first { $0.toolTip == L10n.text("annotation.clear") })
    let colorWell = try #require(stack.arrangedSubviews.compactMap { $0 as? NSColorWell }.first)
    let widthControl = try #require(stack.arrangedSubviews.compactMap { $0 as? OverlayWidthControl }.first)

    #expect(!toolbar.isHidden)
    #expect(toolbar.frame.minX >= 12)
    #expect(toolbar.frame.maxX <= view.bounds.maxX - 12)
    #expect(toolbar.frame.maxY < 150)
    #expect(toolbar.frame.width < 460)
    #expect(stack.distribution == .equalSpacing)
    #expect(visibleButtons.count == 10)
    #expect(Array(visibleButtons.prefix(AnnotationTool.selectionTools.count)).map { $0.accessibilityLabel() ?? "" } ==
        AnnotationTool.selectionTools.map { L10n.text($0.titleKey) })
    #expect(!visibleButtons.contains { $0.accessibilityLabel() == L10n.text("overlay.edit") })
    #expect(!visibleButtons.contains { $0.accessibilityLabel() == L10n.text("overlay.finishEditing") })
    #expect(dragHandle.accessibilityLabel() == L10n.text("overlay.dragToolbar"))
    #expect(colorWell.isHidden)
    #expect(stack.arrangedSubviews.compactMap { $0 as? NSPopUpButton }.allSatisfy { $0.isHidden })
    #expect(widthControl.isHidden)
    #expect(clear.isHidden)
    #expect(!clear.isEnabled)
    #expect(separators.filter { !$0.isHidden }.count == 2)
    #expect(copy.isPrimaryActionStyle)
    #expect(SelectionToolbarAction.copy.iconDefaultsKey == "selectionToolbar.icon.copy")
    #expect(buttons.allSatisfy { $0.image != nil && !($0.toolTip ?? "").isEmpty })
    let penIndex = try #require(stack.arrangedSubviews.firstIndex { $0 === pen })
    let colorIndex = try #require(stack.arrangedSubviews.firstIndex { $0 === colorWell })
    let widthIndex = try #require(stack.arrangedSubviews.firstIndex { $0 === widthControl })

    #expect(colorIndex == penIndex + 1)
    #expect(widthIndex == colorIndex + 1)
    #expect(widthControl.value == AnnotationStyleSettings.defaultBrushPixelWidth(for: .mosaic))
    #expect(widthControl.accessibilityLabel() == L10n.text("annotation.width"))
    #expect(mosaic.state == .off)
    pen.performClick(nil)
    let canvas = try #require(view.subviews.compactMap { $0 as? AnnotationCanvasView }.first)
    #expect(!canvas.isHidden)
    #expect(toolbar.frame.width > 520)
    #expect(buttons.filter { !$0.isHidden }.count == 13)
    #expect(!colorWell.isHidden)
    #expect(!widthControl.isHidden)
    #expect(!clear.isHidden)
    #expect(!clear.isEnabled)
    #expect(pen.state == .on)
    #expect(pen.isSelectedStyle)
    #expect(mosaic.state == .off)
    pen.performClick(nil)
    #expect(canvas.isHidden)
    #expect(colorWell.isHidden)
    #expect(widthControl.isHidden)
    #expect(clear.isHidden)
    #expect(pen.state == .off)
    #expect(!pen.isSelectedStyle)
    for button in buttons where !button.isHidden {
        let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: view)
        #expect(view.hitTest(point) === button)
    }
}

@Test("窄窗口中的直接标注工具栏保持在可见范围内")
@MainActor
func directAnnotationToolbarStaysInsideNarrowOverlay() throws {
    let size = CGSize(width: 420, height: 360)
    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    let image = solidImage(size: size, color: .white)
    var proposedRect = CGRect(origin: .zero, size: size)
    view.previewSourceImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    view.previewImage = image
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 40, y: 80), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 380, y: 300), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 380, y: 300), timestamp: 1.2))

    let toolbar = try #require(view.subviews.compactMap { $0 as? NSVisualEffectView }.first)
    #expect(toolbar.frame.width <= view.bounds.width - 24)
    #expect(toolbar.frame.minX >= 12)
    #expect(toolbar.frame.maxX <= view.bounds.maxX - 12)
    #expect(toolbar.frame.minY >= 0)
    #expect(toolbar.frame.maxY <= view.bounds.maxY)
}

@Test("工具频次排序只在下一次框选生效")
@MainActor
func selectionToolbarUsageSortingDoesNotMoveCurrentButtons() throws {
    let suiteName = "PinboardShotToolbarUsageOrderTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    SelectionToolbarConfiguration.setVisible(true, for: .pickColor, defaults: defaults)
    SelectionToolbarConfiguration.setManualOrder(
        [.copy, .pickColor, .annotate, .pin, .cancel, .scrollingCapture, .selectionSize],
        defaults: defaults
    )
    SelectionToolbarConfiguration.setAutomaticallySortsByUsage(true, defaults: defaults)

    func makeView() -> SelectionOverlayView {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let image = solidImage(size: CGSize(width: 800, height: 600), color: .white)
        var proposedRect = CGRect(x: 0, y: 0, width: 800, height: 600)
        view.previewSourceImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        view.previewImage = image
        view.toolbarConfigurationDefaults = defaults
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 150), timestamp: 1))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 450), timestamp: 1.1))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 450), timestamp: 1.2))
        return view
    }

    func visibleLabels(in view: SelectionOverlayView) -> [String] {
        let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
        let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
        return stack.arrangedSubviews
            .compactMap { $0 as? OverlayToolbarButton }
            .filter { !$0.isHidden }
            .compactMap { $0.accessibilityLabel() }
    }

    let currentView = makeView()
    let initialOrder = visibleLabels(in: currentView)
    #expect(Array(initialOrder.prefix(2)) == [
        L10n.text("common.copy"),
        L10n.text("overlay.pickColor")
    ])
    #expect(Array(initialOrder.dropFirst(2).prefix(AnnotationTool.selectionTools.count)) ==
        AnnotationTool.selectionTools.map { L10n.text($0.titleKey) })
    #expect(!initialOrder.contains(L10n.text("overlay.edit")))
    let toolbar = currentView.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let picker = try #require(stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.accessibilityLabel() == L10n.text("overlay.pickColor") })
    picker.performClick(nil)
    #expect(visibleLabels(in: currentView) == initialOrder)

    let nextView = makeView()
    #expect(visibleLabels(in: nextView).first == L10n.text("overlay.pickColor"))
}

@Test("选区取色器双击时按所选格式复制当前像素")
@MainActor
func selectionColorPickerDoubleClickCopiesSampledPixel() throws {
    let size = CGSize(width: 400, height: 400)
    let context = CGContext(
        data: nil,
        width: 4,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    context.setFillColor(NSColor(red: 1, green: 0.5, blue: 0, alpha: 1).cgColor)
    context.fill(CGRect(x: 2, y: 1, width: 1, height: 1))
    let source = try #require(context.makeImage())
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("PinboardShotColorPickerTests.\(UUID().uuidString)"))
    let suiteName = "PinboardShotColorPickerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewSourceImage = source
    view.previewImage = NSImage(cgImage: source, size: size)
    view.colorPasteboard = pasteboard
    view.colorPickerDefaults = defaults
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 40, y: 40), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 360, y: 360), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 360, y: 360), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let colorFormatPopup = stack.arrangedSubviews.compactMap { $0 as? NSPopUpButton }.first!
    colorFormatPopup.selectItem(withTag: ColorSampleFormat.rgb.menuTag)
    colorFormatPopup.sendAction(colorFormatPopup.action, to: colorFormatPopup.target)
    view.mouseMoved(with: mouseEvent(.mouseMoved, at: CGPoint(x: 250, y: 150), timestamp: 1.9))
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 250, y: 150), timestamp: 2, clickCount: 2))

    #expect(pasteboard.string(forType: .string) == "rgb(255, 128, 0)")
    #expect(ColorSampleFormat.current(defaults: defaults) == .rgb)
    #expect(recorder.cancellationCount == 1)
}

@Test("取色模式跟随鼠标显示颜色预览并可在浮窗切换格式")
@MainActor
func selectionColorPickerPreviewFollowsPointerAndChangesFormat() throws {
    let size = CGSize(width: 400, height: 400)
    let context = CGContext(
        data: nil,
        width: 4,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    context.setFillColor(NSColor(red: 1, green: 0.5, blue: 0, alpha: 1).cgColor)
    context.fill(CGRect(x: 2, y: 1, width: 1, height: 1))
    let source = try #require(context.makeImage())
    let suiteName = "PinboardShotColorPickerPreviewTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewSourceImage = source
    view.previewImage = NSImage(cgImage: source, size: size)
    view.colorPickerDefaults = defaults
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 40, y: 40), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 360, y: 360), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 360, y: 360), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? OverlayToolbarView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let colorPicker = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.accessibilityLabel() == L10n.text("overlay.pickColor") }!
    colorPicker.performClick(nil)
    view.mouseMoved(with: mouseEvent(.mouseMoved, at: CGPoint(x: 250, y: 150), timestamp: 2))

    let preview = try #require(view.subviews.compactMap { $0 as? ColorPickerPreviewView }.first)
    #expect(!preview.isHidden)
    #expect(preview.displayedValue == "#FF8000")
    #expect(preview.frame.minX >= 10)
    #expect(preview.frame.maxX <= view.bounds.maxX - 10)
    #expect(preview.frame.minY >= 10)
    #expect(preview.frame.maxY <= view.bounds.maxY - 10)

    preview.formatPopup.selectItem(withTag: ColorSampleFormat.rgba.menuTag)
    preview.formatPopup.sendAction(preview.formatPopup.action, to: preview.formatPopup.target)

    #expect(preview.displayedValue == "rgba(255, 128, 0, 1)")
    #expect(ColorSampleFormat.current(defaults: defaults) == .rgba)
}

@Test("取色模式单击固定颜色再次单击恢复跟随")
@MainActor
func selectionColorPickerSingleClickFreezesAndResumesPreview() throws {
    let size = CGSize(width: 400, height: 400)
    let context = CGContext(
        data: nil,
        width: 4,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    context.setFillColor(NSColor(red: 1, green: 0.5, blue: 0, alpha: 1).cgColor)
    context.fill(CGRect(x: 2, y: 1, width: 1, height: 1))
    let source = try #require(context.makeImage())

    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewSourceImage = source
    view.previewImage = NSImage(cgImage: source, size: size)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 40, y: 40), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 360, y: 360), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 360, y: 360), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? OverlayToolbarView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let colorPicker = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.accessibilityLabel() == L10n.text("overlay.pickColor") }!
    colorPicker.performClick(nil)
    view.mouseMoved(with: mouseEvent(.mouseMoved, at: CGPoint(x: 250, y: 150), timestamp: 2))

    let preview = try #require(view.subviews.compactMap { $0 as? ColorPickerPreviewView }.first)
    #expect(preview.displayedValue == "#FF8000")

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 250, y: 150), timestamp: 2.1))
    view.mouseMoved(with: mouseEvent(.mouseMoved, at: CGPoint(x: 50, y: 50), timestamp: 2.2))
    #expect(preview.displayedValue == "#FF8000")

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 250, y: 250), timestamp: 3))
    view.mouseMoved(with: mouseEvent(.mouseMoved, at: CGPoint(x: 250, y: 250), timestamp: 3.1))
    #expect(preview.displayedValue != "#FF8000")
}

@Test("取色模式右键复制固定颜色并退出")
@MainActor
func selectionColorPickerRightClickCopiesFrozenSample() throws {
    let size = CGSize(width: 400, height: 400)
    let context = CGContext(
        data: nil,
        width: 4,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    context.setFillColor(NSColor(red: 1, green: 0.5, blue: 0, alpha: 1).cgColor)
    context.fill(CGRect(x: 2, y: 1, width: 1, height: 1))
    let source = try #require(context.makeImage())
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("PinboardShotColorPickerRightClickTests.\(UUID().uuidString)"))

    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewSourceImage = source
    view.previewImage = NSImage(cgImage: source, size: size)
    view.colorPasteboard = pasteboard
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 40, y: 40), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 360, y: 360), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 360, y: 360), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? OverlayToolbarView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let colorPicker = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.accessibilityLabel() == L10n.text("overlay.pickColor") }!
    colorPicker.performClick(nil)
    view.mouseMoved(with: mouseEvent(.mouseMoved, at: CGPoint(x: 250, y: 150), timestamp: 2))
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 250, y: 150), timestamp: 2.1))
    view.rightMouseDown(with: mouseEvent(.rightMouseDown, at: CGPoint(x: 50, y: 50), timestamp: 3))

    #expect(pasteboard.string(forType: .string) == "#FF8000")
    #expect(recorder.cancellationCount == 1)
}

@Test("取色模式隐藏选区框并使用全屏灰色蒙层")
@MainActor
func selectionColorPickerModeHidesSelectionFrame() throws {
    let size = CGSize(width: 400, height: 300)
    let image = solidImage(size: size, color: .white)
    var proposedRect = CGRect(origin: .zero, size: size)
    let source = try #require(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))

    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewSourceImage = source
    view.previewImage = image
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 80), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 300, y: 220), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 300, y: 220), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? OverlayToolbarView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let colorPicker = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.accessibilityLabel() == L10n.text("overlay.pickColor") }!
    colorPicker.performClick(nil)

    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    let boundary = try #require(bitmap.colorAt(
        x: Int(100 * scale),
        y: Int((view.bounds.height - 150) * scale)
    )?.usingColorSpace(.deviceRGB))

    #expect(abs(boundary.redComponent - boundary.greenComponent) < 0.03)
    #expect(abs(boundary.greenComponent - boundary.blueComponent) < 0.03)
}

@Test("选区工具栏图标预设都可显示")
func selectionToolbarIconPresetsAreValid() {
    for action in SelectionToolbarAction.allCases {
        #expect(action.presetSymbolNames.first == action.defaultSymbolName)
        #expect(Set(action.presetSymbolNames).count == action.presetSymbolNames.count)
        for symbolName in action.presetSymbolNames {
            #expect(NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil)
        }
    }
}

@Test("选区工具栏记住上一次标注线宽")
@MainActor
func selectionToolbarPersistsAnnotationWidth() {
    let suiteName = "PinboardShotToolbarWidthTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    AnnotationStyleSettings.setBrushPixelWidth(14, for: .mosaic, defaults: defaults)
    AnnotationStyleSettings.setBrushPixelWidth(6, for: .arrow, defaults: defaults)
    let image = solidImage(size: CGSize(width: 800, height: 600), color: .white)
    var proposedRect = CGRect(x: 0, y: 0, width: 800, height: 600)
    let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)!

    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    view.previewSourceImage = source
    view.previewImage = image
    view.annotationStyleDefaults = defaults
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 150), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 450), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 450), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let widthControl = stack.arrangedSubviews.compactMap { $0 as? OverlayWidthControl }.first!
    #expect(widthControl.value == 14)

    widthControl.value = 22
    widthControl.sendAction(widthControl.action, to: widthControl.target)
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .mosaic, defaults: defaults) == 22)
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .arrow, defaults: defaults) == 6)

    let arrow = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.toolTip == L10n.text(AnnotationTool.arrow.titleKey) }!
    arrow.performClick(nil)
    #expect(widthControl.value == 6)
    widthControl.value = 10
    widthControl.sendAction(widthControl.action, to: widthControl.target)
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .mosaic, defaults: defaults) == 22)
    #expect(AnnotationStyleSettings.brushPixelWidth(for: .arrow, defaults: defaults) == 10)

    let nextView = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    nextView.previewSourceImage = source
    nextView.previewImage = image
    nextView.annotationStyleDefaults = defaults
    nextView.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 120, y: 160), timestamp: 2))
    nextView.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 520, y: 460), timestamp: 2.1))
    nextView.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 520, y: 460), timestamp: 2.2))

    let nextToolbar = nextView.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let nextStack = nextToolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let nextWidthControl = nextStack.arrangedSubviews.compactMap { $0 as? OverlayWidthControl }.first!
    #expect(nextWidthControl.value == 22)
    let nextArrow = nextStack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.toolTip == L10n.text(AnnotationTool.arrow.titleKey) }!
    nextArrow.performClick(nil)
    #expect(nextWidthControl.value == 10)
}

@Test("选区工具栏可直接进入滚动截图")
@MainActor
func selectionToolbarStartsScrollingCapture() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 180, y: 150), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 580, y: 450), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 580, y: 450), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let scrollingCapture = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.toolTip == L10n.text("action.scrollingRegion") }!
    scrollingCapture.performClick(nil)

    #expect(recorder.completedRect == CGRect(x: 180, y: 150, width: 400, height: 300))
    #expect(recorder.completedAsScrollingCapture)
}

@Test("无工具栏滚动框选完成后保留选区描边状态")
@MainActor
func scrollingSelectionCanKeepOutlineVisible() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder
    view.showsToolbar = false
    view.defaultDisposition = .scrollingCapture
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 180, y: 150), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 580, y: 450), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 580, y: 450), timestamp: 1.2))
    view.presentScrollingCaptureOutline()

    #expect(recorder.completedRect == CGRect(x: 180, y: 150, width: 400, height: 300))
    #expect(recorder.completedAsScrollingCapture)
    #expect(view.isPresentingScrollingCaptureOutline)
}

@Test("选区工具栏 OCR 进入标注而不关闭选区")
@MainActor
func selectionToolbarOCRStartsAnnotationMode() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    let image = solidImage(size: CGSize(width: 900, height: 600), color: .white)
    var proposedRect = CGRect(x: 0, y: 0, width: 900, height: 600)
    let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)!
    view.previewSourceImage = source
    view.previewImage = image
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 180, y: 150), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 580, y: 450), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 580, y: 450), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let ocr = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.toolTip == L10n.text(AnnotationTool.ocr.titleKey) }!
    ocr.performClick(nil)

    let canvas = view.subviews.compactMap { $0 as? AnnotationCanvasView }.first!
    #expect(recorder.completedRect == nil)
    #expect(!canvas.isHidden)
    #expect(ocr.isSelectedStyle)
}

@Test("选区工具栏左侧把手可拖拽且不替换选区")
@MainActor
func selectionToolbarDragHandleMovesToolbarWithoutReplacingSelection() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 180, y: 150), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 580, y: 450), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 580, y: 450), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? OverlayToolbarView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let handle = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarDragHandleView }.first!
    let dragGlyph = handle.subviews.compactMap { $0 as? NSImageView }.first
    #expect(dragGlyph?.image != nil)
    #expect((dragGlyph?.image?.size.width ?? 0) > 0)
    #expect((dragGlyph?.image?.size.height ?? 0) > 0)
    #expect(dragGlyph?.contentTintColor == .secondaryLabelColor)
    #expect(handle.bounds.width == 16)
    let originalFrame = toolbar.frame
    let start = handle.convert(CGPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: view)
    handle.mouseDown(with: mouseEvent(.leftMouseDown, at: start, timestamp: 2))
    handle.mouseDragged(with: mouseEvent(
        .leftMouseDragged,
        at: CGPoint(x: start.x + 80, y: start.y + 120),
        timestamp: 2.1
    ))
    handle.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: start.x + 80, y: start.y + 120), timestamp: 2.2))

    #expect(toolbar.frame.minX > originalFrame.minX)
    #expect(toolbar.frame.minY > originalFrame.minY)
    #expect(toolbar.frame.maxX <= view.bounds.maxX - 8)
    #expect(toolbar.frame.maxY <= view.bounds.maxY - 8)

    let insideSelection = CGPoint(x: 560, y: 430)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 3))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: insideSelection, timestamp: 3.05))
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 3.2, clickCount: 2))

    #expect(recorder.completedRect == CGRect(x: 180, y: 150, width: 400, height: 300))
    #expect(recorder.completedAsCopy)
}

@Test("工具栏空白区域的鼠标序列不会触发新框选")
@MainActor
func toolbarBackgroundGestureDoesNotReplaceSelection() {
    let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 150), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 450), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 450), timestamp: 1.2))
    #expect(recorder.actionPhaseCount == 1)

    let toolbar = view.subviews.compactMap { $0 as? OverlayToolbarView }.first!
    let toolbarPoint = CGPoint(x: toolbar.frame.midX, y: toolbar.frame.midY)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: toolbarPoint, timestamp: 2))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 760, y: 40), timestamp: 2.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 760, y: 40), timestamp: 2.2))

    let insideSelection = CGPoint(x: 300, y: 250)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 3))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: insideSelection, timestamp: 3.05))
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: insideSelection, timestamp: 3.2, clickCount: 2))

    #expect(recorder.completedRect == CGRect(x: 100, y: 150, width: 400, height: 300))
}

@Test("点击具体标注工具后直接记录选区笔迹")
@MainActor
func inlineAnnotationExpandsToolbarAndRecordsStroke() {
    let size = CGSize(width: 800, height: 600)
    let context = CGContext(
        data: nil,
        width: 800,
        height: 600,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    let source = context.makeImage()!

    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewSourceImage = source
    view.previewImage = NSImage(cgImage: source, size: size)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 400), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 400), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let buttons = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
    let pen = buttons.first { $0.toolTip == L10n.text(AnnotationTool.pen.titleKey) }!
    pen.performClick(nil)

    let canvas = view.subviews.compactMap { $0 as? AnnotationCanvasView }.first!
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 150, y: 150), timestamp: 2))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 250, y: 220), timestamp: 2.1))
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 250, y: 220), timestamp: 2.2))

    let clear = buttons.first { $0.toolTip == L10n.text("annotation.clear") }!
    #expect(buttons.filter { !$0.isHidden }.count == 13)
    #expect(!buttons.contains { $0.toolTip == L10n.text("overlay.finishEditing") })
    #expect(pen.state == .on)
    #expect(pen.isSelectedStyle)
    #expect(clear.isEnabled)
    #expect(buttons.first { $0.toolTip == L10n.text("action.scrollingRegion") }!.isHidden)
    #expect(!canvas.isHidden)
    #expect(canvas.layer?.borderWidth == 1.5)
    #expect(canvas.layer?.borderColor != nil)
    #expect(view.annotations.count == 1)
    #expect(view.annotations.first?.tool == .pen)
}

@Test("非编辑态移动选区时不拖带旧选区快照")
@MainActor
func movingSelectionDoesNotDragCachedAnnotationImage() throws {
    let size = CGSize(width: 800, height: 600)
    let context = CGContext(
        data: nil,
        width: 800,
        height: 600,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.systemRed.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 400, y: 0, width: 400, height: 600))
    let source = context.makeImage()!

    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewSourceImage = source
    view.previewImage = NSImage(cgImage: source, size: size)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 300, y: 300), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 300, y: 300), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let buttons = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
    let pen = buttons.first { $0.toolTip == L10n.text(AnnotationTool.pen.titleKey) }!
    pen.performClick(nil)
    let canvas = view.subviews.compactMap { $0 as? AnnotationCanvasView }.first!
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 140, y: 140), timestamp: 2))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 180, y: 180), timestamp: 2.1))
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 180, y: 180), timestamp: 2.2))
    pen.performClick(nil)

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 200, y: 200), timestamp: 3))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 200), timestamp: 3.1))

    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    let sampled = try #require(bitmap.colorAt(
        x: Int(500 * scale),
        y: Int(200 * scale)
    )?.usingColorSpace(.deviceRGB))
    #expect(sampled.blueComponent > sampled.redComponent)
}

@Test("选择具体标注工具后可以直接调整颜色和粗细")
@MainActor
func expandedAnnotationToolbarPreservesStyleBeforeToolSelection() {
    let size = CGSize(width: 800, height: 600)
    let context = CGContext(
        data: nil,
        width: 800,
        height: 600,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    let source = context.makeImage()!

    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewSourceImage = source
    view.previewImage = NSImage(cgImage: source, size: size)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 400), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 400), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let colorWell = stack.arrangedSubviews.compactMap { $0 as? NSColorWell }.first!
    let widthControl = stack.arrangedSubviews.compactMap { $0 as? OverlayWidthControl }.first!
    let pen = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.toolTip == L10n.text(AnnotationTool.pen.titleKey) }!
    pen.performClick(nil)
    colorWell.color = .systemBlue
    colorWell.sendAction(colorWell.action, to: colorWell.target)
    widthControl.value = 18
    widthControl.sendAction(widthControl.action, to: widthControl.target)
    let canvas = view.subviews.compactMap { $0 as? AnnotationCanvasView }.first!
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 150, y: 150), timestamp: 2))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 250, y: 220), timestamp: 2.1))
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 250, y: 220), timestamp: 2.2))

    let stroke = view.annotations.first!
    #expect(stroke.color == AnnotationColor(.systemBlue))
    #expect(abs(stroke.width - 0.06) < 0.0001)
}

@Test("OCR 工具拖选后立即生成识别 tooltip")
@MainActor
func ocrToolCreatesImmediateTooltipAnnotation() {
    let size = CGSize(width: 800, height: 600)
    let image = solidImage(size: size, color: .white)
    var proposedRect = CGRect(origin: .zero, size: size)
    let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)!

    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewSourceImage = source
    view.previewImage = NSImage(cgImage: source, size: size)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 400), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 400), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let ocr = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.toolTip == L10n.text(AnnotationTool.ocr.titleKey) }!
    ocr.performClick(nil)

    let canvas = view.subviews.compactMap { $0 as? AnnotationCanvasView }.first!
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 150, y: 150), timestamp: 2))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 320, y: 230), timestamp: 2.1))
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 320, y: 230), timestamp: 2.2))

    let stroke = view.annotations.first
    #expect(stroke?.tool == .ocr)
    #expect(stroke?.text == L10n.text("annotation.ocr.pending"))
    #expect(stroke?.points.count == 2)
}

@Test("具体标注工具绘制时双击也会完成截图且不保留双击圆点")
@MainActor
func doubleClickInsideAnnotationCanvasCompletesCapture() {
    let size = CGSize(width: 800, height: 600)
    let context = CGContext(
        data: nil,
        width: 800,
        height: 600,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    let source = context.makeImage()!
    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    let recorder = SelectionCompletionRecorder()
    view.delegate = recorder
    view.previewSourceImage = source
    view.previewImage = NSImage(cgImage: source, size: size)
    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 400), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 400), timestamp: 1.2))

    let toolbar = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    let stack = toolbar.subviews.compactMap { $0 as? NSStackView }.first!
    let mosaic = stack.arrangedSubviews.compactMap { $0 as? OverlayToolbarButton }
        .first { $0.toolTip == L10n.text(AnnotationTool.mosaic.titleKey) }!
    mosaic.performClick(nil)

    let canvas = view.subviews.compactMap { $0 as? AnnotationCanvasView }.first!
    let point = CGPoint(x: 220, y: 220)
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: point, timestamp: 2))
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: point, timestamp: 2.05))
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: point, timestamp: 2.2, clickCount: 2))

    #expect(recorder.completedRect == CGRect(x: 100, y: 100, width: 400, height: 300))
    #expect(recorder.completedAsCopy)
    #expect(view.annotations.isEmpty)
}

@Test("文字工具原地提交并进入最终渲染")
@MainActor
func textAnnotationCommitsAndRenders() throws {
    let context = CGContext(
        data: nil,
        width: 240,
        height: 120,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 240, height: 120))
    let source = context.makeImage()!
    let canvas = AnnotationCanvasView(
        sourceImage: source,
        logicalSize: CGSize(width: 240, height: 120),
        contentInset: 0
    )
    canvas.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
    canvas.tool = .text
    canvas.annotationColor = .systemRed
    canvas.brushPixelWidth = 12
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 24, y: 60), timestamp: 1))

    let field = canvas.subviews.compactMap { $0 as? NSTextField }.first!
    field.stringValue = "PinboardShot 文字标注测试 1234567890"
    canvas.commitPendingText()

    let stroke = try #require(canvas.strokes.first)
    #expect(stroke.tool == .text)
    #expect(stroke.text == "PinboardShot 文字标注测试 1234567890")
    let rendered = try AnnotationRenderer.render(image: source, strokes: canvas.strokes)
    #expect(rendered.dataProvider?.data != source.dataProvider?.data)
}

@Test("文字工具图标明确表达输入光标")
@MainActor
func textToolUsesTypingCursorSymbol() {
    #expect(AnnotationTool.text.symbolName == "character.cursor.ibeam")
    #expect(NSImage(systemSymbolName: AnnotationTool.text.symbolName, accessibilityDescription: nil) != nil)
}

@Test("已提交文字可改颜色字号并双击重新编辑")
@MainActor
func committedTextCanBeRestyledAndEditedAgain() throws {
    let context = CGContext(
        data: nil,
        width: 240,
        height: 120,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 240, height: 120))
    let canvas = AnnotationCanvasView(
        sourceImage: context.makeImage()!,
        logicalSize: CGSize(width: 240, height: 120),
        contentInset: 0
    )
    canvas.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
    canvas.tool = .text
    canvas.annotationColor = .systemRed
    canvas.brushPixelWidth = 10
    var selectedStyle: (AnnotationColor, CGFloat)?
    canvas.onSelectedTextStyleChanged = { color, width in
        selectedStyle = (AnnotationColor(color), width)
    }
    let anchor = CGPoint(x: 24, y: 60)
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: anchor, timestamp: 1))
    let initialField = try #require(canvas.subviews.compactMap { $0 as? AnnotationTextField }.first)
    initialField.stringValue = "可再次编辑"
    canvas.commitPendingText()

    canvas.annotationColor = .systemBlue
    canvas.brushPixelWidth = 18
    var stroke = try #require(canvas.strokes.first)
    #expect(stroke.color == AnnotationColor(.systemBlue))
    #expect(abs(stroke.width - 0.3) < 0.001)

    let selectedBitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    canvas.cacheDisplay(in: canvas.bounds, to: selectedBitmap)
    let selectedPNG = selectedBitmap.representation(using: .png, properties: [:])!
    canvas.tool = .pen
    let unselectedBitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    canvas.cacheDisplay(in: canvas.bounds, to: unselectedBitmap)
    let unselectedPNG = unselectedBitmap.representation(using: .png, properties: [:])!
    #expect(selectedPNG != unselectedPNG)
    canvas.tool = .text
    selectedStyle = nil
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: anchor, timestamp: 2, clickCount: 2))
    let editingField = try #require(canvas.subviews.compactMap { $0 as? AnnotationTextField }.first)
    #expect(selectedStyle?.0 == AnnotationColor(.systemBlue))
    #expect(selectedStyle?.1 == 18)
    #expect(editingField.stringValue == "可再次编辑")
    #expect(AnnotationColor(editingField.textColor ?? .clear) == AnnotationColor(.systemBlue))
    #expect(editingField.font?.pointSize == 36)
    editingField.stringValue = "文字已经更新"
    canvas.commitPendingText()

    stroke = try #require(canvas.strokes.first)
    #expect(canvas.strokes.count == 1)
    #expect(stroke.text == "文字已经更新")
    #expect(stroke.color == AnnotationColor(.systemBlue))
    canvas.undo()
    #expect(canvas.strokes.first?.text == "可再次编辑")
}

@Test("已提交文字可实时拖动并在松手后记录一次历史")
@MainActor
func committedTextCanBeDraggedWithinCanvasAndUndone() throws {
    let context = CGContext(
        data: nil,
        width: 240,
        height: 120,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 240, height: 120))
    let canvas = AnnotationCanvasView(
        sourceImage: context.makeImage()!,
        logicalSize: CGSize(width: 240, height: 120),
        contentInset: 0
    )
    canvas.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
    canvas.tool = .text
    canvas.brushPixelWidth = 10
    let originalPoint = CGPoint(x: 24, y: 50)
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: originalPoint, timestamp: 1))
    let field = try #require(canvas.subviews.compactMap { $0 as? AnnotationTextField }.first)
    field.stringValue = "拖动文字"
    canvas.commitPendingText()
    let originalAnchor = try #require(canvas.strokes.first?.points.first)
    let beforeDrag = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    canvas.cacheDisplay(in: canvas.bounds, to: beforeDrag)
    let beforeDragPNG = beforeDrag.representation(using: .png, properties: [:])!

    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: originalPoint, timestamp: 2))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 100, y: 80), timestamp: 2.1))
    let duringDrag = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    canvas.cacheDisplay(in: canvas.bounds, to: duringDrag)
    let duringDragPNG = duringDrag.representation(using: .png, properties: [:])!
    #expect(canvas.strokes.first?.points.first == originalAnchor)
    #expect(duringDragPNG != beforeDragPNG)
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 100, y: 80), timestamp: 2.2))

    let movedAnchor = try #require(canvas.strokes.first?.points.first)
    #expect(abs(movedAnchor.x - 100 / 240) < 0.001)
    #expect(abs(movedAnchor.y - 80 / 120) < 0.001)
    canvas.undo()
    #expect(canvas.strokes.first?.points.first == originalAnchor)

    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: originalPoint, timestamp: 3))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 500), timestamp: 3.1))
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 500), timestamp: 3.2))
    let boundedAnchor = try #require(canvas.strokes.first?.points.first)
    #expect(boundedAnchor.x < 1)
    #expect(boundedAnchor.y < 1)
}

@Test("已提交矩形可整体拖动、限制在画布内并撤销")
@MainActor
func committedRectangleCanBeDraggedWithinCanvasAndUndone() throws {
    let context = CGContext(
        data: nil,
        width: 240,
        height: 120,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 240, height: 120))
    let canvas = AnnotationCanvasView(
        sourceImage: context.makeImage()!,
        logicalSize: CGSize(width: 240, height: 120),
        contentInset: 0
    )
    canvas.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
    canvas.tool = .rectangle

    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 30, y: 30), timestamp: 1))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 110, y: 80), timestamp: 1.1))
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 110, y: 80), timestamp: 1.2))
    let originalPoints = try #require(canvas.strokes.first?.points)

    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 50, y: 50), timestamp: 2))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 100, y: 70), timestamp: 2.1))
    #expect(canvas.strokes.first?.points == originalPoints)
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 100, y: 70), timestamp: 2.2))

    let movedPoints = try #require(canvas.strokes.first?.points)
    #expect(canvas.strokes.count == 1)
    #expect(abs(movedPoints[0].x - 80 / 240) < 0.001)
    #expect(abs(movedPoints[0].y - 50 / 120) < 0.001)
    #expect(abs(movedPoints[1].x - 160 / 240) < 0.001)
    #expect(abs(movedPoints[1].y - 100 / 120) < 0.001)

    canvas.undo()
    #expect(canvas.strokes.first?.points == originalPoints)

    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 50, y: 50), timestamp: 3))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 500), timestamp: 3.1))
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 500), timestamp: 3.2))
    let boundedPoints = try #require(canvas.strokes.first?.points)
    #expect(abs((boundedPoints[1].x - boundedPoints[0].x) - (originalPoints[1].x - originalPoints[0].x)) < 0.001)
    #expect(abs((boundedPoints[1].y - boundedPoints[0].y) - (originalPoints[1].y - originalPoints[0].y)) < 0.001)
    #expect(boundedPoints.allSatisfy { (0 ... 1).contains($0.x) && (0 ... 1).contains($0.y) })
}

@Test("文字工具空输入框双击仍会完成截图")
@MainActor
func emptyTextFieldDoubleClickRequestsCompletion() {
    let context = CGContext(
        data: nil,
        width: 120,
        height: 80,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
    let canvas = AnnotationCanvasView(
        sourceImage: context.makeImage()!,
        logicalSize: CGSize(width: 120, height: 80),
        contentInset: 0
    )
    canvas.frame = CGRect(x: 0, y: 0, width: 120, height: 80)
    canvas.tool = .text
    var requestedCompletion = false
    canvas.onDoubleClick = { requestedCompletion = true }
    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 20, y: 40), timestamp: 1))

    let field = canvas.subviews.compactMap { $0 as? AnnotationTextField }.first!
    #expect(!field.isBezeled)
    #expect(!field.drawsBackground)
    #expect(field.focusRingType == .none)
    #expect(field.layer?.cornerRadius == AnnotationTextField.cornerRadius)
    #expect(field.layer?.backgroundColor?.alpha == AnnotationTextField.backgroundAlpha)
    field.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 20, y: 40), timestamp: 1.2, clickCount: 2))

    #expect(requestedCompletion)
    #expect(canvas.subviews.compactMap { $0 as? AnnotationTextField }.isEmpty)
}

@Test("马赛克拖动过程中实时显示像素化结果")
@MainActor
func mosaicPreviewUpdatesBeforeMouseUp() {
    let context = CGContext(
        data: nil,
        width: 64,
        height: 64,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for x in 0..<64 {
        context.setFillColor((x % 2 == 0 ? NSColor.white : NSColor.black).cgColor)
        context.fill(CGRect(x: x, y: 0, width: 1, height: 64))
    }
    let source = context.makeImage()!
    let canvas = AnnotationCanvasView(
        sourceImage: source,
        logicalSize: CGSize(width: 64, height: 64),
        contentInset: 0
    )
    canvas.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
    canvas.tool = .mosaic
    canvas.brushPixelWidth = 14

    let before = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    canvas.cacheDisplay(in: canvas.bounds, to: before)
    let originalPNG = before.representation(using: .png, properties: [:])!

    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 8, y: 32), timestamp: 1))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 56, y: 32), timestamp: 1.1))
    let during = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    canvas.cacheDisplay(in: canvas.bounds, to: during)
    let previewPNG = during.representation(using: .png, properties: [:])!

    #expect(canvas.strokes.isEmpty)
    #expect(previewPNG != originalPNG)
}

@Test("高亮选区重绘不透明冻结快照而不是挖透明洞")
@MainActor
func selectedRegionRendersOpaqueSnapshot() {
    let size = CGSize(width: 800, height: 600)
    let preview = NSImage(size: size, flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        return true
    }
    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: size))
    view.previewImage = preview

    view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), timestamp: 1))
    view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 700, y: 500), timestamp: 1.1))
    view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 700, y: 500), timestamp: 1.2))

    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let inside = bitmap.colorAt(x: 400, y: 300)!
    let outside = bitmap.colorAt(x: 20, y: 20)!
    let insideGray = inside.usingColorSpace(.deviceGray)!
    let outsideGray = outside.usingColorSpace(.deviceGray)!

    #expect(inside.alphaComponent == 1)
    #expect(outside.alphaComponent == 1)
    #expect(insideGray.whiteComponent > outsideGray.whiteComponent)
    #expect(outsideGray.whiteComponent < 0.65)
}

@Test("贴图拖动按全局鼠标位移更新窗口位置")
func pinnedImageDragGeometry() {
    let origin = PinWindowDragGeometry.origin(
        initialWindowOrigin: CGPoint(x: 100, y: 200),
        initialMouseLocation: CGPoint(x: 300, y: 400),
        currentMouseLocation: CGPoint(x: 345, y: 370)
    )
    #expect(origin == CGPoint(x: 145, y: 170))
}

@Test("贴图缩放围绕操作锚点并遵守最小尺寸")
func pinnedImageScaleGeometry() {
    let frame = CGRect(x: 100, y: 200, width: 400, height: 200)
    let anchor = CGPoint(x: 200, y: 250)

    let enlarged = PinWindowScaleGeometry.scaledFrame(
        frame,
        by: 1.5,
        around: anchor,
        minimumSize: CGSize(width: 80, height: 60)
    )
    #expect(enlarged == CGRect(x: 50, y: 175, width: 600, height: 300))

    let reduced = PinWindowScaleGeometry.scaledFrame(
        frame,
        by: 0.1,
        around: anchor,
        minimumSize: CGSize(width: 80, height: 60)
    )
    #expect(reduced == CGRect(x: 170, y: 235, width: 120, height: 60))
}

@Test("贴图描边和四角可命中缩放方向")
func pinnedImageResizeHandleHitTesting() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)

    #expect(PinWindowResizeGeometry.handle(at: CGPoint(x: 2, y: 198), in: bounds) == .topLeft)
    #expect(PinWindowResizeGeometry.handle(at: CGPoint(x: 200, y: 198), in: bounds) == .top)
    #expect(PinWindowResizeGeometry.handle(at: CGPoint(x: 398, y: 100), in: bounds) == .right)
    #expect(PinWindowResizeGeometry.handle(at: CGPoint(x: 200, y: 100), in: bounds) == nil)
}

@Test("鼠标靠近贴图边缘时展示八向缩放控制点")
func pinnedImageResizeChromeGeometry() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)

    #expect(PinWindowResizeChromeGeometry.isNearEdge(CGPoint(x: 20, y: 100), in: bounds))
    #expect(!PinWindowResizeChromeGeometry.isNearEdge(CGPoint(x: 200, y: 100), in: bounds))
    #expect(PinWindowResizeChromeGeometry.handleRect(for: .topLeft, in: bounds) == CGRect(x: 2, y: 190, width: 8, height: 8))
    #expect(PinWindowResizeChromeGeometry.handleRect(for: .right, in: bounds) == CGRect(x: 393, y: 93, width: 5, height: 14))
}

@Test("贴图描边拖拽围绕对边等比例缩放")
func pinnedImageBorderResizeGeometry() {
    let frame = CGRect(x: 100, y: 200, width: 400, height: 200)
    let minimumSize = CGSize(width: 80, height: 60)

    let fromRight = PinWindowResizeGeometry.resizedFrame(
        frame,
        using: .right,
        from: CGPoint(x: 500, y: 300),
        to: CGPoint(x: 700, y: 300),
        minimumSize: minimumSize
    )
    #expect(fromRight == CGRect(x: 100, y: 150, width: 600, height: 300))

    let fromTopRight = PinWindowResizeGeometry.resizedFrame(
        frame,
        using: .topRight,
        from: CGPoint(x: 500, y: 400),
        to: CGPoint(x: 700, y: 500),
        minimumSize: minimumSize
    )
    #expect(fromTopRight == CGRect(x: 100, y: 200, width: 600, height: 300))

    let clampedFromLeft = PinWindowResizeGeometry.resizedFrame(
        frame,
        using: .left,
        from: CGPoint(x: 100, y: 300),
        to: CGPoint(x: 600, y: 300),
        minimumSize: minimumSize
    )
    #expect(clampedFromLeft == CGRect(x: 380, y: 270, width: 120, height: 60))

    let unchangedFromInsetHitArea = PinWindowResizeGeometry.resizedFrame(
        frame,
        using: .right,
        from: CGPoint(x: 494, y: 300),
        to: CGPoint(x: 494, y: 300),
        minimumSize: minimumSize
    )
    #expect(unchangedFromInsetHitArea == frame)
}

@Test("贴图可一键恢复首次贴屏时的全部可变状态")
@MainActor
func pinnedImageRestoresInitialState() throws {
    _ = NSApplication.shared
    let controller = PinWindowController(
        id: UUID(),
        image: NSImage(size: CGSize(width: 320, height: 180)),
        hasShadow: true,
        onClose: { _ in }
    )
    controller.show(near: CGPoint(x: 300, y: 300))

    let window = try #require(controller.window)
    let initialFrame = window.frame
    controller.scale(by: 1.4)
    window.setFrameOrigin(CGPoint(x: initialFrame.minX + 40, y: initialFrame.minY + 30))
    controller.adjustOpacity(by: -0.4)
    controller.togglePositionLock()
    controller.toggleAllSpaces()
    controller.toggleAutoFadeOnHover()
    controller.toggleMousePassthrough()

    controller.restoreInitialState()

    #expect(window.frame == initialFrame)
    #expect(!window.ignoresMouseEvents)
    let restoredState = controller.workspaceCapture.state
    #expect(restoredState.opacity == 1)
    #expect(!restoredState.isPositionLocked)
    #expect(restoredState.appearsOnAllSpaces)
    #expect(restoredState.visibilityBundleIdentifier == nil)
    #expect(!restoredState.isAutoFadeOnHoverEnabled)
    #expect(window.alphaValue == 1)
    let imageView = try #require(window.contentView as? PinImageView)
    #expect(window is PinPanel)
    #expect(window.canBecomeKey)
    #expect(window.styleMask.contains(.nonactivatingPanel))
    #expect(window.acceptsMouseMovedEvents)
    let menuTitles = imageView.menu?.items.map(\.title) ?? []
    #expect(menuTitles.contains(L10n.text("pin.zoomIn")))
    #expect(menuTitles.contains(L10n.text("pin.zoomOut")))
    #expect(menuTitles.contains(L10n.text("pin.restoreInitialState")))
    #expect(menuTitles.contains(L10n.text("pinWorkspace.saveCurrent")))
    #expect(menuTitles.contains(L10n.text("pin.metadata.edit")))
    #expect(menuTitles.contains(L10n.text("pin.compare.needsTwoPins")))
    #expect(!menuTitles.contains("切换鼠标穿透"))
    #expect(!menuTitles.contains("Toggle Mouse Passthrough"))
    controller.close()
}

@Test("贴图备注、对比入口与会话变化回调保持独立")
@MainActor
func pinnedImageMetadataComparisonAndSessionCallbacks() throws {
    _ = NSApplication.shared
    let initialMetadata = try PinMetadata(note: "初稿", tags: ["UI"])
    var editedMetadata: PinMetadata?
    var requestedComparisonMode: PinComparisonMode?
    var stateChangeCount = 0
    let controller = PinWindowController(
        id: UUID(),
        image: solidImage(size: CGSize(width: 120, height: 80), color: .cyan),
        metadata: initialMetadata,
        hasShadow: true,
        onEditMetadata: { _, metadata in editedMetadata = metadata },
        comparisonState: { _ in .canCompare },
        onComparisonAction: { _, mode in requestedComparisonMode = mode },
        onStateChanged: { stateChangeCount += 1 },
        onClose: { _ in }
    )
    controller.show(near: CGPoint(x: 300, y: 300))

    controller.requestMetadataEdit()
    #expect(editedMetadata == initialMetadata)
    let updatedMetadata = try PinMetadata(note: "终稿", tags: ["Review", "完成"])
    controller.updateMetadata(updatedMetadata)
    #expect(controller.workspaceCapture.metadata == updatedMetadata)

    controller.requestComparison(mode: .blend)
    #expect(requestedComparisonMode == .blend)
    let imageView = try #require(controller.window?.contentView as? PinImageView)
    let menu = try #require(imageView.menu)
    let comparisonItem = try #require(
        menu.items.first { $0.title == L10n.text("pin.compare.withReference") }
    )
    let comparisonTitles = comparisonItem.submenu?.items.map(\.title) ?? []
    #expect(comparisonTitles == [
        L10n.text("pin.compare.sideBySide"),
        L10n.text("pin.compare.overlay"),
        L10n.text("pin.compare.blend")
    ])

    controller.adjustOpacity(by: -0.1)
    controller.togglePositionLock()
    #expect(stateChangeCount == 2)
    controller.toggleMousePassthrough()
    controller.restoreInteraction()
    #expect(stateChangeCount == 4)
    #expect(!controller.ignoresMouseEvents)
    #expect(controller.sessionCapture.id == controller.id)
    controller.close()
}

@Test("贴图工作区完整往返状态并使用私有文件权限")
@MainActor
func pinWorkspaceRoundTripsStateAndPermissions() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceTests-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: root) }
    let store = PinWorkspaceStore(fileManager: fileManager, rootDirectory: root)
    let state = PinWorkspaceWindowState(
        frame: CGRect(x: 120, y: 180, width: 480, height: 320),
        opacity: 0.65,
        ignoresMouseEvents: true,
        isPositionLocked: true,
        appearsOnAllSpaces: false,
        visibilityBundleIdentifier: "com.example.DesignApp",
        isAutoFadeOnHoverEnabled: true
    )

    let saved = try store.save(
        name: "  设计对稿  ",
        captures: [PinWorkspaceCapture(
            image: solidImage(size: CGSize(width: 48, height: 32), color: .systemPink),
            state: state
        )]
    )

    #expect(saved.name == "设计对稿")
    #expect(saved.pinCount == 1)
    #expect(store.workspaces == [saved])
    let loaded = try store.load(saved)
    #expect(loaded.entries.count == 1)
    #expect(loaded.skippedPinCount == 0)
    #expect(loaded.entries[0].state == state)
    #expect(loaded.entries[0].image.size == CGSize(width: 48, height: 32))

    let rootPermissions = try fileManager.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
    #expect(rootPermissions?.intValue == 0o700)
    let workspaceDirectory = try #require(
        fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first
    )
    let workspacePermissions = try fileManager.attributesOfItem(atPath: workspaceDirectory.path)[.posixPermissions] as? NSNumber
    #expect(workspacePermissions?.intValue == 0o700)
    let files = try fileManager.contentsOfDirectory(at: workspaceDirectory, includingPropertiesForKeys: nil)
    #expect(files.count == 2)
    for file in files {
        let permissions = try fileManager.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    try store.delete(saved)
    #expect(store.workspaces.isEmpty)
    #expect(!fileManager.fileExists(atPath: workspaceDirectory.path))
}

@Test("贴图工作区拒绝空名称和空贴图集合")
@MainActor
func pinWorkspaceValidatesSaveInput() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PinWorkspaceTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PinWorkspaceStore(rootDirectory: root)
    let state = PinWorkspaceWindowState(
        frame: CGRect(x: 0, y: 0, width: 100, height: 80),
        opacity: 1,
        ignoresMouseEvents: false,
        isPositionLocked: false,
        appearsOnAllSpaces: true,
        visibilityBundleIdentifier: nil,
        isAutoFadeOnHoverEnabled: false
    )
    let capture = PinWorkspaceCapture(
        image: solidImage(size: CGSize(width: 12, height: 8), color: .systemBlue),
        state: state
    )

    #expect(throws: PinWorkspaceStoreError.invalidName) {
        try store.save(name: "   ", captures: [capture])
    }
    #expect(throws: PinWorkspaceStoreError.noPins) {
        try store.save(name: "空工作区", captures: [])
    }
    #expect(store.workspaces.isEmpty)
}

@Test("贴图工作区缺少部分图片时恢复其余贴图")
@MainActor
func pinWorkspacePartiallyRestoresMissingImages() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceTests-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: root) }
    let store = PinWorkspaceStore(fileManager: fileManager, rootDirectory: root)
    let state = PinWorkspaceWindowState(
        frame: CGRect(x: 0, y: 0, width: 120, height: 80),
        opacity: 1,
        ignoresMouseEvents: false,
        isPositionLocked: false,
        appearsOnAllSpaces: true,
        visibilityBundleIdentifier: nil,
        isAutoFadeOnHoverEnabled: false
    )
    let workspace = try store.save(
        name: "部分恢复",
        captures: [
            PinWorkspaceCapture(image: solidImage(size: CGSize(width: 20, height: 10), color: .red), state: state),
            PinWorkspaceCapture(image: solidImage(size: CGSize(width: 24, height: 12), color: .blue), state: state)
        ]
    )
    let workspaceDirectory = try #require(
        fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first
    )
    let imageURL = try #require(
        fileManager.contentsOfDirectory(at: workspaceDirectory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "png" }
    )
    try fileManager.removeItem(at: imageURL)

    let loaded = try store.load(workspace)
    #expect(loaded.entries.count == 1)
    #expect(loaded.skippedPinCount == 1)
}

@Test("损坏工作区不会阻塞有效工作区载入")
@MainActor
func pinWorkspaceReportsCorruptDirectoriesWithoutBlockingValidOnes() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceTests-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: root) }
    let store = PinWorkspaceStore(fileManager: fileManager, rootDirectory: root)
    let state = PinWorkspaceWindowState(
        frame: CGRect(x: 0, y: 0, width: 80, height: 60),
        opacity: 1,
        ignoresMouseEvents: false,
        isPositionLocked: false,
        appearsOnAllSpaces: true,
        visibilityBundleIdentifier: nil,
        isAutoFadeOnHoverEnabled: false
    )
    let valid = try store.save(
        name: "有效工作区",
        captures: [PinWorkspaceCapture(
            image: solidImage(size: CGSize(width: 8, height: 6), color: .green),
            state: state
        )]
    )
    let corruptDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: corruptDirectory, withIntermediateDirectories: false)
    try Data("not-json".utf8).write(to: corruptDirectory.appendingPathComponent("manifest.json"))

    store.refresh()

    #expect(store.workspaces == [valid])
    #expect(store.loadWarningCount == 1)
    #expect(try store.load(valid).entries.count == 1)
}

@Test("恢复贴图工作区时回收离屏窗口并移除失效 App 限制")
@MainActor
func pinWorkspaceRestoreConstrainsFrameAndClearsUnavailableAppBinding() throws {
    _ = NSApplication.shared
    let controller = PinWindowController(
        id: UUID(),
        image: solidImage(size: CGSize(width: 320, height: 180), color: .purple),
        hasShadow: true,
        onClose: { _ in }
    )
    let requested = PinWorkspaceWindowState(
        frame: CGRect(x: 100_000, y: 100_000, width: 600, height: 400),
        opacity: 0.42,
        ignoresMouseEvents: true,
        isPositionLocked: true,
        appearsOnAllSpaces: false,
        visibilityBundleIdentifier: "com.example.PinboardShot.MissingApplication.\(UUID().uuidString)",
        isAutoFadeOnHoverEnabled: true
    )

    let clearedBinding = controller.show(restoring: requested)
    let restored = controller.workspaceCapture.state

    #expect(clearedBinding)
    #expect(restored.visibilityBundleIdentifier == nil)
    #expect(restored.opacity == 0.42)
    #expect(restored.ignoresMouseEvents)
    #expect(restored.isPositionLocked)
    #expect(!restored.appearsOnAllSpaces)
    #expect(restored.isAutoFadeOnHoverEnabled)
    #expect(controller.window?.alphaValue == 0.42)
    #expect(NSScreen.screens.contains { $0.visibleFrame.intersects(restored.frame) })
    controller.close()
}

@Test("贴图可见区域回收保持比例并选择最近屏幕")
func pinWorkspaceVisibleFrameRecovery() {
    let screens = [
        CGRect(x: 0, y: 0, width: 1_000, height: 800),
        CGRect(x: 1_000, y: 0, width: 800, height: 600)
    ]
    let recovered = PinWindowVisibleGeometry.constrainedFrame(
        CGRect(x: 4_000, y: 2_000, width: 1_600, height: 1_200),
        visibleFrames: screens
    )

    #expect(recovered == CGRect(x: 1_000, y: 0, width: 800, height: 600))
    #expect(abs(recovered.width / recovered.height - 4.0 / 3.0) < 0.000_001)
}

@Test("贴图窗口响应 Command-W 关闭当前贴图")
@MainActor
func pinPanelCommandWClosesCurrentPin() throws {
    _ = NSApplication.shared
    let id = UUID()
    var closedIDs: [UUID] = []
    let controller = PinWindowController(
        id: id,
        image: NSImage(size: CGSize(width: 320, height: 180)),
        hasShadow: true,
        onClose: { closedIDs.append($0) }
    )
    controller.show(near: CGPoint(x: 300, y: 300))

    let window = try #require(controller.window as? PinPanel)
    let event = keyEvent(
        keyCode: UInt16(kVK_ANSI_W),
        characters: "w",
        modifierFlags: .command
    )

    #expect(window.performKeyEquivalent(with: event))
    #expect(closedIDs == [id])
}

@Test("贴图保存根据扩展名选择图片格式")
func pinnedImageSaveFormatMappingAndEncoding() throws {
    #expect(PinImageSaveFormat.format(for: URL(fileURLWithPath: "/tmp/capture.png")) == .png)
    #expect(PinImageSaveFormat.format(for: URL(fileURLWithPath: "/tmp/capture.jpeg")) == .jpeg)
    #expect(PinImageSaveFormat.format(for: URL(fileURLWithPath: "/tmp/capture.tif")) == .tiff)
    #expect(PinImageSaveFormat.format(for: URL(fileURLWithPath: "/tmp/capture.heif")) == .heic)
    #expect(PinImageSaveFormat.format(for: URL(fileURLWithPath: "/tmp/capture.unknown")) == .png)
    #expect(PinImageSaveFormat.allowedContentTypes.contains(.png))
    #expect(PinImageSaveFormat.allowedContentTypes.contains(.jpeg))
    #expect(PinImageSaveFormat.allowedContentTypes.contains(.tiff))

    let image = solidImage(size: CGSize(width: 12, height: 8), color: .systemBlue)
    #expect(PinImageSaveFormat.png.encodedData(for: image)?.isEmpty == false)
    #expect(PinImageSaveFormat.jpeg.encodedData(for: image)?.isEmpty == false)
    #expect(PinImageSaveFormat.tiff.encodedData(for: image)?.isEmpty == false)
}

@Test("开机自启系统状态映射完整")
func launchAtLoginStatusMapping() {
    #expect(LaunchAtLoginState(status: .notRegistered) == .disabled)
    #expect(LaunchAtLoginState(status: .enabled) == .enabled)
    #expect(LaunchAtLoginState(status: .requiresApproval) == .requiresApproval)
    #expect(LaunchAtLoginState(status: .notFound) == .unavailable)
}

@Test("捕获层拒绝写入均匀深色空白帧")
func captureImageValidation() {
    let suiteName = "PinboardShotCaptureImageValidation.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let darkContext = CGContext(
        data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    darkContext.setFillColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
    darkContext.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    #expect(CaptureImageValidator.isUniformDark(darkContext.makeImage()!, defaults: defaults))

    let contentContext = CGContext(
        data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    contentContext.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    contentContext.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
    contentContext.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    contentContext.fill(CGRect(x: 8, y: 0, width: 8, height: 16))
    #expect(!CaptureImageValidator.isUniformDark(contentContext.makeImage()!, defaults: defaults))
}

@Test("用户可显式允许均匀深色截图")
func uniformDarkCaptureOverride() {
    let suiteName = "PinboardShotUniformDarkCaptureOverride.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let key = CaptureImageValidator.allowUniformDarkDefaultsKey
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let context = CGContext(
        data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))

    defaults.set(true, forKey: key)
    #expect(!CaptureImageValidator.isUniformDark(context.makeImage()!, defaults: defaults))
}

@Test("黑帧校验保留深色背景上的稀疏亮像素")
func captureImageValidationKeepsSparseContent() {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.setFillColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 8, y: 8, width: 1, height: 1))

    #expect(!CaptureImageValidator.isUniformDark(context.makeImage()!))
}

@Test("区域裁剪在发布前拒绝均匀深色成品")
func croppedRegionValidation() {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    let snapshot = ScreenSnapshot(
        image: context.makeImage()!,
        screenFrame: CGRect(x: 0, y: 0, width: 16, height: 16),
        pointSize: CGSize(width: 16, height: 16)
    )

    #expect(throws: PinboardShotError.self) {
        try snapshot.cropped(to: CGRect(x: 2, y: 2, width: 8, height: 8))
    }
}

@Test("标注历史支持撤销重做和清空")
func annotationHistoryOperations() {
    let stroke = AnnotationStroke(
        tool: .arrow,
        points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.8, y: 0.7)],
        color: AnnotationColor(.systemRed),
        width: 0.02
    )
    var history = AnnotationHistory()
    history.append(stroke)
    #expect(history.strokes == [stroke])
    #expect(history.canUndo)
    history.undo()
    #expect(history.strokes.isEmpty)
    #expect(history.canRedo)
    history.redo()
    #expect(history.strokes == [stroke])
    history.clear()
    #expect(history.strokes.isEmpty)
    #expect(history.canUndo)
    history.undo()
    #expect(history.strokes == [stroke])
    #expect(history.canRedo)
}

@Test("箭头端点几何保持对称")
func annotationArrowGeometry() {
    let head = AnnotationGeometry.arrowHead(
        from: CGPoint(x: 0, y: 0),
        to: CGPoint(x: 100, y: 0),
        length: 20
    )
    #expect(abs(head.0.x - head.1.x) < 0.001)
    #expect(abs(head.0.y + head.1.y) < 0.001)
    #expect(head.0.x < 100)
}

@Test("马赛克和画笔渲染保持原始像素尺寸")
func annotationRenderingPreservesPixels() throws {
    let context = CGContext(
        data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for x in stride(from: 0, to: 96, by: 4) {
        context.setFillColor((x / 4).isMultiple(of: 2) ? NSColor.white.cgColor : NSColor.black.cgColor)
        context.fill(CGRect(x: x, y: 0, width: 4, height: 64))
    }
    let source = context.makeImage()!
    let strokes = [
        AnnotationStroke(tool: .mosaic, points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)], color: AnnotationColor(.clear), width: 0.18),
        AnnotationStroke(tool: .pen, points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.9, y: 0.2)], color: AnnotationColor(.systemRed), width: 0.05)
    ]
    let rendered = try AnnotationRenderer.render(image: source, strokes: strokes)
    #expect(rendered.width == source.width)
    #expect(rendered.height == source.height)
    #expect(rendered.dataProvider?.data != source.dataProvider?.data)
}

@Test("区域截图在发布前应用内联标注笔迹")
@MainActor
func captureRegionNativeAppliesInlineAnnotations() throws {
    let context = CGContext(
        data: nil,
        width: 100,
        height: 100,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
    let snapshot = ScreenSnapshot(
        image: context.makeImage()!,
        screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        pointSize: CGSize(width: 100, height: 100)
    )
    let stroke = AnnotationStroke(
        tool: .pen,
        points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)],
        color: AnnotationColor(.systemRed),
        width: 0.12
    )

    let image = try ScreenCaptureService().captureRegionNative(
        snapshot.screenFrame,
        from: snapshot,
        annotations: [stroke]
    )
    var proposed = CGRect(origin: .zero, size: image.size)
    let rendered = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)!
    let sample = NSBitmapImageRep(cgImage: rendered).colorAt(x: 50, y: 50)!
        .usingColorSpace(.deviceRGB)!

    #expect(sample.redComponent > sample.greenComponent)
    #expect(sample.redComponent > sample.blueComponent)
}

@Test("语言设置支持系统、简中、繁中和英文")
func supportedLanguages() {
    #expect(Set(AppLanguage.allCases.map(\.rawValue)) == Set(["system", "zh-Hans", "zh-Hant", "en"]))
}

@Test("截图启动动画默认开启并可关闭")
func captureAnimationPreference() {
    let suiteName = "PinboardShotAnimationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    #expect(OverlaySafetyPolicy.shouldAnimate(defaults: defaults))
    defaults.set(false, forKey: OverlaySafetyPolicy.animationDefaultsKey)
    #expect(!OverlaySafetyPolicy.shouldAnimate(defaults: defaults))
}

@Test("贴图阴影默认开启并能同步到已存在贴图")
@MainActor
func pinShadowPreference() {
    let defaults = UserDefaults.standard
    let previous = defaults.object(forKey: PinWindowManager.shadowDefaultsKey)
    defer {
        if let previous { defaults.set(previous, forKey: PinWindowManager.shadowDefaultsKey) }
        else { defaults.removeObject(forKey: PinWindowManager.shadowDefaultsKey) }
    }
    defaults.removeObject(forKey: PinWindowManager.shadowDefaultsKey)
    let manager = PinWindowManager()
    #expect(manager.shadowsEnabled)
    manager.setShadowsEnabled(false)
    #expect(!manager.shadowsEnabled)
}

@Test("自动更新检查周期提供明确且稳定的时间间隔")
func updateCheckFrequencyIntervals() {
    #expect(UpdateCheckFrequency.hourly.interval == 3_600)
    #expect(UpdateCheckFrequency.everySixHours.interval == 21_600)
    #expect(UpdateCheckFrequency.everyTwelveHours.interval == 43_200)
    #expect(UpdateCheckFrequency.daily.interval == 86_400)
    #expect(UpdateCheckFrequency.everyThreeDays.interval == 259_200)
    #expect(UpdateCheckFrequency.weekly.interval == 604_800)
}

@Test("已有 Sparkle 周期会映射到最接近的可选项")
func updateCheckFrequencyMapping() {
    #expect(UpdateCheckFrequency.closest(to: 3_600) == .hourly)
    #expect(UpdateCheckFrequency.closest(to: 80_000) == .daily)
    #expect(UpdateCheckFrequency.closest(to: 500_000) == .weekly)
}

@Test("更新检查时间菜单文案在没有记录时给出稳定提示")
func updateLastCheckMenuDetailFallsBackWhenMissing() {
    #expect(UpdateLastCheckDisplay.menuDetail(for: nil) == "上次：未检查")
}

@Test("隐形水印默认关闭且配置只从显式字段读取")
func invisibleWatermarkSettingsDefaults() {
    let suiteName = "PinboardShotWatermarkSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(!InvisibleWatermarkSettings.current(defaults: defaults).enabled)
    defaults.set(true, forKey: InvisibleWatermarkSettings.enabledDefaultsKey)
    defaults.set("项目 A", forKey: InvisibleWatermarkSettings.projectDefaultsKey)
    let settings = InvisibleWatermarkSettings.current(defaults: defaults)
    #expect(settings.enabled)
    #expect(settings.project == "项目 A")
    #expect(settings.recipient.isEmpty)
}

@Test("截图发布后改用压缩 PNG 承载并保留逻辑尺寸")
@MainActor
func preparedCaptureUsesCompressedImageBacking() throws {
    let suiteName = "PinboardShotCompressedCaptureTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PinboardShotCompressedCaptureTests-\(UUID().uuidString)")
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
    let store = InvisibleWatermarkStore(
        directoryURL: directory,
        signingKeyData: Data(repeating: 7, count: 32)
    )
    let service = InvisibleWatermarkService(store: store, defaults: defaults)
    let source = solidImage(size: CGSize(width: 80, height: 48), color: .systemBlue)

    let capture = try service.prepareCapture(source)

    #expect(capture.image !== source)
    #expect(capture.image.size == source.size)
    #expect(capture.image.pixelDimensions?.width == 80)
    #expect(capture.image.pixelDimensions?.height == 48)
    #expect(!capture.pngData.isEmpty)
}

@Test("隐形水印可从 PNG 像素和缩放图片中恢复")
func invisibleWatermarkRoundTrip() throws {
    let id = UUID()
    let source = watermarkTestImage(width: 960, height: 600)
    let marked = try InvisibleWatermarkCodec.embed(id: id, in: source)
    #expect(try InvisibleWatermarkCodec.detect(in: marked) == id)

    let scaled = watermarkResizedImage(marked, width: 720, height: 450)
    #expect(try InvisibleWatermarkCodec.detect(in: scaled) == id)

    var rect = CGRect(origin: .zero, size: marked.size)
    let markedCG = marked.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    let bitmap = NSBitmapImageRep(cgImage: markedCG)
    let jpegData = try #require(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]))
    let jpeg = try #require(NSImage(data: jpegData))
    #expect(try InvisibleWatermarkCodec.detect(in: jpeg) == id)

    let croppedCG = try #require(markedCG.cropping(to: CGRect(x: 48, y: 30, width: 864, height: 540)))
    let cropped = NSImage(cgImage: croppedCG, size: CGSize(width: 864, height: 540))
    #expect(try InvisibleWatermarkCodec.detect(in: cropped) == id)
}

@Test("隐形水印记录使用本地密钥签名并检测篡改")
@MainActor
func invisibleWatermarkRecordSignature() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PinboardShotWatermarkStoreTests.\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = InvisibleWatermarkStore(
        directoryURL: directory,
        signingKeyData: Data(repeating: 0x5A, count: 32)
    )
    let settings = InvisibleWatermarkSettings(
        enabled: true,
        customText: "仅限评审",
        project: "项目 A",
        recipient: "评审组"
    )
    let record = try store.add(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        settings: settings,
        imageSHA256: String(repeating: "a", count: 64)
    )
    #expect(store.isAuthentic(record))

    let tampered = InvisibleWatermarkRecord(
        id: record.id,
        createdAt: record.createdAt,
        customText: "已修改",
        project: record.project,
        recipient: record.recipient,
        appVersion: record.appVersion,
        protocolVersion: record.protocolVersion,
        imageSHA256: record.imageSHA256,
        signature: record.signature
    )
    #expect(!store.isAuthentic(tampered))
}

private func watermarkTestImage(width: Int, height: Int) -> NSImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let colors = [NSColor.systemBlue.cgColor, NSColor.systemOrange.cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(
        gradient,
        start: .zero,
        end: CGPoint(x: width, y: height),
        options: []
    )
    return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
}

private func watermarkResizedImage(_ image: NSImage, width: Int, height: Int) -> NSImage {
    var rect = CGRect(origin: .zero, size: image.size)
    let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
}
