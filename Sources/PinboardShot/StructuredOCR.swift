import AppKit
import Vision

struct OCRTextBox: Sendable {
    let text: String
    let bounds: CGRect
}

enum StructuredOCRFormat: String, CaseIterable, Identifiable {
    case plain, layout, tsv, markdown
    var id: String { rawValue }
    var title: String { L10n.text("feature.ocr.format.\(rawValue)") }
}

enum StructuredOCR {
    static func recognize(image: CGImage) throws -> [OCRTextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).flatMap { observation -> [OCRTextBox] in
            guard let candidate = observation.topCandidates(1).first else { return [] }
            let text = candidate.string
            let regex = try? NSRegularExpression(pattern: "\\S+")
            let words = (regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []).compactMap { match -> OCRTextBox? in
                guard let range = Range(match.range, in: text), let box = try? candidate.boundingBox(for: range) else { return nil }
                return OCRTextBox(text: String(text[range]), bounds: box.boundingBox)
            }
            guard words.count > 1 else { return [OCRTextBox(text: text, bounds: observation.boundingBox)] }
            var cells: [OCRTextBox] = []
            for word in words {
                if let previous = cells.last, word.bounds.minX - previous.bounds.maxX < max(previous.bounds.height, word.bounds.height) * 0.65 {
                    cells[cells.count - 1] = OCRTextBox(text: previous.text + " " + word.text, bounds: previous.bounds.union(word.bounds))
                } else { cells.append(word) }
            }
            return cells
        }
    }

    static func rows(_ boxes: [OCRTextBox]) -> [[OCRTextBox]] {
        let sorted = boxes.filter { !$0.text.isEmpty && !$0.bounds.isEmpty &&
            $0.bounds.origin.x.isFinite && $0.bounds.origin.y.isFinite &&
            $0.bounds.width.isFinite && $0.bounds.height.isFinite
        }.sorted { $0.bounds.midY > $1.bounds.midY }
        var result: [[OCRTextBox]] = []
        for box in sorted {
            if let index = result.indices.last,
               let reference = result[index].first,
               abs(reference.bounds.midY - box.bounds.midY) < min(reference.bounds.height, box.bounds.height) * 0.6 {
                result[index].append(box)
            } else { result.append([box]) }
        }
        return result.map { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }

    static func format(_ boxes: [OCRTextBox], as format: StructuredOCRFormat) -> String {
        let rows = rows(boxes)
        guard !rows.isEmpty else { return "" }
        switch format {
        case .plain:
            return rows.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
        case .layout:
            let characterWidths = boxes.filter { !$0.text.isEmpty }.map { $0.bounds.width / CGFloat($0.text.count) }.sorted()
            let width = max(0.002, characterWidths[characterWidths.count / 2])
            let left = boxes.map(\.bounds.minX).min() ?? 0
            return rows.map { row in
                var line = ""
                var column = 0
                for box in row {
                    let target = min(500, max(0, Int(((box.bounds.minX - left) / width).rounded())))
                    if !line.isEmpty || target > 0 {
                        let spaces = max(line.isEmpty ? 0 : 1, target - column)
                        line += String(repeating: " ", count: spaces)
                        column += spaces
                    }
                    line += box.text
                    column += box.text.count
                }
                return line
            }.joined(separator: "\n")
        case .tsv, .markdown:
            let table = tableRows(rows)
            if format == .tsv {
                return table.map { $0.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") }.joined(separator: "\t") }.joined(separator: "\n")
            }
            let lines = table.map { row in
                "| " + row.map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>").replacingOccurrences(of: "\r", with: "") }.joined(separator: " | ") + " |"
            }
            let divider = "| " + Array(repeating: "---", count: table[0].count).joined(separator: " | ") + " |"
            return ([lines[0], divider] + Array(lines.dropFirst())).joined(separator: "\n")
        }
    }

    private static func tableRows(_ rows: [[OCRTextBox]]) -> [[String]] {
        // Infer stable left edges; empty cells are preserved instead of shifting later columns.
        let sorted = rows.flatMap { $0 }.map(\.bounds.minX).sorted()
        var columns: [CGFloat] = []
        for x in sorted where columns.last.map({ x - $0 > 0.035 }) ?? true { columns.append(x) }
        return rows.map { row in
            var cells = Array(repeating: "", count: columns.count)
            for box in row {
                let index = columns.indices.min { abs(columns[$0] - box.bounds.minX) < abs(columns[$1] - box.bounds.minX) } ?? 0
                if !cells[index].isEmpty { cells[index] += " " }
                cells[index] += box.text
            }
            return cells
        }
    }
}
