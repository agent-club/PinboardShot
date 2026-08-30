import AppKit
import SwiftUI

private enum PinComparisonDiscoveryTipConstants {
    static let width: CGFloat = 300
    static let maxWidth: CGFloat = 380
    static let cornerRadius: CGFloat = 10
    static let padding: CGFloat = 10
    static let animationDuration: TimeInterval = 0.2
    static let displayDuration: TimeInterval = 6
    static let horizontalOffset: CGFloat = 12
    static let verticalOffset: CGFloat = 10
}

@MainActor
final class PinComparisonDiscoveryTipController {
    private final class NonActivatingTipPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var windowController: NSWindowController?
    private var dismissTask: Task<Void, Never>?
    private var currentMessage: String?

    func show(near point: CGPoint, message: String) {
        show(near: point, message: message, includeCloseButton: true)
    }

    func show(near point: CGPoint, message: String, includeCloseButton: Bool) {
        show(point: point, message: message, includeCloseButton: includeCloseButton)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        currentMessage = nil
        windowController?.close()
        windowController = nil
    }

    private func show(point: CGPoint, message: String, includeCloseButton: Bool) {
        dismiss()

        currentMessage = message
        let size = estimateSize(for: message)
        let host = NonActivatingTipPanelHostView(
            message: message,
            onClose: { [weak self] in
                self?.dismiss()
            },
            showCloseButton: includeCloseButton,
            contentWidth: size.width
        )
        let hostingController = NSHostingController(rootView: host)
        let frame = frameForTip(near: point, preferredSize: size)
        let panel = NonActivatingTipPanel(
            contentRect: CGRect(origin: frame.origin, size: frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentViewController = hostingController

        let controller = NSWindowController(window: panel)
        windowController = controller
        panel.orderFrontRegardless()
        animateTipIn(panel)

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PinComparisonDiscoveryTipConstants.displayDuration))
            guard !Task.isCancelled else { return }
            guard let self, self.currentMessage == message else { return }
            self.dismiss()
        }
    }

    private func animateTipIn(_ panel: NSPanel) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
            return
        }

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PinComparisonDiscoveryTipConstants.animationDuration
            panel.animator().alphaValue = 1
        }
    }

    private func estimateSize(for message: String) -> CGSize {
        let maxWidth = PinComparisonDiscoveryTipConstants.maxWidth - (PinComparisonDiscoveryTipConstants.padding * 2)
        let font = NSFont.preferredFont(forTextStyle: .callout)
        let measured = message.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        let width = min(
            max(
                measured.width + (PinComparisonDiscoveryTipConstants.padding * 2) + 16,
                PinComparisonDiscoveryTipConstants.width
            ),
            PinComparisonDiscoveryTipConstants.maxWidth
        )
        let height = max(
            42,
            ceil(measured.height + (PinComparisonDiscoveryTipConstants.padding * 2) + 2)
        )

        return CGSize(width: width, height: height)
    }

    private func frameForTip(near point: CGPoint, preferredSize: CGSize) -> CGRect {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let preferredHeight = max(1, preferredSize.height)
        let preferredWidth = max(1, preferredSize.width)

        var frame = CGRect(
            x: point.x - preferredWidth / 2,
            y: point.y - preferredHeight - PinComparisonDiscoveryTipConstants.verticalOffset,
            width: preferredWidth,
            height: preferredHeight
        )

        guard let visibleFrame = screen?.visibleFrame else {
            return frame
        }

        if frame.minX < visibleFrame.minX + PinComparisonDiscoveryTipConstants.horizontalOffset {
            frame.origin.x = visibleFrame.minX + PinComparisonDiscoveryTipConstants.horizontalOffset
        }
        if frame.maxX > visibleFrame.maxX - PinComparisonDiscoveryTipConstants.horizontalOffset {
            frame.origin.x = visibleFrame.maxX - frame.width - PinComparisonDiscoveryTipConstants.horizontalOffset
        }

        if frame.minY < visibleFrame.minY + PinComparisonDiscoveryTipConstants.verticalOffset {
            frame.origin.y = point.y + PinComparisonDiscoveryTipConstants.verticalOffset
        }
        if frame.maxY > visibleFrame.maxY - PinComparisonDiscoveryTipConstants.verticalOffset {
            frame.origin.y = visibleFrame.maxY - frame.height - PinComparisonDiscoveryTipConstants.verticalOffset
        }

        return frame
    }
}

private struct NonActivatingTipPanelHostView: View {
    let message: String
    let onClose: () -> Void
    let showCloseButton: Bool
    let contentWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.callout)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if showCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PinComparisonDiscoveryTipConstants.padding)
        .frame(width: contentWidth, alignment: .leading)
        .frame(maxWidth: PinComparisonDiscoveryTipConstants.maxWidth, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: PinComparisonDiscoveryTipConstants.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: PinComparisonDiscoveryTipConstants.cornerRadius,
                style: .continuous
            )
            .stroke(.primary.opacity(0.12), lineWidth: 0.8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
