import AppKit
import SwiftUI

enum QuickCaptureOverlaySettings {
    static let enabledDefaultsKey = "quickCaptureOverlayEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: enabledDefaultsKey) != nil else { return true }
        return defaults.bool(forKey: enabledDefaultsKey)
    }
}

@MainActor
enum ImageFileExporter {
    static func save(_ image: NSImage, suggestedName: String? = nil) throws -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = PinImageSaveFormat.allowedContentTypes
        panel.allowsOtherFileTypes = false
        panel.nameFieldStringValue = suggestedName ?? defaultFilename()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let format = PinImageSaveFormat.format(for: url)
        guard let data = format.encodedData(for: image) else {
            throw PinboardShotError.imageEncodingFailed
        }
        try data.write(to: url, options: .atomic)
        return true
    }

    private static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "PinboardShot-\(formatter.string(from: Date())).png"
    }
}

struct QuickCaptureOverlayActions {
    let copy: () -> Void
    let save: () -> Void
    let annotate: () -> Void
    let pin: () -> Void
    let dismiss: () -> Void
}

@MainActor
final class CaptureResultOverlayController {
    private var windowController: NSWindowController?
    private var dismissTask: Task<Void, Never>?

    func show(image: NSImage, actions: QuickCaptureOverlayActions) {
        dismiss()

        let view = QuickCaptureOverlayView(image: image, actions: actions)
        let hostingController = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 112),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentViewController = hostingController

        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            panel.setFrameOrigin(
                CGPoint(
                    x: visibleFrame.maxX - panel.frame.width - 20,
                    y: visibleFrame.minY + 20
                )
            )
        }

        let controller = NSWindowController(window: panel)
        windowController = controller
        panel.orderFrontRegardless()

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        windowController?.close()
        windowController = nil
    }
}

private struct QuickCaptureOverlayView: View {
    let image: NSImage
    let actions: QuickCaptureOverlayActions

    var body: some View {
        HStack(spacing: 12) {
            DraggableCaptureImage(image: image)
                .frame(width: 116, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .help(L10n.text("quickOverlay.dragHelp"))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.text("quickOverlay.title"))
                        .font(.headline)
                    Spacer()
                    Button(action: actions.dismiss) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("common.close"))
                }

                HStack(spacing: 7) {
                    overlayButton("doc.on.doc", "pin.copy", action: actions.copy)
                    overlayButton("square.and.arrow.down", "pin.save", action: actions.save)
                    overlayButton("pencil.tip.crop.circle", "quickOverlay.annotate", action: actions.annotate)
                    overlayButton("pin", "annotation.pin", action: actions.pin)
                }
            }
        }
        .padding(12)
        .frame(width: 360, height: 112)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private func overlayButton(_ symbol: String, _ titleKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.bordered)
        .help(L10n.text(titleKey))
        .accessibilityLabel(L10n.text(titleKey))
    }
}

private struct DraggableCaptureImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> CaptureDragImageView {
        let view = CaptureDragImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = image
        view.imageAlignment = .alignCenter
        view.setAccessibilityLabel(L10n.text("quickOverlay.preview"))
        return view
    }

    func updateNSView(_ nsView: CaptureDragImageView, context: Context) {
        nsView.image = image
    }
}

private final class CaptureDragImageView: NSImageView, NSDraggingSource {
    private var mouseDownPoint: CGPoint?

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let image, let mouseDownPoint else { return }
        let item = NSDraggingItem(pasteboardWriter: image)
        let size = CGSize(width: 96, height: 64)
        item.setDraggingFrame(
            CGRect(
                x: mouseDownPoint.x - size.width / 2,
                y: mouseDownPoint.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            contents: image
        )
        beginDraggingSession(with: [item], event: event, source: self)
        self.mouseDownPoint = nil
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
