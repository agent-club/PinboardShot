import AppKit

final class AnchoredColorWell: NSColorWell {
    private static let fallbackPanelSize = CGSize(width: 260, height: 320)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func mouseDown(with event: NSEvent) {
        positionSharedColorPanel()
        super.mouseDown(with: event)
        positionSharedColorPanel()
    }

    override func activate(_ exclusive: Bool) {
        positionSharedColorPanel()
        super.activate(exclusive)
        positionSharedColorPanel()
    }

    private func positionSharedColorPanel() {
        guard let window else { return }
        let anchorRect = window.convertToScreen(convert(bounds, to: nil))
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchorRect
        let panel = NSColorPanel.shared
        let panelSize = CGSize(
            width: max(panel.frame.width, Self.fallbackPanelSize.width),
            height: max(panel.frame.height, Self.fallbackPanelSize.height)
        )
        panel.setFrameOrigin(Self.preferredPanelOrigin(
            for: panelSize,
            anchoredTo: anchorRect,
            in: visibleFrame
        ))
    }

    nonisolated static func preferredPanelOrigin(
        for panelSize: CGSize,
        anchoredTo anchorRect: CGRect,
        in visibleFrame: CGRect
    ) -> CGPoint {
        let panelSpacing: CGFloat = 8
        let panelWidth = min(panelSize.width, visibleFrame.width)
        let panelHeight = min(panelSize.height, visibleFrame.height)
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - panelWidth)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - panelHeight)
        let x = min(
            max(anchorRect.midX - panelWidth / 2, visibleFrame.minX),
            maxX
        )

        let belowY = anchorRect.minY - panelHeight - panelSpacing
        let aboveY = anchorRect.maxY + panelSpacing
        let y: CGFloat
        if belowY >= visibleFrame.minY {
            y = belowY
        } else if aboveY + panelHeight <= visibleFrame.maxY {
            y = aboveY
        } else {
            y = min(
                max(anchorRect.midY - panelHeight / 2, visibleFrame.minY),
                maxY
            )
        }

        return CGPoint(x: x, y: y)
    }
}
