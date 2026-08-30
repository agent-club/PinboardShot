import AppKit
import SwiftUI

enum CompositionLayout: String, CaseIterable, Identifiable {
    case horizontal
    case vertical
    case grid
    var id: String { rawValue }
}

enum CompositionBackground: String, CaseIterable, Identifiable {
    case transparent
    case light
    case dark
    case blueGradient
    var id: String { rawValue }
}

struct CompositionOptions {
    var layout: CompositionLayout = .grid
    var background: CompositionBackground = .blueGradient
    var padding: CGFloat = 32
    var spacing: CGFloat = 18
    var cornerRadius: CGFloat = 14
    var showsShadow = true
    var title = ""
}

enum CompositionRenderer {
    static func render(images: [NSImage], options: CompositionOptions) -> NSImage? {
        guard !images.isEmpty else { return nil }
        let tileSizes = images.map { fittedSize($0.size, maximum: CGSize(width: 720, height: 520)) }
        let columns: Int
        switch options.layout {
        case .horizontal: columns = images.count
        case .vertical: columns = 1
        case .grid: columns = min(2, images.count)
        }
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let columnWidths = (0..<columns).map { column in
            stride(from: column, to: images.count, by: columns).map { tileSizes[$0].width }.max() ?? 0
        }
        let rowHeights = (0..<rows).map { row in
            let start = row * columns
            return (start..<min(start + columns, images.count)).map { tileSizes[$0].height }.max() ?? 0
        }
        let titleHeight: CGFloat = options.title.isEmpty ? 0 : 48
        let canvasSize = CGSize(
            width: options.padding * 2 + columnWidths.reduce(0, +) + options.spacing * CGFloat(max(0, columns - 1)),
            height: options.padding * 2 + titleHeight + rowHeights.reduce(0, +) + options.spacing * CGFloat(max(0, rows - 1))
        )
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let output = NSImage(size: canvasSize)
        output.lockFocus()
        defer { output.unlockFocus() }
        drawBackground(options.background, in: CGRect(origin: .zero, size: canvasSize))

        if !options.title.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: options.background == .dark ? NSColor.white : NSColor.labelColor
            ]
            options.title.draw(at: CGPoint(x: options.padding, y: canvasSize.height - options.padding - 30), withAttributes: attributes)
        }

        var y = canvasSize.height - options.padding - titleHeight
        for row in 0..<rows {
            y -= rowHeights[row]
            var x = options.padding
            for column in 0..<columns {
                let index = row * columns + column
                guard images.indices.contains(index) else { break }
                let size = tileSizes[index]
                let rect = CGRect(x: x, y: y + (rowHeights[row] - size.height) / 2, width: size.width, height: size.height)
                NSGraphicsContext.current?.saveGraphicsState()
                let path = NSBezierPath(roundedRect: rect, xRadius: options.cornerRadius, yRadius: options.cornerRadius)
                if options.showsShadow {
                    let shadow = NSShadow()
                    shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
                    shadow.shadowBlurRadius = 14
                    shadow.shadowOffset = CGSize(width: 0, height: -5)
                    shadow.set()
                    NSColor.white.setFill()
                    path.fill()
                }
                path.addClip()
                images[index].draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.current?.restoreGraphicsState()
                x += columnWidths[column] + options.spacing
            }
            y -= options.spacing
        }
        return output
    }

    private static func fittedSize(_ size: CGSize, maximum: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1, height: 1) }
        let scale = min(maximum.width / size.width, maximum.height / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func drawBackground(_ background: CompositionBackground, in rect: CGRect) {
        switch background {
        case .transparent:
            NSColor.clear.setFill(); rect.fill()
        case .light:
            NSColor(calibratedWhite: 0.96, alpha: 1).setFill(); rect.fill()
        case .dark:
            NSColor(calibratedWhite: 0.10, alpha: 1).setFill(); rect.fill()
        case .blueGradient:
            NSGradient(colors: [NSColor.systemBlue, NSColor.systemPurple])?.draw(in: rect, angle: -35)
        }
    }
}

@MainActor
final class CompositionStudioController {
    private var windowController: NSWindowController?

    func show(historyStore: HistoryStore, onPin: @escaping (NSImage) -> Void) {
        let view = CompositionStudioView(historyStore: historyStore, onPin: onPin)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("composition.title")
        window.minSize = CGSize(width: 760, height: 520)
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct CompositionStudioView: View {
    @ObservedObject var historyStore: HistoryStore
    let onPin: (NSImage) -> Void
    @State private var selectedIDs: Set<UUID> = []
    @State private var options = CompositionOptions()
    @State private var errorMessage: String?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("composition.chooseCaptures")).font(.headline)
                List(historyStore.items) { item in
                    Toggle(isOn: selectionBinding(for: item.id)) {
                        VStack(alignment: .leading) {
                            Text(item.createdAt, style: .time)
                            Text("\(item.pixelWidth) × \(item.pixelHeight)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(minWidth: 230)

            VStack(spacing: 12) {
                controls
                preview
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                actions
            }
            .padding(14)
            .frame(minWidth: 500)
        }
        .onAppear {
            selectedIDs = Set(historyStore.items.prefix(4).map(\.id))
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            TextField(L10n.text("composition.titlePlaceholder"), text: $options.title)
            HStack {
                Picker(L10n.text("composition.layout"), selection: $options.layout) {
                    ForEach(CompositionLayout.allCases) { layout in
                        Text(L10n.text("composition.layout.\(layout.rawValue)")).tag(layout)
                    }
                }
                Picker(L10n.text("composition.background"), selection: $options.background) {
                    ForEach(CompositionBackground.allCases) { background in
                        Text(L10n.text("composition.background.\(background.rawValue)")).tag(background)
                    }
                }
                Toggle(L10n.text("composition.shadow"), isOn: $options.showsShadow)
            }
            HStack {
                Text(L10n.text("composition.padding"))
                Slider(value: $options.padding, in: 0...80)
                Text(L10n.text("composition.cornerRadius"))
                Slider(value: $options.cornerRadius, in: 0...32)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = renderedImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.06))
        } else {
            ContentUnavailableView(L10n.text("composition.empty"), systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button(L10n.text("annotation.pin")) {
                guard let image = renderedImage else { return }
                onPin(image)
            }
            Button(L10n.text("pin.save")) {
                guard let image = renderedImage else { return }
                do { _ = try ImageFileExporter.save(image) }
                catch { errorMessage = error.localizedDescription }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var renderedImage: NSImage? {
        let images = historyStore.items
            .filter { selectedIDs.contains($0.id) }
            .compactMap { historyStore.image(for: $0) }
        return CompositionRenderer.render(images: images, options: options)
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { selected in
                if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
            }
        )
    }
}
