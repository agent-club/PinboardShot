import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
@preconcurrency import ScreenCaptureKit

enum CaptureImageValidator {
    static let allowUniformDarkDefaultsKey = "allowUniformDarkCaptures"

    static func isUniformDark(_ image: CGImage, defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: allowUniformDarkDefaultsKey) { return false }
        // 低分辨率只做候选筛选；原图复核可避免把深色界面上的细文字平均掉。
        guard isUniformDarkSample(image) else { return false }
        return isUniformDarkAtNativeResolution(image)
    }

    private static func isUniformDarkSample(_ image: CGImage) -> Bool {
        let sampleWidth = 8
        let sampleHeight = 8
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: sampleWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }
        guard rendered else { return false }

        var minimum = UInt8.max
        var maximum = UInt8.min
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in index..<(index + 3) {
                minimum = min(minimum, pixels[channel])
                maximum = max(maximum, pixels[channel])
            }
        }
        return maximum <= 32 && Int(maximum) - Int(minimum) <= 3
    }

    private static func isUniformDarkAtNativeResolution(_ image: CGImage) -> Bool {
        guard let range = nativeLuminanceRange(image) else { return false }
        return range.maximum <= 32 && Int(range.maximum) - Int(range.minimum) <= 3
    }

    static func nativeLuminanceRange(_ image: CGImage) -> (minimum: UInt8, maximum: UInt8)? {
        let (pixelCount, overflow) = image.width.multipliedReportingOverflow(by: image.height)
        guard !overflow, pixelCount > 0, pixelCount <= 50_000_000 else { return nil }

        var pixels = [UInt8](repeating: 0, count: pixelCount)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else { return nil }

        var minimum = UInt8.max
        var maximum = UInt8.min
        for value in pixels {
            minimum = min(minimum, value)
            maximum = max(maximum, value)
        }
        return (minimum, maximum)
    }
}

enum CaptureResolution {
    static func pixelDimensions(
        for pointSize: CGSize,
        pointPixelScale: CGFloat
    ) -> (width: Int, height: Int) {
        let scale = pointPixelScale.isFinite && pointPixelScale > 0 ? pointPixelScale : 1
        return (
            max(1, Int((pointSize.width * scale).rounded(.up))),
            max(1, Int((pointSize.height * scale).rounded(.up)))
        )
    }
}

/// 将原生裁图等比适配到标准画布；目标档位低于源图时保持原始像素。
enum CaptureExportResolution {
    static func pixelDimensions(
        for sourcePixelSize: CGSize,
        quality: CaptureQuality
    ) -> (width: Int, height: Int) {
        let sourceWidth = max(1, sourcePixelSize.width)
        let sourceHeight = max(1, sourcePixelSize.height)
        guard let landscapeBounds = quality.landscapePixelBounds else {
            return (Int(sourceWidth.rounded()), Int(sourceHeight.rounded()))
        }

        let targetBounds = sourceHeight > sourceWidth
            ? CGSize(width: landscapeBounds.height, height: landscapeBounds.width)
            : landscapeBounds
        let targetScale = min(
            targetBounds.width / sourceWidth,
            targetBounds.height / sourceHeight
        )
        let scale = max(1, targetScale)
        return (
            max(1, Int((sourceWidth * scale).rounded())),
            max(1, Int((sourceHeight * scale).rounded()))
        )
    }
}

/// 只放大最终成品，并把单次生成上限收口到标准 8K 像素数。
enum CaptureImageScaler {
    static let maximumGeneratedPixelCount = 33_177_600

    static func canGenerate(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        return !overflow && pixelCount <= maximumGeneratedPixelCount
    }

    static func scaled(_ image: CGImage, quality: CaptureQuality) throws -> CGImage {
        let dimensions = CaptureExportResolution.pixelDimensions(
            for: CGSize(width: image.width, height: image.height),
            quality: quality
        )
        guard dimensions.width != image.width || dimensions.height != image.height else {
            return image
        }
        guard canGenerate(width: dimensions.width, height: dimensions.height) else {
            throw PinboardShotError.imageScalingFailed
        }

        let source = CIImage(cgImage: image)
        let scaleX = CGFloat(dimensions.width) / CGFloat(image.width)
        let scaleY = CGFloat(dimensions.height) / CGFloat(image.height)
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = source
        filter.scale = Float(scaleX)
        filter.aspectRatio = Float(scaleY / scaleX)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let output = filter.outputImage,
              let scaled = context.createCGImage(
                output,
                from: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
              ) else {
            throw PinboardShotError.imageScalingFailed
        }
        return scaled
    }
}

enum CaptureDiagnostics {
    private static let phaseKey = "captureDiagnostics.lastPhase"
    private static let errorKey = "captureDiagnostics.lastErrorType"
    private static let cropReportKey = "captureDiagnostics.lastRejectedCrop"

    static func begin(defaults: UserDefaults = .standard) {
        defaults.set("captureStarted", forKey: phaseKey)
        defaults.removeObject(forKey: errorKey)
        defaults.removeObject(forKey: cropReportKey)
    }

    static func recordPhase(_ phase: String, defaults: UserDefaults = .standard) {
        defaults.set(phase, forKey: phaseKey)
    }

    static func recordError(_ error: Error, defaults: UserDefaults = .standard) {
        defaults.set(String(reflecting: type(of: error)), forKey: errorKey)
    }

    static func report(defaults: UserDefaults = .standard) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let phase = defaults.string(forKey: phaseKey) ?? "none"
        let errorType = defaults.string(forKey: errorKey) ?? "none"
        let rejectedCropRecorded = defaults.dictionary(forKey: cropReportKey) != nil
        return [
            "PinboardShot \(version) (\(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Screen capture permission: \(CGPreflightScreenCaptureAccess() ? "granted" : "missing")",
            "Last capture phase: \(phase)",
            "Last error type: \(errorType)",
            "Rejected crop diagnostics: \(rejectedCropRecorded ? "available locally" : "none")",
            "No screenshot pixels, file paths, or user content are included."
        ].joined(separator: "\n")
    }

    static func recordRejectedCrop(
        snapshot: CGImage,
        screenFrame: CGRect,
        selection: CGRect,
        cropRect: CGRect,
        croppedImage: CGImage,
        defaults: UserDefaults = .standard
    ) {
        let bounds = CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
        let alternativeRect = CGRect(
            x: cropRect.minX,
            y: CGFloat(snapshot.height) - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height
        ).integral.intersection(bounds)
        let alternativeImage = snapshot.cropping(to: alternativeRect)

        var report: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "screenFrame": rectValues(screenFrame),
            "selection": rectValues(selection),
            "snapshotPixels": [snapshot.width, snapshot.height],
            "cropRect": rectValues(cropRect),
            "alternativeCropRect": rectValues(alternativeRect)
        ]
        report["snapshotRange"] = rangeValues(CaptureImageValidator.nativeLuminanceRange(snapshot))
        report["cropRange"] = rangeValues(CaptureImageValidator.nativeLuminanceRange(croppedImage))
        report["alternativeCropRange"] = rangeValues(
            alternativeImage.flatMap(CaptureImageValidator.nativeLuminanceRange)
        )
        defaults.set(report, forKey: cropReportKey)
        recordPhase("cropRejected", defaults: defaults)
    }

    private static func rectValues(_ rect: CGRect) -> [Double] {
        [rect.minX, rect.minY, rect.width, rect.height].map(Double.init)
    }

    private static func rangeValues(_ range: (minimum: UInt8, maximum: UInt8)?) -> [Int] {
        guard let range else { return [] }
        return [Int(range.minimum), Int(range.maximum)]
    }
}

struct ScreenSnapshot {
    let image: CGImage
    let screenFrame: CGRect
    let pointSize: CGSize

    func cropped(to selection: CGRect) throws -> CGImage {
        let cropRect = CaptureGeometry(screenFrame: screenFrame, selection: selection).pixelCropRect(
            for: CGSize(width: image.width, height: image.height)
        )
        guard !cropRect.isNull, cropRect.width > 0, cropRect.height > 0,
              let croppedImage = image.cropping(to: cropRect) else {
            throw PinboardShotError.invalidSelection
        }
        guard !CaptureImageValidator.isUniformDark(croppedImage) else {
            CaptureDiagnostics.recordRejectedCrop(
                snapshot: image,
                screenFrame: screenFrame,
                selection: selection,
                cropRect: cropRect,
                croppedImage: croppedImage
            )
            throw PinboardShotError.emptyCaptureFrame
        }
        return croppedImage
    }
}

@MainActor
struct PreparedRegionCapture {
    let snapshot: ScreenSnapshot
    let screen: NSScreen
}

struct ScrollCaptureGeometry: Equatable, Sendable {
    let screenFrame: CGRect
    let displayBounds: CGRect
    let selection: CGRect
    let windowFrame: CGRect

    var quartzSelectionRect: CGRect {
        CGRect(
            x: displayBounds.minX + selection.minX - screenFrame.minX,
            y: displayBounds.minY + screenFrame.maxY - selection.maxY,
            width: selection.width,
            height: selection.height
        )
    }

    var selectionInWindow: CGRect {
        let rect = quartzSelectionRect.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
        return rect.intersection(CGRect(origin: .zero, size: windowFrame.size))
    }
}

struct ScrollCaptureTarget: @unchecked Sendable {
    let window: SCWindow
    let cropRect: CGRect
    let pointPixelScale: CGFloat
    let selection: SelectedRegion

    var sourceApplicationBundleIdentifier: String? {
        window.owningApplication?.bundleIdentifier
    }
}

struct WindowCaptureResult {
    let image: NSImage
    let sourceApplicationBundleIdentifier: String?
}

@MainActor
final class ScreenCaptureService {
    private var hasConfirmedScreenCaptureAccess = false

    var hasScreenCaptureAccess: Bool {
        hasConfirmedScreenCaptureAccess || CGPreflightScreenCaptureAccess()
    }

    func requestPermissionIfNeeded() -> Bool {
        if hasScreenCaptureAccess { return true }
        let granted = CGRequestScreenCaptureAccess()
        hasConfirmedScreenCaptureAccess = granted
        return granted
    }

    func captureCurrentDisplay() async throws -> NSImage {
        let prepared = try await prepareRegionCapture()
        let outputImage = try await scaledForExport(prepared.snapshot.image)
        return NSImage(cgImage: outputImage, size: prepared.snapshot.pointSize)
    }

    func prepareRegionCapture() async throws -> PreparedRegionCapture {
        let content = try await shareableContent(
            excludingDesktopWindows: false,
            onScreenWindowsOnly: true
        )
        let (screen, display) = try currentScreenAndDisplay(in: content)
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let image = try await captureFullDisplay(display, filter: filter)
        guard !CaptureImageValidator.isUniformDark(image) else {
            CaptureDiagnostics.recordPhase("snapshotRejected")
            throw PinboardShotError.emptyCaptureFrame
        }
        return PreparedRegionCapture(
            snapshot: ScreenSnapshot(
                image: image,
                screenFrame: screen.frame,
                pointSize: screen.frame.size
            ),
            screen: screen
        )
    }

    func captureRegion(_ selection: CGRect, from snapshot: ScreenSnapshot) async throws -> NSImage {
        let nativeImage = try captureRegionNative(selection, from: snapshot)
        return try await scaleForExport(nativeImage)
    }

    func captureRegionNative(
        _ selection: CGRect,
        from snapshot: ScreenSnapshot,
        annotations: [AnnotationStroke] = []
    ) throws -> NSImage {
        let croppedImage = try snapshot.cropped(to: selection)
        // 笔迹先应用到原生裁图，随后才进入用户选择的输出清晰度缩放。
        let renderedImage = try AnnotationRenderer.render(image: croppedImage, strokes: annotations)
        return NSImage(cgImage: renderedImage, size: selection.size)
    }

    func scaleForExport(_ image: NSImage) async throws -> NSImage {
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw PinboardShotError.imageEncodingFailed
        }
        let outputImage = try await scaledForExport(cgImage)
        return NSImage(cgImage: outputImage, size: image.size)
    }

    func captureWindowUnderPointer() async throws -> WindowCaptureResult {
        let content = try await shareableContent(
            excludingDesktopWindows: true,
            onScreenWindowsOnly: true
        )
        let point = quartzMouseLocation()
        guard let window = content.windows.first(where: { candidate in
            candidate.isOnScreen && candidate.frame.contains(point) &&
            candidate.frame.width > 40 && candidate.frame.height > 40
        }) else {
            throw PinboardShotError.windowUnavailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let dimensions = CaptureResolution.pixelDimensions(
            for: window.frame.size,
            pointPixelScale: CGFloat(filter.pointPixelScale)
        )
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.showsCursor = false
        let image = try await withCaptureTimeout {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        let outputImage = try await scaledForExport(image)
        return WindowCaptureResult(
            image: NSImage(cgImage: outputImage, size: window.frame.size),
            sourceApplicationBundleIdentifier: window.owningApplication?.bundleIdentifier
        )
    }

    func scrollCaptureTarget(for selection: SelectedRegion) async throws -> ScrollCaptureTarget {
        let content = try await shareableContent(
            excludingDesktopWindows: true,
            onScreenWindowsOnly: true
        )
        guard let display = display(for: selection.screen, in: content.displays) else {
            throw PinboardShotError.displayUnavailable
        }
        let displayBounds = CGDisplayBounds(display.displayID)
        let quartzSelection = ScrollCaptureGeometry(
            screenFrame: selection.screen.frame,
            displayBounds: displayBounds,
            selection: selection.rect,
            windowFrame: .zero
        ).quartzSelectionRect
        let ownProcessID = pid_t(ProcessInfo.processInfo.processIdentifier)
        guard let window = content.windows.first(where: { candidate in
            candidate.isOnScreen &&
            candidate.owningApplication?.processID != ownProcessID &&
            candidate.frame.contains(CGPoint(x: quartzSelection.midX, y: quartzSelection.midY)) &&
            candidate.frame.width > 80 && candidate.frame.height > 80
        }) else {
            throw PinboardShotError.scrollTargetUnavailable
        }

        let geometry = ScrollCaptureGeometry(
            screenFrame: selection.screen.frame,
            displayBounds: displayBounds,
            selection: selection.rect,
            windowFrame: window.frame
        )
        let cropRect = geometry.selectionInWindow
        guard cropRect.width >= 40, cropRect.height >= 40 else {
            throw PinboardShotError.invalidSelection
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return ScrollCaptureTarget(
            window: window,
            cropRect: cropRect,
            pointPixelScale: CGFloat(filter.pointPixelScale),
            selection: selection
        )
    }

    private func shareableContent(
        excludingDesktopWindows: Bool,
        onScreenWindowsOnly: Bool
    ) async throws -> SCShareableContent {
        do {
            let content = try await withCaptureTimeout {
                try await SCShareableContent.excludingDesktopWindows(
                    excludingDesktopWindows,
                    onScreenWindowsOnly: onScreenWindowsOnly
                )
            }
            hasConfirmedScreenCaptureAccess = true
            return content
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                hasConfirmedScreenCaptureAccess = false
                throw PinboardShotError.permissionDenied
            }
            throw error
        }
    }

    private func currentScreenAndDisplay(in content: SCShareableContent) throws -> (NSScreen, SCDisplay) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
              let display = display(for: screen, in: content.displays) else {
            throw PinboardShotError.displayUnavailable
        }
        return (screen, display)
    }

    private func captureFullDisplay(_ display: SCDisplay, filter: SCContentFilter) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        let dimensions = CaptureResolution.pixelDimensions(
            for: CGSize(width: display.width, height: display.height),
            pointPixelScale: CGFloat(filter.pointPixelScale)
        )
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.showsCursor = UserDefaults.standard.bool(forKey: "captureCursor")
        return try await withCaptureTimeout {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
    }

    private func scaledForExport(_ image: CGImage) async throws -> CGImage {
        let quality = CaptureQuality.current()
        // 4K/8K 的 Lanczos 缩放离开 MainActor，避免阻塞菜单栏与窗口事件。
        return try await Task.detached(priority: .userInitiated) {
            try CaptureImageScaler.scaled(image, quality: quality)
        }.value
    }

    private func display(for screen: NSScreen, in displays: [SCDisplay]) -> SCDisplay? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return displays.first { $0.displayID == CGDirectDisplayID(number.uint32Value) }
    }

    private func quartzMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func withCaptureTimeout<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw PinboardShotError.captureTimedOut
            }
            guard let result = try await group.next() else {
                throw PinboardShotError.captureTimedOut
            }
            group.cancelAll()
            return result
        }
    }
}
