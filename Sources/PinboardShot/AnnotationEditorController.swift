import AppKit

struct AnnotationEditResult: @unchecked Sendable {
    let image: NSImage
    let disposition: SelectionDisposition
}

@MainActor
final class AnnotationEditorController: NSObject, NSWindowDelegate {
    private var continuation: CheckedContinuation<AnnotationEditResult?, Never>?
    private var windowController: NSWindowController?
    private var canvas: AnnotationCanvasView?
    private weak var undoButton: NSButton?
    private weak var redoButton: NSButton?
    private weak var widthSlider: NSSlider?
    private var selectedTool: AnnotationTool = .mosaic

    func edit(image: NSImage) async -> AnnotationEditResult? {
        guard continuation == nil, let source = image.cgImageValue else { return nil }
        let window = makeWindow(source: source, logicalSize: image.size)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            windowController = NSWindowController(window: window)
            windowController?.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow(source: CGImage, logicalSize: CGSize) -> NSWindow {
        selectedTool = .mosaic
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("annotation.title")
        window.minSize = CGSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self

        let root = NSView(frame: window.contentLayoutRect)
        root.autoresizingMask = [.width, .height]
        let canvas = AnnotationCanvasView(sourceImage: source, logicalSize: logicalSize)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.onHistoryChanged = { [weak self] canUndo, canRedo in
            self?.undoButton?.isEnabled = canUndo
            self?.redoButton?.isEnabled = canRedo
        }
        self.canvas = canvas

        let tools = NSSegmentedControl(labels: AnnotationTool.editorTools.map { L10n.text($0.titleKey) }, trackingMode: .selectOne, target: self, action: #selector(toolChanged(_:)))
        tools.selectedSegment = 0
        tools.controlSize = .small
        for (index, tool) in AnnotationTool.editorTools.enumerated() {
            tools.setImage(NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: L10n.text(tool.titleKey)), forSegment: index)
            tools.setLabel("", forSegment: index)
            tools.setToolTip(L10n.text(tool.titleKey), forSegment: index)
            tools.setWidth(38, forSegment: index)
        }

        let colorWell = AnchoredColorWell()
        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.toolTip = L10n.text("annotation.color")

        let widthSlider = NSSlider(
            value: Double(AnnotationStyleSettings.brushPixelWidth(for: selectedTool)),
            minValue: Double(AnnotationStyleSettings.minimumBrushPixelWidth),
            maxValue: Double(AnnotationStyleSettings.maximumBrushPixelWidth),
            target: self,
            action: #selector(widthChanged(_:))
        )
        widthSlider.frame.size.width = 110
        widthSlider.toolTip = L10n.text("annotation.width")
        self.widthSlider = widthSlider

        let undo = button(titleKey: "annotation.undo", symbol: "arrow.uturn.backward", action: #selector(undo))
        let redo = button(titleKey: "annotation.redo", symbol: "arrow.uturn.forward", action: #selector(redo))
        let clear = button(titleKey: "annotation.clear", symbol: "trash", action: #selector(clear))
        let crop = button(titleKey: "annotation.crop", symbol: "crop", action: #selector(cropToRectangle))
        let rotate = button(titleKey: "annotation.rotate", symbol: "rotate.right", action: #selector(rotateClockwise))
        let smartRedact = button(titleKey: "annotation.smartRedact", symbol: "eye.slash", action: #selector(smartRedact))
        undo.isEnabled = false
        redo.isEnabled = false
        undoButton = undo
        redoButton = redo

        let topBar = NSStackView(views: [tools, separator(), colorWell, widthSlider, separator(), undo, redo, clear, crop, rotate, smartRedact])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 10
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: L10n.text("common.cancel"), target: self, action: #selector(cancel))
        let copy = NSButton(title: L10n.text("annotation.copy"), target: self, action: #selector(copyResult))
        let pin = NSButton(title: L10n.text("annotation.pin"), target: self, action: #selector(pinResult))
        copy.keyEquivalent = "\r"
        pin.bezelStyle = .rounded
        let bottomBar = NSStackView(views: [NSView(), cancel, copy, pin])
        bottomBar.orientation = .horizontal
        bottomBar.alignment = .centerY
        bottomBar.spacing = 10
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(topBar)
        root.addSubview(canvas)
        root.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            topBar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            topBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            topBar.heightAnchor.constraint(equalToConstant: 34),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            canvas.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            canvas.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -10),
            bottomBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            bottomBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            bottomBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            bottomBar.heightAnchor.constraint(equalToConstant: 34)
        ])
        window.contentView = root
        window.center()
        widthChanged(widthSlider)
        return window
    }

    private func button(titleKey: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: L10n.text(titleKey))!, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.toolTip = L10n.text(titleKey)
        return button
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.frame.size = CGSize(width: 1, height: 24)
        return box
    }

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        guard AnnotationTool.editorTools.indices.contains(sender.selectedSegment) else { return }
        selectedTool = AnnotationTool.editorTools[sender.selectedSegment]
        let width = AnnotationStyleSettings.brushPixelWidth(for: selectedTool)
        widthSlider?.doubleValue = Double(width)
        canvas?.tool = selectedTool
        canvas?.brushPixelWidth = width
    }

    @objc private func colorChanged(_ sender: NSColorWell) { canvas?.annotationColor = sender.color }
    @objc private func widthChanged(_ sender: NSSlider) {
        let width = CGFloat(sender.doubleValue)
        AnnotationStyleSettings.setBrushPixelWidth(width, for: selectedTool)
        canvas?.brushPixelWidth = AnnotationStyleSettings.clampedBrushPixelWidth(width)
    }
    @objc private func undo() { canvas?.undo() }
    @objc private func redo() { canvas?.redo() }
    @objc private func clear() { canvas?.clear() }
    @objc private func cropToRectangle() {
        guard canvas?.cropToSelectedRectangle() == true else { NSSound.beep(); return }
    }
    @objc private func rotateClockwise() { canvas?.rotateClockwise() }
    @objc private func smartRedact() {
        guard let source = canvas?.sourceImageForAnalysis else { return }
        let boxed = AnnotationAnalysisSource(image: source)
        Task { @MainActor [weak self] in
            let regions = await Task.detached(priority: .userInitiated) {
                (try? TextRecognitionService.sensitiveRegions(in: boxed.image)) ?? []
            }.value
            guard let self else { return }
            if regions.isEmpty {
                let alert = NSAlert()
                alert.messageText = L10n.text("annotation.smartRedactNone")
                alert.runModal()
            } else {
                self.canvas?.addRedactionRegions(regions)
            }
        }
    }
    @objc private func cancel() { finish(nil) }
    @objc private func copyResult() { finishResult(disposition: .copy) }
    @objc private func pinResult() { finishResult(disposition: .pin) }

    private func finishResult(disposition: SelectionDisposition) {
        guard let image = canvas?.renderedImage() else { return }
        finish(AnnotationEditResult(image: image, disposition: disposition))
    }

    private func finish(_ result: AnnotationEditResult?, closeWindow: Bool = true) {
        guard let continuation else { return }
        self.continuation = nil
        windowController?.window?.delegate = nil
        if closeWindow { windowController?.close() }
        windowController = nil
        canvas = nil
        continuation.resume(returning: result)
    }

    func windowWillClose(_ notification: Notification) { finish(nil, closeWindow: false) }
}

final class AnnotationTextField: NSTextField {
    static let backgroundAlpha: CGFloat = 0.74
    static let cornerRadius: CGFloat = 7
    var onEmptyDoubleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        // 关闭 AppKit 原生亮色 bezel，由截图工具自己的暗色表面承载输入状态。
        isBezeled = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.backgroundAlpha).cgColor
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.masksToBounds = true
        cell?.usesSingleLineMode = true
        cell?.lineBreakMode = .byTruncatingTail
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2, stringValue.isEmpty {
            onEmptyDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }
}

private struct OCRSourceImage: @unchecked Sendable {
    let image: CGImage
}

private struct AnnotationAnalysisSource: @unchecked Sendable {
    let image: CGImage
}

final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    var tool: AnnotationTool = .mosaic {
        didSet {
            guard tool != oldValue else { return }
            if oldValue == .text { commitPendingText() }
            finishRectangleDrag(commit: false)
            selectedRectangleIndex = nil
            if tool != .text {
                finishTextDrag(commit: false)
                selectText(at: nil)
            }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    var annotationColor: NSColor = .systemRed {
        didSet { applyCurrentStyleToSelectedText() }
    }
    var brushPixelWidth: CGFloat = AnnotationStyleSettings.defaultBrushPixelWidth(for: .mosaic) {
        didSet { applyCurrentStyleToSelectedText() }
    }
    var onHistoryChanged: ((Bool, Bool) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onSelectedTextStyleChanged: ((NSColor, CGFloat) -> Void)?
    var strokes: [AnnotationStroke] { history.strokes }
    var currentRenderedImage: NSImage { cachedImage }
    var sourceImageForAnalysis: CGImage { sourceImage }

    private var sourceImage: CGImage
    private var logicalSize: CGSize
    private let contentInset: CGFloat
    private var history = AnnotationHistory()
    private var currentStroke: AnnotationStroke?
    private var cachedImage: NSImage
    // 预先缓存像素化底图，拖动时只裁切当前笔迹区域，避免每帧重算整张 Retina 图。
    private var pixelatedPreviewImage: NSImage?
    private var doubleClickTracker = SelectionDoubleClickTracker()
    private var lastCommittedStrokeWasTap = false
    // 输入框只承载临时编辑；索引区分新增与替换，选中索引负责画布反馈和工具栏样式回填。
    private weak var activeTextField: NSTextField?
    private var activeTextAnchor: CGPoint?
    private var activeTextIndex: Int?
    private var selectedTextIndex: Int?
    // 拖动期间只移动轻量预览，松手后才替换历史中的文字，避免每一帧都产生撤销记录。
    private var textDragIndex: Int?
    private var textDragStartPoint: CGPoint?
    private var textDragOriginalStroke: AnnotationStroke?
    private var textDragPreviewStroke: AnnotationStroke?
    private var textDragDidMove = false
    // 矩形拖动沿用文字的“预览后一次提交”语义，避免拖动每一帧都进入撤销栈。
    private var selectedRectangleIndex: Int?
    private var rectangleDragIndex: Int?
    private var rectangleDragStartPoint: CGPoint?
    private var rectangleDragOriginalStroke: AnnotationStroke?
    private var rectangleDragPreviewStroke: AnnotationStroke?
    private var rectangleDragDidMove = false
    // 从已选文字回填颜色和字号时禁止反向写历史，避免一次选中被误记为一次编辑。
    private var isSynchronizingTextStyle = false

    init(sourceImage: CGImage, logicalSize: CGSize, contentInset: CGFloat = 10) {
        self.sourceImage = sourceImage
        self.logicalSize = logicalSize
        self.contentInset = contentInset
        cachedImage = NSImage(cgImage: sourceImage, size: logicalSize)
        pixelatedPreviewImage = AnnotationRenderer.makePixelated(sourceImage).map {
            NSImage(cgImage: $0, size: logicalSize)
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = imageRect
        cachedImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        if let currentStroke { drawPreview(currentStroke, in: rect) }
        if let textDragPreviewStroke {
            drawTextPreview(textDragPreviewStroke, in: rect)
            drawTextSelection(for: textDragPreviewStroke, in: rect)
        } else if activeTextField == nil,
           let selectedTextIndex,
           history.strokes.indices.contains(selectedTextIndex) {
            drawTextSelection(for: history.strokes[selectedTextIndex], in: rect)
        }
        if let rectangleDragPreviewStroke {
            drawPreview(rectangleDragPreviewStroke, in: rect)
            drawRectangleSelection(for: rectangleDragPreviewStroke, in: rect)
        } else if let selectedRectangleIndex,
                  history.strokes.indices.contains(selectedRectangleIndex) {
            drawRectangleSelection(for: history.strokes[selectedRectangleIndex], in: rect)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if tool == .text, activeTextField == nil {
            for stroke in history.strokes where stroke.tool == .text {
                addCursorRect(textBounds(for: stroke, in: imageRect).insetBy(dx: -6, dy: -6), cursor: .openHand)
            }
        } else if tool == .rectangle {
            for stroke in history.strokes where stroke.tool == .rectangle {
                addCursorRect(rectangleBounds(for: stroke, in: imageRect).insetBy(dx: -6, dy: -6), cursor: .openHand)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        if tool == .text {
            commitPendingText()
            if let index = textStrokeIndex(at: point) {
                selectText(at: index)
                if event.clickCount >= 2 {
                    beginTextEntry(at: point, editing: index)
                } else {
                    beginTextDrag(at: point, index: index)
                }
            } else if event.clickCount >= 2 {
                selectText(at: nil)
                onDoubleClick?()
            } else {
                selectText(at: nil)
                beginTextEntry(at: point, editing: nil)
            }
            return
        }
        if event.clickCount >= 2 ||
            doubleClickTracker.registerClick(timestamp: event.timestamp, point: point) {
            // 双击第一下形成的点笔迹不应污染最终截图。
            currentStroke = nil
            if lastCommittedStrokeWasTap {
                history.undo()
                lastCommittedStrokeWasTap = false
                rebuildCache()
            }
            onDoubleClick?()
            return
        }
        if tool == .rectangle, let index = rectangleStrokeIndex(at: point) {
            beginRectangleDrag(at: point, index: index)
            return
        }
        selectedRectangleIndex = nil
        let normalized = normalizedPoint(point)
        currentStroke = AnnotationStroke(
            tool: tool,
            points: [normalized],
            color: AnnotationColor(annotationColor),
            width: brushPixelWidth / CGFloat(max(1, min(sourceImage.width, sourceImage.height)))
        )
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if textDragIndex != nil {
            updateTextDrag(to: convert(event.locationInWindow, from: nil))
            return
        }
        if rectangleDragIndex != nil {
            doubleClickTracker.reset()
            lastCommittedStrokeWasTap = false
            updateRectangleDrag(to: convert(event.locationInWindow, from: nil))
            return
        }
        guard var stroke = currentStroke else { return }
        doubleClickTracker.reset()
        lastCommittedStrokeWasTap = false
        let point = normalizedPoint(convert(event.locationInWindow, from: nil))
        if stroke.tool == .pen || stroke.tool == .mosaic {
            stroke.points.append(point)
        } else if stroke.points.count == 1 {
            stroke.points.append(point)
        } else {
            stroke.points[1] = point
        }
        currentStroke = stroke
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if textDragIndex != nil {
            finishTextDrag(commit: true)
            return
        }
        if rectangleDragIndex != nil {
            finishRectangleDrag(commit: true)
            return
        }
        guard var stroke = currentStroke else { return }
        lastCommittedStrokeWasTap = stroke.points.count == 1
        if stroke.points.count == 1 {
            stroke.points.append(normalizedPoint(convert(event.locationInWindow, from: nil)))
        }
        currentStroke = nil
        if stroke.tool == .ocr {
            commitOCRSelection(stroke)
            return
        }
        if stroke.tool == .number {
            let next = history.strokes.filter { $0.tool == .number }.count + 1
            stroke.text = String(next)
        }
        history.append(stroke)
        if stroke.tool == .rectangle {
            selectedRectangleIndex = history.strokes.count - 1
        }
        rebuildCache()
    }

    func undo() {
        finishRectangleDrag(commit: false)
        selectedRectangleIndex = nil
        finishTextDrag(commit: false)
        commitPendingText()
        selectText(at: nil)
        history.undo()
        rebuildCache()
    }

    func redo() {
        finishRectangleDrag(commit: false)
        selectedRectangleIndex = nil
        finishTextDrag(commit: false)
        commitPendingText()
        selectText(at: nil)
        history.redo()
        rebuildCache()
    }

    func clear() {
        finishRectangleDrag(commit: false)
        selectedRectangleIndex = nil
        finishTextDrag(commit: false)
        cancelPendingText()
        selectText(at: nil)
        history.clear()
        rebuildCache()
    }

    func commitPendingText() {
        guard let field = activeTextField, let anchor = activeTextAnchor else { return }
        let editingIndex = activeTextIndex
        activeTextField = nil
        activeTextAnchor = nil
        activeTextIndex = nil
        field.delegate = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        guard !text.isEmpty else {
            if let editingIndex {
                history.remove(at: editingIndex)
                selectText(at: nil)
                rebuildCache()
            }
            return
        }
        let stroke = AnnotationStroke(
            tool: .text,
            points: [anchor],
            color: AnnotationColor(annotationColor),
            width: normalizedTextWidth(forBrushWidth: brushPixelWidth),
            text: text
        )
        if let editingIndex, history.strokes.indices.contains(editingIndex) {
            history.replace(at: editingIndex, with: stroke)
            selectText(at: editingIndex)
        } else {
            history.append(stroke)
            selectText(at: history.strokes.count - 1)
        }
        rebuildCache()
    }

    func updateSourceImage(_ image: CGImage, logicalSize: CGSize) {
        // 选区调整后替换底图，但保留归一化笔迹，使标注随新选区同步缩放。
        finishTextDrag(commit: false)
        sourceImage = image
        self.logicalSize = logicalSize
        pixelatedPreviewImage = AnnotationRenderer.makePixelated(image).map {
            NSImage(cgImage: $0, size: logicalSize)
        }
        rebuildCache()
    }

    func renderedImage() -> NSImage? {
        commitPendingText()
        guard let rendered = try? AnnotationRenderer.render(image: sourceImage, strokes: history.strokes) else { return nil }
        return NSImage(cgImage: rendered, size: logicalSize)
    }

    func cropToSelectedRectangle() -> Bool {
        guard let selectedRectangleIndex,
              history.strokes.indices.contains(selectedRectangleIndex) else { return false }
        let stroke = history.strokes[selectedRectangleIndex]
        guard stroke.tool == .rectangle, stroke.points.count >= 2 else { return false }
        let first = stroke.points[0]
        let last = stroke.points[1]
        let crop = CGRect(
            x: min(first.x, last.x) * CGFloat(sourceImage.width),
            y: min(first.y, last.y) * CGFloat(sourceImage.height),
            width: abs(last.x - first.x) * CGFloat(sourceImage.width),
            height: abs(last.y - first.y) * CGFloat(sourceImage.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))
        guard crop.width >= 3, crop.height >= 3, let cropped = sourceImage.cropping(to: crop) else { return false }
        sourceImage = cropped
        logicalSize = CGSize(width: crop.width, height: crop.height)
        history = AnnotationHistory()
        self.selectedRectangleIndex = nil
        refreshSourceCaches()
        return true
    }

    func rotateClockwise() {
        guard let rotated = Self.rotatedClockwise(sourceImage) else { return }
        sourceImage = rotated
        logicalSize = CGSize(width: logicalSize.height, height: logicalSize.width)
        history = AnnotationHistory()
        selectedRectangleIndex = nil
        refreshSourceCaches()
    }

    func addRedactionRegions(_ regions: [CGRect]) {
        for region in regions where region.width > 0 && region.height > 0 {
            history.append(AnnotationStroke(
                tool: .redaction,
                points: [region.origin, CGPoint(x: region.maxX, y: region.maxY)],
                color: AnnotationColor(.black),
                width: 0.002
            ))
        }
        rebuildCache()
    }

    private func refreshSourceCaches() {
        cachedImage = NSImage(cgImage: sourceImage, size: logicalSize)
        pixelatedPreviewImage = AnnotationRenderer.makePixelated(sourceImage).map {
            NSImage(cgImage: $0, size: logicalSize)
        }
        onHistoryChanged?(false, false)
        needsDisplay = true
    }

    private static func rotatedClockwise(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.height,
            height: image.width,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: CGFloat(image.height), y: 0)
        context.rotate(by: .pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private func rebuildCache(excludingTextAt excludedIndex: Int? = nil) {
        let renderStrokes = history.strokes.enumerated().compactMap { index, stroke in
            index == excludedIndex ? nil : stroke
        }
        if let rendered = try? AnnotationRenderer.render(image: sourceImage, strokes: renderStrokes) {
            cachedImage = NSImage(cgImage: rendered, size: logicalSize)
        }
        onHistoryChanged?(history.canUndo, history.canRedo)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private var imageRect: CGRect {
        let inset = bounds.insetBy(dx: contentInset, dy: contentInset)
        let scale = min(inset.width / logicalSize.width, inset.height / logicalSize.height)
        let size = CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale)
        return CGRect(x: inset.midX - size.width / 2, y: inset.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func normalizedPoint(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(
            x: min(max((point.x - rect.minX) / rect.width, 0), 1),
            y: min(max((point.y - rect.minY) / rect.height, 0), 1)
        )
    }

    private func beginTextEntry(at point: CGPoint, editing index: Int?) {
        let existingStroke = index.flatMap { history.strokes.indices.contains($0) ? history.strokes[$0] : nil }
        let anchor = existingStroke?.points.first ?? normalizedPoint(point)
        let anchorPoint = denormalizedPoint(anchor)
        if let existingStroke {
            isSynchronizingTextStyle = true
            annotationColor = existingStroke.color.nsColor
            brushPixelWidth = brushWidth(forTextStroke: existingStroke)
            isSynchronizingTextStyle = false
        }
        let fontSize = textFontPointSize(forBrushWidth: brushPixelWidth)
        let existingText = existingStroke?.text ?? ""
        let measuredWidth = (existingText as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)]
        ).width
        let availableWidth = max(80, imageRect.maxX - anchorPoint.x)
        let fieldWidth = min(280, availableWidth, max(120, measuredWidth + 34))
        let field = AnnotationTextField(frame: CGRect(
            x: anchorPoint.x,
            y: min(max(anchorPoint.y - 7, imageRect.minY), imageRect.maxY - fontSize - 12),
            width: fieldWidth,
            height: fontSize + 12
        ))
        field.stringValue = existingText
        field.font = .systemFont(ofSize: fontSize, weight: .medium)
        field.textColor = annotationColor
        field.delegate = self
        field.target = self
        field.action = #selector(commitTextField(_:))
        field.onEmptyDoubleClick = { [weak self] in
            self?.cancelPendingText()
            self?.onDoubleClick?()
        }
        activeTextAnchor = anchor
        activeTextIndex = index
        activeTextField = field
        addSubview(field)
        rebuildCache(excludingTextAt: index)
        window?.makeFirstResponder(field)
        if index != nil {
            field.currentEditor()?.selectAll(nil)
        }
    }

    @objc private func commitTextField(_ sender: NSTextField) {
        commitPendingText()
        window?.makeFirstResponder(self)
    }

    private func cancelPendingText() {
        guard let field = activeTextField else { return }
        activeTextField = nil
        activeTextAnchor = nil
        activeTextIndex = nil
        field.delegate = nil
        field.removeFromSuperview()
        rebuildCache()
        window?.makeFirstResponder(self)
    }

    private func beginTextDrag(at point: CGPoint, index: Int) {
        guard history.strokes.indices.contains(index) else { return }
        let stroke = history.strokes[index]
        textDragIndex = index
        textDragStartPoint = point
        textDragOriginalStroke = stroke
        textDragPreviewStroke = stroke
        textDragDidMove = false
        rebuildCache(excludingTextAt: index)
        NSCursor.closedHand.set()
    }

    private func updateTextDrag(to point: CGPoint) {
        guard let startPoint = textDragStartPoint,
              let original = textDragOriginalStroke,
              let originalAnchor = original.points.first else { return }
        let rect = imageRect
        let originalDisplayPoint = denormalizedPoint(originalAnchor)
        let originalBounds = textBounds(for: original, in: rect)
        let proposed = CGPoint(
            x: originalDisplayPoint.x + point.x - startPoint.x,
            y: originalDisplayPoint.y + point.y - startPoint.y
        )
        let minimumY = rect.minY + 3
        let maximumX = max(rect.minX, rect.maxX - originalBounds.width)
        let maximumY = max(minimumY, rect.maxY - originalBounds.height + 3)
        let clamped = CGPoint(
            x: min(max(proposed.x, rect.minX), maximumX),
            y: min(max(proposed.y, minimumY), maximumY)
        )
        var preview = original
        preview.points[0] = normalizedPoint(clamped)
        textDragPreviewStroke = preview
        textDragDidMove = hypot(point.x - startPoint.x, point.y - startPoint.y) >= 1
        needsDisplay = true
    }

    private func finishTextDrag(commit: Bool) {
        guard let index = textDragIndex else { return }
        let preview = textDragPreviewStroke
        let shouldCommit = commit && textDragDidMove
        textDragIndex = nil
        textDragStartPoint = nil
        textDragOriginalStroke = nil
        textDragPreviewStroke = nil
        textDragDidMove = false
        if shouldCommit, let preview, history.strokes.indices.contains(index) {
            history.replace(at: index, with: preview)
        }
        rebuildCache()
        selectText(at: history.strokes.indices.contains(index) ? index : nil)
        NSCursor.openHand.set()
    }

    private func beginRectangleDrag(at point: CGPoint, index: Int) {
        guard history.strokes.indices.contains(index) else { return }
        let stroke = history.strokes[index]
        selectedRectangleIndex = index
        rectangleDragIndex = index
        rectangleDragStartPoint = point
        rectangleDragOriginalStroke = stroke
        rectangleDragPreviewStroke = stroke
        rectangleDragDidMove = false
        rebuildCache(excludingTextAt: index)
        NSCursor.closedHand.set()
    }

    private func updateRectangleDrag(to point: CGPoint) {
        guard let startPoint = rectangleDragStartPoint,
              let original = rectangleDragOriginalStroke,
              original.points.count >= 2 else { return }
        let rect = imageRect
        let proposedDX = (point.x - startPoint.x) / rect.width
        let proposedDY = (point.y - startPoint.y) / rect.height
        let minX = original.points.map(\.x).min() ?? 0
        let maxX = original.points.map(\.x).max() ?? 1
        let minY = original.points.map(\.y).min() ?? 0
        let maxY = original.points.map(\.y).max() ?? 1
        let dx = min(max(proposedDX, -minX), 1 - maxX)
        let dy = min(max(proposedDY, -minY), 1 - maxY)
        var preview = original
        preview.points = original.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        rectangleDragPreviewStroke = preview
        rectangleDragDidMove = hypot(point.x - startPoint.x, point.y - startPoint.y) >= 1
        needsDisplay = true
    }

    private func finishRectangleDrag(commit: Bool) {
        guard let index = rectangleDragIndex else { return }
        let preview = rectangleDragPreviewStroke
        let shouldCommit = commit && rectangleDragDidMove
        rectangleDragIndex = nil
        rectangleDragStartPoint = nil
        rectangleDragOriginalStroke = nil
        rectangleDragPreviewStroke = nil
        rectangleDragDidMove = false
        if shouldCommit, let preview, history.strokes.indices.contains(index) {
            history.replace(at: index, with: preview)
        }
        selectedRectangleIndex = history.strokes.indices.contains(index) ? index : nil
        rebuildCache()
        NSCursor.openHand.set()
    }

    private func applyCurrentStyleToSelectedText() {
        guard !isSynchronizingTextStyle else { return }
        if let field = activeTextField {
            field.textColor = annotationColor
            field.font = .systemFont(
                ofSize: textFontPointSize(forBrushWidth: brushPixelWidth),
                weight: .medium
            )
            return
        }
        guard tool == .text,
              let selectedTextIndex,
              history.strokes.indices.contains(selectedTextIndex),
              history.strokes[selectedTextIndex].tool == .text else { return }
        var stroke = history.strokes[selectedTextIndex]
        stroke.color = AnnotationColor(annotationColor)
        stroke.width = normalizedTextWidth(forBrushWidth: brushPixelWidth)
        history.replace(at: selectedTextIndex, with: stroke)
        rebuildCache()
    }

    private func selectText(at index: Int?) {
        selectedTextIndex = index
        guard let index, history.strokes.indices.contains(index) else {
            needsDisplay = true
            return
        }
        let stroke = history.strokes[index]
        let selectedBrushWidth = brushWidth(forTextStroke: stroke)
        isSynchronizingTextStyle = true
        annotationColor = stroke.color.nsColor
        brushPixelWidth = selectedBrushWidth
        isSynchronizingTextStyle = false
        onSelectedTextStyleChanged?(stroke.color.nsColor, selectedBrushWidth)
        needsDisplay = true
    }

    private func textStrokeIndex(at point: CGPoint) -> Int? {
        for index in history.strokes.indices.reversed() {
            let stroke = history.strokes[index]
            guard stroke.tool == .text else { continue }
            if textBounds(for: stroke, in: imageRect).insetBy(dx: -6, dy: -6).contains(point) {
                return index
            }
        }
        return nil
    }

    private func textBounds(for stroke: AnnotationStroke, in rect: CGRect) -> CGRect {
        guard let anchor = stroke.points.first else { return .zero }
        let text = stroke.text ?? ""
        let fontSize = textFontPointSize(for: stroke)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGRect(
            x: rect.minX + anchor.x * rect.width,
            y: rect.minY + anchor.y * rect.height - 3,
            width: max(12, size.width),
            height: max(fontSize, size.height) + 6
        )
    }

    private func drawTextSelection(for stroke: AnnotationStroke, in rect: CGRect) {
        let selectionRect = textBounds(for: stroke, in: rect).insetBy(dx: -5, dy: -4)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 5, yRadius: 5)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }

    private func rectangleStrokeIndex(at point: CGPoint) -> Int? {
        for index in history.strokes.indices.reversed() {
            let stroke = history.strokes[index]
            guard stroke.tool == .rectangle else { continue }
            if rectangleBounds(for: stroke, in: imageRect).insetBy(dx: -6, dy: -6).contains(point) {
                return index
            }
        }
        return nil
    }

    private func rectangleBounds(for stroke: AnnotationStroke, in rect: CGRect) -> CGRect {
        guard let first = stroke.points.first, let last = stroke.points.last else { return .zero }
        let firstPoint = CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height)
        let lastPoint = CGPoint(x: rect.minX + last.x * rect.width, y: rect.minY + last.y * rect.height)
        return CGRect(
            x: min(firstPoint.x, lastPoint.x),
            y: min(firstPoint.y, lastPoint.y),
            width: abs(lastPoint.x - firstPoint.x),
            height: abs(lastPoint.y - firstPoint.y)
        )
    }

    private func drawRectangleSelection(for stroke: AnnotationStroke, in rect: CGRect) {
        let selectionRect = rectangleBounds(for: stroke, in: rect).insetBy(dx: -4, dy: -4)
        let path = NSBezierPath(rect: selectionRect)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }

    private func drawTextPreview(_ stroke: AnnotationStroke, in rect: CGRect) {
        guard let anchor = stroke.points.first,
              let text = stroke.text,
              !text.isEmpty else { return }
        let point = CGPoint(x: rect.minX + anchor.x * rect.width, y: rect.minY + anchor.y * rect.height)
        (text as NSString).draw(
            at: point,
            withAttributes: [
                .font: NSFont.systemFont(ofSize: textFontPointSize(for: stroke), weight: .medium),
                .foregroundColor: stroke.color.nsColor
            ]
        )
    }

    private func denormalizedPoint(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private var sourcePointScale: CGFloat {
        let scaleX = CGFloat(sourceImage.width) / max(1, logicalSize.width)
        let scaleY = CGFloat(sourceImage.height) / max(1, logicalSize.height)
        return max(1, min(scaleX, scaleY))
    }

    private func textFontPointSize(forBrushWidth width: CGFloat) -> CGFloat {
        max(14, width * 2)
    }

    private func normalizedTextWidth(forBrushWidth width: CGFloat) -> CGFloat {
        let fontPixels = textFontPointSize(forBrushWidth: width) * sourcePointScale
        return fontPixels / CGFloat(max(1, min(sourceImage.width, sourceImage.height)))
    }

    private func textFontPointSize(for stroke: AnnotationStroke) -> CGFloat {
        stroke.width * CGFloat(max(1, min(sourceImage.width, sourceImage.height))) / sourcePointScale
    }

    private func brushWidth(forTextStroke stroke: AnnotationStroke) -> CGFloat {
        max(2, min(36, textFontPointSize(for: stroke) / 2))
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitPendingText()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelPendingText()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitPendingText()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    private func commitOCRSelection(_ stroke: AnnotationStroke) {
        guard let cropped = croppedSourceImage(for: stroke) else { return }
        var pending = stroke
        pending.text = L10n.text("annotation.ocr.pending")
        history.append(pending)
        let pendingIndex = history.strokes.count - 1
        rebuildCache()

        let source = OCRSourceImage(image: cropped)
        Task.detached { [weak self] in
            let recognizedText: String
            do {
                let recognized = try await InteractiveOCRService.recognizeText(in: source.image)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                recognizedText = recognized.isEmpty ? L10n.text("annotation.ocr.empty") : recognized
            } catch {
                recognizedText = L10n.text("annotation.ocr.failed")
            }
            await MainActor.run {
                guard let self,
                      self.history.strokes.indices.contains(pendingIndex),
                      self.history.strokes[pendingIndex] == pending else { return }
                var recognized = pending
                recognized.text = recognizedText
                self.history.replace(at: pendingIndex, with: recognized)
                self.rebuildCache()
            }
        }
    }

    private func croppedSourceImage(for stroke: AnnotationStroke) -> CGImage? {
        guard stroke.points.count >= 2 else { return nil }
        let first = stroke.points[0]
        let last = stroke.points[1]
        let crop = CGRect(
            x: min(first.x, last.x) * CGFloat(sourceImage.width),
            y: min(first.y, last.y) * CGFloat(sourceImage.height),
            width: abs(last.x - first.x) * CGFloat(sourceImage.width),
            height: abs(last.y - first.y) * CGFloat(sourceImage.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))
        guard crop.width >= 2, crop.height >= 2 else { return nil }
        return sourceImage.cropping(to: crop)
    }

    private func drawPreview(_ stroke: AnnotationStroke, in rect: CGRect) {
        let points = stroke.points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = max(1, stroke.width * min(rect.width, rect.height))
        if stroke.tool == .mosaic, let pixelatedPreviewImage,
           let context = NSGraphicsContext.current?.cgContext {
            // 用当前未提交笔迹作为 clip，鼠标移动时直接露出像素化底图。
            context.saveGState()
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineWidth(path.lineWidth)
            context.beginPath()
            context.move(to: first)
            points.dropFirst().forEach { context.addLine(to: $0) }
            if points.count == 1 { context.addLine(to: first) }
            context.replacePathWithStrokedPath()
            context.clip()
            pixelatedPreviewImage.draw(
                in: rect,
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.none]
            )
            context.restoreGState()
            return
        }
        stroke.color.nsColor.setStroke()
        path.move(to: first)
        if stroke.tool == .rectangle || stroke.tool == .highlight || stroke.tool == .ocr || stroke.tool == .ellipse || stroke.tool == .redaction,
           let last = points.last {
            let box = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
            if stroke.tool == .highlight {
                stroke.color.nsColor.withAlphaComponent(0.28).setFill()
                box.fill()
            } else if stroke.tool == .ocr {
                NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
                NSColor.controlAccentColor.setStroke()
                let border = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
                border.lineWidth = 1.5
                border.setLineDash([4, 3], count: 2, phase: 0)
                border.stroke()
            } else if stroke.tool == .ellipse {
                stroke.color.nsColor.setStroke()
                NSBezierPath(ovalIn: box).stroke()
            } else if stroke.tool == .redaction {
                NSColor.black.withAlphaComponent(0.7).setFill()
                box.fill()
            } else {
                NSBezierPath(rect: box).stroke()
            }
        } else if stroke.tool == .arrow, let last = points.last {
            path.line(to: last)
            let head = AnnotationGeometry.arrowHead(from: first, to: last, length: max(path.lineWidth * 3, 12))
            path.move(to: head.0); path.line(to: last); path.line(to: head.1); path.stroke()
        } else if stroke.tool == .line, let last = points.last {
            path.line(to: last)
            path.stroke()
        } else if stroke.tool == .number {
            let radius = max(10, path.lineWidth)
            stroke.color.nsColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2)).fill()
        } else if stroke.tool != .text {
            points.dropFirst().forEach { path.line(to: $0) }
            path.stroke()
        }
    }
}

private extension NSImage {
    var cgImageValue: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
