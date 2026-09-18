import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CaptureGuideModel: ObservableObject {
    @Published var guide = CaptureGuide(title: L10n.text("feature.guide.untitled")) {
        didSet { hasUnsavedChanges = true }
    }
    @Published var isCollecting = false
    @Published var hasUnsavedChanges = false
    @Published var selectedID: UUID?

    func append(_ image: NSImage) throws {
        guard guide.steps.count < 100 else { throw CaptureFeatureError.imageTooLarge }
        guard let data = image.pngData else { throw PinboardShotError.imageEncodingFailed }
        guard data.count <= 128 * 1_024 * 1_024,
              guide.steps.reduce(data.count, { $0 + $1.pngData.count }) <= 160 * 1_024 * 1_024 else {
            throw CaptureFeatureError.imageTooLarge
        }
        _ = try CaptureDocumentExport.decodeImage(data)
        let step = CaptureGuideStep(title: L10n.text("feature.guide.step", guide.steps.count + 1), pngData: data)
        guide.steps.append(step)
        selectedID = step.id
        hasUnsavedChanges = true
    }
}

@MainActor
final class CaptureToolsController: NSObject, NSWindowDelegate {
    let guide = CaptureGuideModel()
    private var window: NSWindow?
    private var hiddenForCapture = false
    var onCaptureStep: (() -> Void)?
    var onEdit: ((NSImage, Bool) -> Void)?
    var onRecord: (() -> Void)?
    var onUseImage: ((NSImage) -> Void)?

    func show(image: NSImage? = nil, guideSelected: Bool = false) {
        if let window, image == nil, !guideSelected {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        window?.close()
        let content = CaptureToolsView(image: image, guideModel: guide, initialTab: guideSelected ? 2 : 0,
            edit: { [weak self] in self?.onEdit?($0, $1) },
            capture: { [weak self] in self?.onCaptureStep?() },
            record: { [weak self] in self?.onRecord?() },
            useImage: { [weak self] in self?.onUseImage?($0) })
        let created = NSWindow(contentViewController: NSHostingController(rootView: content))
        created.title = L10n.text("feature.tools.title")
        created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        created.setContentSize(CGSize(width: 980, height: 700))
        created.minSize = CGSize(width: 840, height: 580)
        created.isReleasedWhenClosed = false
        created.delegate = self
        created.center()
        window = created
        created.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func suspendForCapture() {
        hiddenForCapture = window?.isVisible == true
        window?.orderOut(nil)
    }

    func resumeAfterCapture() {
        if hiddenForCapture { window?.makeKeyAndOrderFront(nil) }
        hiddenForCapture = false
    }

    func windowWillClose(_ notification: Notification) { guide.isCollecting = false }
}

private struct CaptureToolsView: View {
    @State private var image: NSImage?
    @State private var tab: Int
    @ObservedObject var guideModel: CaptureGuideModel
    let edit: (NSImage, Bool) -> Void
    let capture: () -> Void
    let record: () -> Void
    let useImage: (NSImage) -> Void
    @State private var message: String?

    init(image: NSImage?, guideModel: CaptureGuideModel, initialTab: Int,
         edit: @escaping (NSImage, Bool) -> Void, capture: @escaping () -> Void,
         record: @escaping () -> Void, useImage: @escaping (NSImage) -> Void) {
        _image = State(initialValue: image)
        _tab = State(initialValue: initialTab)
        self.guideModel = guideModel
        self.edit = edit
        self.capture = capture
        self.record = record
        self.useImage = useImage
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(L10n.text("feature.tools.open"), systemImage: "photo") { openImage() }
                Button(L10n.text("feature.tools.paste"), systemImage: "doc.on.clipboard") {
                    image = ImageClipboard().read()
                    if image == nil { message = L10n.text("error.clipboardHasNoImage") }
                }
                Spacer()
                Button(L10n.text("feature.draft.edit"), systemImage: "pencil.tip.crop.circle") { if let image { edit(image, false) } }.disabled(image == nil)
                Button(L10n.text("annotation.tool.ruler"), systemImage: "ruler") { if let image { edit(image, true) } }.disabled(image == nil)
                Button(L10n.text("feature.record.start"), systemImage: "record.circle") { record() }
            }
            Picker("", selection: $tab) {
                Text(L10n.text("feature.long.title")).tag(0)
                Text(L10n.text("feature.ocr.title")).tag(1)
                Text(L10n.text("feature.guide.title")).tag(2)
            }.pickerStyle(.segmented)
            ZStack {
                CaptureGuideView(model: guideModel, currentImage: image, capture: capture)
                    .opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2).disabled(tab != 2).accessibilityHidden(tab != 2)
                if let image, let source = image.cgImageValue {
                    LongImageView(image: source, useImage: useImage).id(ObjectIdentifier(image))
                        .opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0).disabled(tab != 0).accessibilityHidden(tab != 0)
                    StructuredOCRView(image: source, active: tab == 1).id(ObjectIdentifier(image))
                        .opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1).disabled(tab != 1).accessibilityHidden(tab != 1)
                } else if tab != 2 {
                    ContentUnavailableView(L10n.text("feature.tools.choose"), systemImage: "photo.on.rectangle",
                        description: Text(L10n.text("feature.tools.chooseHelp")))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(L10n.text("feature.error.title"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(L10n.text("common.done")) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let source = try CaptureDocumentExport.decodeImage(data)
                image = NSImage(cgImage: source, size: CGSize(width: source.width, height: source.height))
            } catch { message = error.localizedDescription }
        }
    }
}

private struct LongImageView: View {
    @State private var document: LongImageDocument
    @State private var preview: CGImage
    @State private var start = 0
    @State private var end = 0
    @State private var pageHeight = 1600
    @State private var message: String?
    let useImage: (NSImage) -> Void

    private var selectedRows: Range<Int> {
        let a = max(0, min(document.height, start))
        let b = max(0, min(document.height, end))
        return min(a, b)..<max(a, b)
    }

    init(image: CGImage, useImage: @escaping (NSImage) -> Void) {
        _document = State(initialValue: LongImageDocument(image: image))
        _preview = State(initialValue: image)
        self.useImage = useImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("feature.long.help")).foregroundStyle(.secondary)
            HStack {
                Text(L10n.text("feature.long.from"))
                TextField("", value: $start, format: .number).frame(width: 80)
                Text(L10n.text("feature.long.to"))
                TextField("", value: $end, format: .number).frame(width: 80)
                Text("px")
                Button(L10n.text("feature.long.remove"), role: .destructive) {
                    run {
                        if document.removeRows(from: start, to: end) { preview = try document.render(); start = 0; end = 0 }
                    }
                }.disabled(selectedRows.isEmpty || selectedRows.count >= document.height)
                Button { run { document.undo(); preview = try document.render(); start = 0; end = 0 } } label: { Image(systemName: "arrow.uturn.backward") }
                    .help(L10n.text("annotation.undo")).disabled(!document.canUndo)
                Button { run { document.redo(); preview = try document.render(); start = 0; end = 0 } } label: { Image(systemName: "arrow.uturn.forward") }
                    .help(L10n.text("annotation.redo")).disabled(!document.canRedo)
                Spacer()
                Text("\(preview.width) × \(preview.height) px").monospacedDigit()
            }
            GeometryReader { geometry in
                let width = min(geometry.size.width - 24, CGFloat(preview.width))
                let scale = width / CGFloat(preview.width)
                ScrollView {
                    Image(decorative: preview, scale: 1).resizable().interpolation(.high)
                        .frame(width: width, height: CGFloat(preview.height) * scale)
                        .overlay(alignment: .top) {
                            Rectangle().fill(.red.opacity(0.28))
                                .frame(height: CGFloat(selectedRows.count) * scale)
                                .offset(y: CGFloat(selectedRows.lowerBound) * scale)
                                .allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
                            start = max(0, min(document.height, Int(drag.startLocation.y / scale)))
                            end = max(0, min(document.height, Int(drag.location.y / scale)))
                        })
                        .padding(.horizontal, 8)
                }.background(Color(nsColor: .underPageBackgroundColor))
            }
            HStack {
                Text(L10n.text("feature.long.pageHeight"))
                TextField("", value: $pageHeight, format: .number).frame(width: 80)
                Text("px")
                Button(L10n.text("feature.long.exportPages")) { exportPages(pdf: false) }.disabled(pageHeight <= 0)
                Button(L10n.text("feature.export.pdf")) { exportPages(pdf: true) }.disabled(pageHeight <= 0)
                Spacer()
                Button(L10n.text("pin.save")) { run { _ = try ImageFileExporter.save(NSImage(cgImage: preview, size: CGSize(width: preview.width, height: preview.height))) } }
                Button(L10n.text("feature.long.use")) { useImage(NSImage(cgImage: preview, size: CGSize(width: preview.width, height: preview.height))) }
            }
            if let message { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
        }.textFieldStyle(.roundedBorder)
    }

    private func run(_ operation: () throws -> Void) {
        do { try operation(); message = nil } catch { message = error.localizedDescription }
    }

    private func exportPages(pdf: Bool) {
        run {
            if pdf {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.nameFieldStringValue = "PinboardShot-pages.pdf"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try CaptureDocumentExport.imagePDF(document.pages(pageHeight: pageHeight)).write(to: url, options: .atomic)
            } else {
                guard let parent = FeaturePanels.chooseDirectory() else { return }
                let pages = try document.pages(pageHeight: pageHeight)
                let url = try CaptureDocumentExport.directory(in: parent, name: "PinboardShot-pages") { folder in
                    for (index, image) in pages.enumerated() {
                        try CaptureDocumentExport.writePNG(image, to: folder.appendingPathComponent(String(format: "page-%03d.png", index + 1)))
                    }
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}

private struct StructuredOCRView: View {
    let image: CGImage
    let active: Bool
    @State private var format: StructuredOCRFormat = .plain
    @State private var drafts: [StructuredOCRFormat: String] = [:]
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(L10n.text("feature.ocr.format"), selection: $format) {
                    ForEach(StructuredOCRFormat.allCases) { Text($0.title).tag($0) }
                }.frame(width: 320)
                Button(L10n.text("feature.ocr.recognize")) { recognize() }.disabled(busy)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L10n.text("annotation.copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(drafts[format] ?? "", forType: .string)
                }.disabled((drafts[format] ?? "").isEmpty || busy)
            }
            Text(L10n.text("feature.ocr.help")).foregroundStyle(.secondary)
            HSplitView {
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().frame(width: 320)
                }.frame(minWidth: 200, idealWidth: 320, maxWidth: 420)
                TextEditor(text: Binding(get: { drafts[format] ?? "" }, set: { drafts[format] = $0 }))
                    .font(.system(.body, design: .monospaced)).padding(4)
            }
            if let message { Text(message).foregroundStyle(.secondary) }
        }.task(id: active) { if active && drafts.isEmpty && !busy { recognize() } }
    }

    private func recognize() {
        busy = true
        message = nil
        Task {
            do {
                let source = image
                let boxes = try await Task.detached(priority: .userInitiated) { try StructuredOCR.recognize(image: source) }.value
                for mode in StructuredOCRFormat.allCases { drafts[mode] = StructuredOCR.format(boxes, as: mode) }
                if boxes.isEmpty { message = L10n.text("feature.ocr.empty") }
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}

private struct CaptureGuideView: View {
    @ObservedObject var model: CaptureGuideModel
    let currentImage: NSImage?
    let capture: () -> Void
    @State private var message: String?
    @State private var discardAction: GuideReplacement?

    private enum GuideReplacement: String, Identifiable {
        case new, open
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.text("feature.guide.documentTitle"), text: $model.guide.title).font(.title2)
            Text(L10n.text("feature.guide.help")).foregroundStyle(.secondary)
            HStack {
                Toggle(L10n.text("feature.guide.collect"), isOn: $model.isCollecting).toggleStyle(.switch)
                Button(L10n.text("feature.guide.capture")) { model.isCollecting = true; capture() }
                Button(L10n.text("feature.guide.addCurrent")) { if let currentImage { run { try model.append(currentImage) } } }.disabled(currentImage == nil || model.guide.steps.count >= 100)
                Spacer()
                Text(L10n.text("feature.guide.count", model.guide.steps.count))
            }
            HSplitView {
                List(selection: $model.selectedID) {
                    ForEach(Array(model.guide.steps.enumerated()), id: \.element.id) { index, step in
                        HStack {
                            if let image = NSImage(data: step.pngData) { Image(nsImage: image).resizable().scaledToFit().frame(width: 56, height: 40) }
                            Text("\(index + 1). \(step.title)").lineLimit(2)
                        }.tag(step.id)
                    }
                }.frame(minWidth: 200, idealWidth: 250, maxWidth: 320)
                if let index = model.guide.steps.firstIndex(where: { $0.id == model.selectedID }) {
                    VStack(alignment: .leading) {
                        TextField(L10n.text("feature.guide.stepTitle"), text: $model.guide.steps[index].title)
                        TextEditor(text: $model.guide.steps[index].detail).frame(minHeight: 80, idealHeight: 110, maxHeight: 160)
                        if let image = NSImage(data: model.guide.steps[index].pngData) {
                            ScrollView { Image(nsImage: image).resizable().scaledToFit() }
                        }
                        HStack {
                            Button(L10n.text("feature.guide.up")) { model.guide.move(id: model.guide.steps[index].id, by: -1) }.disabled(index == 0)
                            Button(L10n.text("feature.guide.down")) { model.guide.move(id: model.guide.steps[index].id, by: 1) }.disabled(index == model.guide.steps.count - 1)
                            Spacer()
                            Button(L10n.text("feature.guide.remove"), role: .destructive) {
                                model.guide.steps.remove(at: index)
                                model.selectedID = model.guide.steps.first?.id
                            }
                        }
                    }.padding(8)
                } else {
                    ContentUnavailableView(L10n.text("feature.guide.empty"), systemImage: "list.number")
                }
            }
            HStack {
                Button(L10n.text("feature.guide.new")) { replace(.new) }
                Button(L10n.text("feature.guide.open")) { replace(.open) }
                Button(L10n.text("feature.guide.save")) { save() }
                if model.hasUnsavedChanges { Text(L10n.text("feature.guide.unsaved")).foregroundStyle(.secondary) }
                Spacer()
                Button(L10n.text("feature.export.markdown")) { export(pdf: false) }.disabled(model.guide.steps.isEmpty)
                Button(L10n.text("feature.export.pdf")) { export(pdf: true) }.disabled(model.guide.steps.isEmpty)
            }
            if let message { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .textFieldStyle(.roundedBorder)
        .alert(item: $discardAction) { action in
            Alert(title: Text(L10n.text("feature.guide.discardTitle")), message: Text(L10n.text("feature.guide.discardHelp")), primaryButton: .destructive(Text(L10n.text("feature.guide.discard"))) { performReplacement(action) }, secondaryButton: .cancel())
        }
    }

    private func run(_ operation: () throws -> Void) {
        do { try operation(); message = nil } catch { message = error.localizedDescription }
    }

    private func replace(_ action: GuideReplacement) {
        if model.hasUnsavedChanges { discardAction = action } else { performReplacement(action) }
    }

    private func performReplacement(_ action: GuideReplacement) {
        if action == .new {
            model.guide = CaptureGuide(title: L10n.text("feature.guide.untitled"))
            model.selectedID = nil
            model.isCollecting = false
            model.hasUnsavedChanges = false
        } else {
            run {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.json]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 256 * 1_024 * 1_024 else { throw CaptureFeatureError.imageTooLarge }
                let guide = try JSONDecoder().decode(CaptureGuide.self, from: Data(contentsOf: url))
                try guide.validate()
                model.guide = guide
                model.selectedID = guide.steps.first?.id
                model.isCollecting = false
                model.hasUnsavedChanges = false
            }
        }
    }

    private func save() {
        run {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "PinboardShot-guide.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try model.guide.validate()
            try JSONEncoder().encode(model.guide).write(to: url, options: .atomic)
            model.hasUnsavedChanges = false
        }
    }

    private func export(pdf: Bool) {
        run {
            try model.guide.validate()
            if pdf {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.nameFieldStringValue = "PinboardShot-guide.pdf"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try CaptureDocumentExport.guidePDF(model.guide).write(to: url, options: .atomic)
            } else {
                guard let parent = FeaturePanels.chooseDirectory() else { return }
                let url = try CaptureDocumentExport.directory(in: parent, name: "PinboardShot-guide") { folder in
                    let images = folder.appendingPathComponent("images", isDirectory: true)
                    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: false)
                    for (index, step) in model.guide.steps.enumerated() {
                        try step.pngData.write(to: images.appendingPathComponent(String(format: "step-%03d.png", index + 1)), options: .atomic)
                    }
                    try model.guide.markdown().write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}

@MainActor
enum FeaturePanels {
    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.text("feature.export.chooseFolder")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
