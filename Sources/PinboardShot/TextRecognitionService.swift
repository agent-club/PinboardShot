import AppKit
import Foundation
import Vision

enum TextRecognitionService {
    static func recognizeText(in image: NSImage) throws -> String {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw PinboardShotError.imageEncodingFailed
        }
        return try recognizeText(in: cgImage)
    }

    static func recognizeText(in image: CGImage) throws -> String {
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

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func sensitiveRegions(in image: CGImage) throws -> [CGRect] {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let barcodeRequest = VNDetectBarcodesRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([textRequest, barcodeRequest, faceRequest])

        let sensitiveTextRegions = (textRequest.results ?? []).compactMap { observation -> CGRect? in
            guard let text = observation.topCandidates(1).first?.string,
                  isSensitiveText(text) else { return nil }
            return expanded(observation.boundingBox)
        }
        let barcodeRegions = (barcodeRequest.results ?? []).map { expanded($0.boundingBox) }
        let faceRegions = (faceRequest.results ?? []).map { expanded($0.boundingBox) }
        return sensitiveTextRegions + barcodeRegions + faceRegions
    }

    private static func isSensitiveText(_ text: String) -> Bool {
        let patterns = [
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"(?:https?://|www\.)\S+"#,
            #"(?:\+?\d[\d\s().-]{6,}\d)"#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func expanded(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -0.008, dy: -0.008).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
