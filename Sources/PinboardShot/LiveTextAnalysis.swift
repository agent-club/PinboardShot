import AppKit
import CoreVideo
import ImageIO
import Vision
import VisionKit

private enum LiveTextAnalysisError: Error {
    case imageUnavailable
    case pixelBufferCreation(CVReturn)
    case pixelBufferLock(CVReturn)
    case bitmapContextCreation
}

private struct LiveTextPixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

struct LiveTextRecognizedLine: Sendable {
    let text: String
    let characterRects: [CGRect]
}

struct LiveTextCharacterLayout: Sendable {
    static let empty = LiveTextCharacterLayout(lines: [])

    let lines: [LiveTextRecognizedLine]

    func containsCharacter(at point: CGPoint, contentBounds: CGRect) -> Bool {
        guard contentBounds.width > 0, contentBounds.height > 0 else { return false }
        return character(at: normalized(point, in: contentBounds)) != nil
    }

    func selectionRange(
        in transcript: String,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        contentBounds: CGRect
    ) -> Range<String.Index>? {
        guard contentBounds.width > 0,
              contentBounds.height > 0,
              let start = character(at: normalized(startPoint, in: contentBounds)),
              let end = character(at: normalized(endPoint, in: contentBounds)),
              start.lineIndex == end.lineIndex else { return nil }

        let line = lines[start.lineIndex]
        guard let lineRange = transcript.range(of: line.text) else { return nil }
        let lowerOffset = min(start.characterIndex, end.characterIndex)
        let upperOffset = max(start.characterIndex, end.characterIndex) + 1
        guard upperOffset <= line.text.count else { return nil }

        let lowerBound = transcript.index(lineRange.lowerBound, offsetBy: lowerOffset)
        let upperBound = transcript.index(lineRange.lowerBound, offsetBy: upperOffset)
        return lowerBound..<upperBound
    }

    private func normalized(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: (point.x - bounds.minX) / bounds.width,
            y: (point.y - bounds.minY) / bounds.height
        )
    }

    private func character(at point: CGPoint) -> (lineIndex: Int, characterIndex: Int)? {
        var nearest: (lineIndex: Int, characterIndex: Int, distance: CGFloat)?
        for (lineIndex, line) in lines.enumerated() {
            for (characterIndex, rect) in line.characterRects.enumerated() {
                if rect.insetBy(dx: -0.004, dy: -0.01).contains(point) {
                    return (lineIndex, characterIndex)
                }
                guard point.y >= rect.minY - 0.02, point.y <= rect.maxY + 0.02 else { continue }
                let horizontalDistance = max(
                    max(rect.minX - point.x, point.x - rect.maxX),
                    0
                )
                if nearest == nil || horizontalDistance < nearest!.distance {
                    nearest = (lineIndex, characterIndex, horizontalDistance)
                }
            }
        }
        guard let nearest, nearest.distance <= 0.02 else { return nil }
        return (nearest.lineIndex, nearest.characterIndex)
    }
}

struct LiveTextAnalysisResult {
    let analysis: ImageAnalysis
    let characterLayout: LiveTextCharacterLayout
}

enum LiveTextInteractionPolicy {
    static func routesToText(
        hasInteractiveItem: Bool,
        hasActiveSelection: Bool,
        isResizeInteraction: Bool
    ) -> Bool {
        !isResizeInteraction && (hasInteractiveItem || hasActiveSelection)
    }
}

@MainActor
final class LiveTextAnalysisService {
    static let shared = LiveTextAnalysisService()

    private let analyzer = ImageAnalyzer()

    private init() {}

    func analyze(_ image: NSImage) async throws -> LiveTextAnalysisResult? {
        guard ImageAnalyzer.isSupported else { return nil }
        let pixelBuffer = try Self.makePixelBuffer(from: image)
        let characterLayoutTask = Task.detached {
            try Self.recognizeCharacterLayout(in: pixelBuffer.value)
        }
        let analysis = try await analyzer.analyze(
            pixelBuffer.value,
            orientation: .up,
            configuration: ImageAnalyzer.Configuration([.text])
        )
        let characterLayout = (try? await characterLayoutTask.value) ?? .empty
        return LiveTextAnalysisResult(
            analysis: analysis,
            characterLayout: characterLayout
        )
    }

    private static func makePixelBuffer(from image: NSImage) throws -> LiveTextPixelBuffer {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw LiveTextAnalysisError.imageUnavailable
        }

        let attributes: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary
        var optionalPixelBuffer: CVPixelBuffer?
        let creationStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            cgImage.width,
            cgImage.height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &optionalPixelBuffer
        )
        guard creationStatus == kCVReturnSuccess, let pixelBuffer = optionalPixelBuffer else {
            throw LiveTextAnalysisError.pixelBufferCreation(creationStatus)
        }

        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw LiveTextAnalysisError.pixelBufferLock(lockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw LiveTextAnalysisError.bitmapContextCreation
        }
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )
        return LiveTextPixelBuffer(value: pixelBuffer)
    }

    nonisolated private static func recognizeCharacterLayout(
        in pixelBuffer: CVPixelBuffer
    ) throws -> LiveTextCharacterLayout {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        if let supportedLanguages = try? request.supportedRecognitionLanguages() {
            let languages = preferredLanguages.filter { supportedLanguages.contains($0) }
            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }
        }
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { observation -> LiveTextRecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            var characterRects: [CGRect] = []
            characterRects.reserveCapacity(text.count)
            var index = text.startIndex
            while index < text.endIndex {
                let nextIndex = text.index(after: index)
                guard let box = try? candidate.boundingBox(for: index..<nextIndex) else {
                    return nil
                }
                characterRects.append(box.boundingBox)
                index = nextIndex
            }
            guard characterRects.count == text.count else { return nil }
            return LiveTextRecognizedLine(
                text: text,
                characterRects: resolvedCharacterRects(characterRects, for: text)
            )
        }
        return LiveTextCharacterLayout(lines: lines)
    }

    nonisolated private static func resolvedCharacterRects(
        _ rawRects: [CGRect],
        for text: String
    ) -> [CGRect] {
        guard let first = rawRects.first, rawRects.count == text.count else { return rawRects }
        let systemReturnedDistinctRects = rawRects.dropFirst().contains { rect in
            abs(rect.minX - first.minX) > 0.0001
                || abs(rect.width - first.width) > 0.0001
                || abs(rect.minY - first.minY) > 0.0001
                || abs(rect.height - first.height) > 0.0001
        }
        guard !systemReturnedDistinctRects else { return rawRects }

        let characters = Array(text)
        let weights = characters.map(characterWidthWeight)
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return rawRects }

        var nextX = first.minX
        return weights.enumerated().map { index, weight in
            let width = index == weights.count - 1
                ? first.maxX - nextX
                : first.width * weight / totalWeight
            defer { nextX += width }
            return CGRect(x: nextX, y: first.minY, width: width, height: first.height)
        }
    }

    nonisolated private static func characterWidthWeight(_ character: Character) -> CGFloat {
        if "ilIjtfr.,'`!|:;".contains(character) { return 0.5 }
        if "mwMW@#%&".contains(character) { return 1.35 }
        if character.isWhitespace { return 0.45 }
        if character.wholeNumberValue != nil { return 0.9 }
        return 1
    }
}

@MainActor
final class LiveTextCharacterSelectionRefiner {
    private weak var containerView: NSView?
    private weak var overlayView: ImageAnalysisOverlayView?
    private let canBegin: (CGPoint, NSEvent) -> Bool
    private let preservesSelectionOnRejectedGesture: Bool
    nonisolated(unsafe) private var eventMonitor: Any?
    private var startPoint: CGPoint?
    private var characterLayout = LiveTextCharacterLayout.empty
    private(set) var selectedText: String?

    init(
        containerView: NSView,
        overlayView: ImageAnalysisOverlayView,
        preservesSelectionOnRejectedGesture: Bool = false,
        canBegin: @escaping (CGPoint, NSEvent) -> Bool
    ) {
        self.containerView = containerView
        self.overlayView = overlayView
        self.preservesSelectionOnRejectedGesture = preservesSelectionOnRejectedGesture
        self.canBegin = canBegin
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    func update(characterLayout: LiveTextCharacterLayout) {
        self.characterLayout = characterLayout
    }

    func reset() {
        startPoint = nil
        characterLayout = .empty
        selectedText = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let containerView,
              let overlayView,
              event.window === containerView.window else { return event }

        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c",
           copyRefinedSelection() {
            return nil
        }

        let containerPoint = containerView.convert(event.locationInWindow, from: nil)
        let overlayPoint = containerView.convert(containerPoint, to: overlayView)

        switch event.type {
        case .leftMouseDown:
            let mayBegin = canBegin(containerPoint, event)
            let containsPoint = overlayView.bounds.contains(overlayPoint)
            guard mayBegin, containsPoint else {
                startPoint = nil
                if !preservesSelectionOnRejectedGesture {
                    selectedText = nil
                }
                return event
            }
            startPoint = overlayPoint
            selectedText = nil
        case .leftMouseUp:
            guard let startPoint else { return event }
            self.startPoint = nil
            let endPoint = overlayPoint
            DispatchQueue.main.async { [weak self, weak overlayView] in
                guard let self, let overlayView else { return }
                guard let range = characterLayout.selectionRange(
                        in: overlayView.text,
                        from: startPoint,
                        to: endPoint,
                        contentBounds: overlayView.bounds
                      ) else { return }
                selectedText = String(overlayView.text[range])
                overlayView.selectedRanges = [range]
            }
        default:
            break
        }
        return event
    }

    @discardableResult
    func copyRefinedSelection() -> Bool {
        guard let selectedText, !selectedText.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(selectedText, forType: .string)
    }
}
