import AppKit
import SwiftUI

enum PinComparisonMode: String, CaseIterable, Hashable, Sendable {
    case sideBySide
    case overlay
    case blend

    fileprivate var titleKey: String {
        switch self {
        case .sideBySide: "comparison.mode.sideBySide"
        case .overlay: "comparison.mode.overlay"
        case .blend: "comparison.mode.blend"
        }
    }
}

enum PinComparisonRenderer {
    // A side-by-side pair of 8K inputs would otherwise allocate a 16K bitmap.
    // Keep exported results within one 8K-class pixel budget while preserving aspect ratios.
    static let maximumDimension = 8_192
    static let maximumPixelCount = 7_680 * 4_320

    static func render(
        first: NSImage,
        second: NSImage,
        mode: PinComparisonMode,
        isSwapped: Bool = false,
        blendOpacity: Double = 0.5
    ) -> NSImage? {
        guard let firstImage = cgImage(for: isSwapped ? second : first),
              let secondImage = cgImage(for: isSwapped ? first : second) else {
            return nil
        }

        let rawCanvasSize: CGSize
        switch mode {
        case .sideBySide:
            rawCanvasSize = CGSize(
                width: CGFloat(firstImage.width + secondImage.width),
                height: CGFloat(max(firstImage.height, secondImage.height))
            )
        case .overlay, .blend:
            rawCanvasSize = CGSize(
                width: CGFloat(max(firstImage.width, secondImage.width)),
                height: CGFloat(max(firstImage.height, secondImage.height))
            )
        }
        let canvasSize = constrainedCanvasSize(rawCanvasSize)
        guard canvasSize.width > 0, canvasSize.height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(canvasSize.width),
                height: Int(canvasSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        context.clear(canvasRect)
        switch mode {
        case .sideBySide:
            let scale = canvasSize.width / rawCanvasSize.width
            let firstSize = CGSize(
                width: CGFloat(firstImage.width) * scale,
                height: CGFloat(firstImage.height) * scale
            )
            let secondSize = CGSize(
                width: CGFloat(secondImage.width) * scale,
                height: CGFloat(secondImage.height) * scale
            )
            context.draw(
                firstImage,
                in: CGRect(
                    x: 0,
                    y: (canvasSize.height - firstSize.height) / 2,
                    width: firstSize.width,
                    height: firstSize.height
                )
            )
            context.draw(
                secondImage,
                in: CGRect(
                    x: firstSize.width,
                    y: (canvasSize.height - secondSize.height) / 2,
                    width: secondSize.width,
                    height: secondSize.height
                )
            )
        case .overlay:
            context.draw(firstImage, in: aspectFitRect(for: firstImage, in: canvasRect))
            context.saveGState()
            context.setBlendMode(.difference)
            context.draw(secondImage, in: aspectFitRect(for: secondImage, in: canvasRect))
            context.restoreGState()
        case .blend:
            context.draw(firstImage, in: aspectFitRect(for: firstImage, in: canvasRect))
            context.saveGState()
            context.setAlpha(CGFloat(min(max(blendOpacity, 0), 1)))
            context.draw(secondImage, in: aspectFitRect(for: secondImage, in: canvasRect))
            context.restoreGState()
        }

        guard let rendered = context.makeImage() else { return nil }
        return NSImage(cgImage: rendered, size: canvasSize)
    }

    private static func cgImage(for image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private static func constrainedCanvasSize(_ rawSize: CGSize) -> CGSize {
        guard rawSize.width > 0, rawSize.height > 0 else { return .zero }
        let dimensionScale = min(
            1,
            CGFloat(maximumDimension) / rawSize.width,
            CGFloat(maximumDimension) / rawSize.height
        )
        let pixelCount = rawSize.width * rawSize.height
        let pixelScale = pixelCount > CGFloat(maximumPixelCount)
            ? sqrt(CGFloat(maximumPixelCount) / pixelCount)
            : 1
        let scale = min(dimensionScale, pixelScale)
        return CGSize(
            width: max(1, floor(rawSize.width * scale)),
            height: max(1, floor(rawSize.height * scale))
        )
    }

    private static func aspectFitRect(for image: CGImage, in bounds: CGRect) -> CGRect {
        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

@MainActor
final class PinComparisonWindowController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?

    func show(
        first: NSImage,
        second: NSImage,
        initialMode: PinComparisonMode = .sideBySide
    ) {
        windowController?.close()

        let rootView = PinComparisonView(
            firstImage: first,
            secondImage: second,
            initialMode: initialMode
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1_000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("comparison.title")
        window.minSize = CGSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === windowController?.window else { return }
        windowController = nil
    }
}

private struct PinComparisonView: View {
    let firstImage: NSImage
    let secondImage: NSImage

    @State private var mode: PinComparisonMode
    @State private var isSwapped = false
    @State private var blendOpacity = 0.5
    @State private var isShowingExportError = false
    @State private var exportErrorMessage = ""

    init(firstImage: NSImage, secondImage: NSImage, initialMode: PinComparisonMode) {
        self.firstImage = firstImage
        self.secondImage = secondImage
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 12) {
            controls
            sizeHints
            comparisonCanvas
        }
        .padding(14)
        .frame(minWidth: 720, minHeight: 480)
        .alert(
            L10n.text("comparison.exportErrorTitle"),
            isPresented: $isShowingExportError
        ) {
            Button(L10n.text("common.close"), role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker(L10n.text("comparison.mode"), selection: $mode) {
                ForEach(PinComparisonMode.allCases, id: \.self) { candidate in
                    Text(L10n.text(candidate.titleKey)).tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .accessibilityLabel(L10n.text("comparison.mode"))

            Button {
                isSwapped.toggle()
            } label: {
                Label(L10n.text("comparison.swap"), systemImage: "arrow.left.arrow.right")
            }
            .accessibilityLabel(L10n.text("comparison.swap"))

            Spacer(minLength: 8)

            if mode == .blend {
                Text(L10n.text("comparison.opacity"))
                    .foregroundStyle(.secondary)
                Slider(value: $blendOpacity, in: 0...1)
                    .frame(width: 150)
                    .accessibilityLabel(L10n.text("comparison.opacity"))
                    .accessibilityValue(Text(blendPercentage))
                Text(blendPercentage)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }

            Button(action: exportComparison) {
                Label(L10n.text("comparison.export"), systemImage: "square.and.arrow.down")
            }
            .help(L10n.text("comparison.exportHelp"))
        }
    }

    private var sizeHints: some View {
        HStack(spacing: 16) {
            sizeHint(label: "A", image: displayedFirst)
            sizeHint(label: "B", image: displayedSecond)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var comparisonCanvas: some View {
        Group {
            switch mode {
            case .sideBySide:
                HStack(spacing: 0) {
                    imagePane(label: "A", image: displayedFirst)
                    Divider()
                    imagePane(label: "B", image: displayedSecond)
                }
            case .overlay:
                stackedImages(secondOpacity: 1, usesDifferenceBlend: true)
            case .blend:
                stackedImages(secondOpacity: blendOpacity, usesDifferenceBlend: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("comparison.canvas"))
    }

    private var displayedFirst: NSImage { isSwapped ? secondImage : firstImage }
    private var displayedSecond: NSImage { isSwapped ? firstImage : secondImage }
    private var blendPercentage: String { "\(Int((blendOpacity * 100).rounded()))%" }

    private func exportComparison() {
        guard let image = PinComparisonRenderer.render(
            first: firstImage,
            second: secondImage,
            mode: mode,
            isSwapped: isSwapped,
            blendOpacity: blendOpacity
        ) else {
            presentExportError(PinboardShotError.imageEncodingFailed.localizedDescription)
            return
        }

        do {
            _ = try ImageFileExporter.save(image, suggestedName: exportFilename())
        } catch {
            presentExportError(error.localizedDescription)
        }
    }

    private func presentExportError(_ detail: String) {
        exportErrorMessage = L10n.text("comparison.exportErrorMessage", detail)
        isShowingExportError = true
    }

    private func exportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "PinboardShot-Comparison-\(formatter.string(from: Date())).png"
    }

    private func sizeHint(label: String, image: NSImage) -> some View {
        Text("\(label) · \(pixelSizeDescription(for: image))")
            .accessibilityLabel(
                L10n.text(
                    "comparison.imageAccessibility",
                    label,
                    pixelWidth(for: image),
                    pixelHeight(for: image)
                )
            )
    }

    private func imagePane(label: String, image: NSImage) -> some View {
        ZStack(alignment: .topLeading) {
            comparisonImage(image, label: label)
                .padding(16)
            imageBadge(label)
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stackedImages(secondOpacity: Double, usesDifferenceBlend: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                comparisonImage(displayedFirst, label: "A")
                if usesDifferenceBlend {
                    comparisonImage(displayedSecond, label: "B")
                        .blendMode(.difference)
                } else {
                    comparisonImage(displayedSecond, label: "B")
                        .opacity(secondOpacity)
                }
            }
            .padding(16)
            .compositingGroup()

            HStack(spacing: 6) {
                imageBadge("A")
                imageBadge("B")
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func comparisonImage(_ image: NSImage, label: String) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(
                L10n.text(
                    "comparison.imageAccessibility",
                    label,
                    pixelWidth(for: image),
                    pixelHeight(for: image)
                )
            )
    }

    private func imageBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .accessibilityHidden(true)
    }

    private func pixelSizeDescription(for image: NSImage) -> String {
        "\(pixelWidth(for: image)) × \(pixelHeight(for: image)) px"
    }

    private func pixelWidth(for image: NSImage) -> Int {
        preferredRepresentation(for: image)?.pixelsWide ?? max(0, Int(image.size.width.rounded()))
    }

    private func pixelHeight(for image: NSImage) -> Int {
        preferredRepresentation(for: image)?.pixelsHigh ?? max(0, Int(image.size.height.rounded()))
    }

    private func preferredRepresentation(for image: NSImage) -> NSImageRep? {
        image.representations.max {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }
    }
}
