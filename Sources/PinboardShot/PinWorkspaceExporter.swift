import CoreGraphics
import Foundation
import ImageIO

enum PinWorkspaceExportFormat: Equatable, Sendable {
    case images
    case pdf
    case markdown
}

struct PinWorkspaceExportItem: Sendable {
    let ordinal: Int
    let pngData: Data
    let metadata: PinMetadata
}

struct PinWorkspaceExportPlan: Sendable {
    let workspace: PinWorkspaceSummary
    let items: [PinWorkspaceExportItem]
    let skippedPinCount: Int
}

struct PinWorkspaceExportReport: Equatable, Sendable {
    let destinationURL: URL
    let format: PinWorkspaceExportFormat
    let requestedPinCount: Int
    let exportedPinCount: Int
    let skippedSourcePinCount: Int
    let failedEncodingPinCount: Int

    var failedItemCount: Int {
        failedEncodingPinCount
    }

    var skippedPinCount: Int {
        skippedSourcePinCount + failedEncodingPinCount
    }
}

enum PinWorkspaceExporterError: LocalizedError, Equatable {
    case invalidDestination
    case noExportablePins
    case pdfCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            L10n.text("pinWorkspace.export.error.invalidDestination")
        case .noExportablePins:
            L10n.text("pinWorkspace.export.error.noExportablePins")
        case .pdfCreationFailed:
            L10n.text("pinWorkspace.export.error.pdfCreationFailed")
        }
    }
}

final class PinWorkspaceExporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func export(
        _ plan: PinWorkspaceExportPlan,
        to parentDirectory: URL,
        format: PinWorkspaceExportFormat
    ) throws -> PinWorkspaceExportReport {
        guard isDirectory(parentDirectory) else {
            throw PinWorkspaceExporterError.invalidDestination
        }

        switch format {
        case .images:
            return try exportImages(plan, to: parentDirectory)
        case .pdf:
            return try exportPDF(plan, to: parentDirectory)
        case .markdown:
            return try exportMarkdown(plan, to: parentDirectory)
        }
    }

    private func exportImages(
        _ plan: PinWorkspaceExportPlan,
        to parentDirectory: URL
    ) throws -> PinWorkspaceExportReport {
        let destinationURL = availableDestination(
            in: parentDirectory,
            baseName: exportBaseName(for: plan.workspace.name, suffix: "-images"),
            pathExtension: nil
        )
        let temporaryURL = try makeTemporaryDirectory(in: parentDirectory)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        var exportedCount = 0
        var failedCount = 0
        var usedOrdinals = Set<Int>()
        for item in plan.items {
            guard isValid(item), usedOrdinals.insert(item.ordinal).inserted else {
                failedCount += 1
                continue
            }

            let imageURL = temporaryURL.appendingPathComponent(imageFilename(for: item.ordinal))
            try item.pngData.write(to: imageURL, options: .atomic)
            exportedCount += 1
        }

        guard exportedCount > 0 else {
            throw PinWorkspaceExporterError.noExportablePins
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return report(
            for: plan,
            format: .images,
            destinationURL: destinationURL,
            exportedCount: exportedCount,
            failedCount: failedCount
        )
    }

    private func exportMarkdown(
        _ plan: PinWorkspaceExportPlan,
        to parentDirectory: URL
    ) throws -> PinWorkspaceExportReport {
        let destinationURL = availableDestination(
            in: parentDirectory,
            baseName: exportBaseName(for: plan.workspace.name, suffix: "-markdown"),
            pathExtension: nil
        )
        let temporaryURL = try makeTemporaryDirectory(in: parentDirectory)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let imagesURL = temporaryURL.appendingPathComponent("images", isDirectory: true)
        try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: false)

        var sections = ["# \(escapeMarkdownHeading(plan.workspace.name))"]
        var exportedCount = 0
        var failedCount = 0
        var usedOrdinals = Set<Int>()
        for item in plan.items {
            guard isValid(item), usedOrdinals.insert(item.ordinal).inserted else {
                failedCount += 1
                continue
            }

            let filename = imageFilename(for: item.ordinal)
            let imageURL = imagesURL.appendingPathComponent(filename)
            try item.pngData.write(to: imageURL, options: .atomic)

            var section = "![Pin \(item.ordinal)](images/\(filename))"
            let note = item.metadata.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                section += "\n\n**Note:**\n\n\(escapeMarkdown(note))"
            }
            let tags = item.metadata.tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !tags.isEmpty {
                section += "\n\n**Tags:** \(tags.map(escapeMarkdown).joined(separator: ", "))"
            }
            sections.append(section)
            exportedCount += 1
        }

        guard exportedCount > 0 else {
            throw PinWorkspaceExporterError.noExportablePins
        }
        let markdown = sections.joined(separator: "\n\n") + "\n"
        try Data(markdown.utf8).write(
            to: temporaryURL.appendingPathComponent("README.md"),
            options: .atomic
        )
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return report(
            for: plan,
            format: .markdown,
            destinationURL: destinationURL,
            exportedCount: exportedCount,
            failedCount: failedCount
        )
    }

    private func exportPDF(
        _ plan: PinWorkspaceExportPlan,
        to parentDirectory: URL
    ) throws -> PinWorkspaceExportReport {
        let destinationURL = availableDestination(
            in: parentDirectory,
            baseName: exportBaseName(for: plan.workspace.name, suffix: ""),
            pathExtension: "pdf"
        )
        let temporaryURL = parentDirectory.appendingPathComponent(
            ".PinboardShot-export-\(UUID().uuidString).pdf"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard let consumer = CGDataConsumer(url: temporaryURL as CFURL) else {
            throw PinWorkspaceExporterError.pdfCreationFailed
        }
        let documentInfo = [
            kCGPDFContextTitle: plan.workspace.name,
            kCGPDFContextCreator: "PinboardShot"
        ] as CFDictionary
        var defaultMediaBox = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &defaultMediaBox,
            documentInfo
        ) else {
            throw PinWorkspaceExporterError.pdfCreationFailed
        }

        var exportedCount = 0
        var failedCount = 0
        var usedOrdinals = Set<Int>()
        for item in plan.items {
            guard usedOrdinals.insert(item.ordinal).inserted,
                  let image = decodedImage(for: item),
                  image.width > 0,
                  image.height > 0 else {
                failedCount += 1
                continue
            }

            let mediaBox = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
            var encodedMediaBox = mediaBox
            let mediaBoxData = Data(
                bytes: &encodedMediaBox,
                count: MemoryLayout<CGRect>.size
            )
            let pageInfo = [kCGPDFContextMediaBox: mediaBoxData] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.draw(image, in: mediaBox)
            context.endPDFPage()
            exportedCount += 1
        }
        context.closePDF()

        guard exportedCount > 0 else {
            throw PinWorkspaceExporterError.noExportablePins
        }
        guard let attributes = try? fileManager.attributesOfItem(atPath: temporaryURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value > 0 else {
            throw PinWorkspaceExporterError.pdfCreationFailed
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return report(
            for: plan,
            format: .pdf,
            destinationURL: destinationURL,
            exportedCount: exportedCount,
            failedCount: failedCount
        )
    }

    private func report(
        for plan: PinWorkspaceExportPlan,
        format: PinWorkspaceExportFormat,
        destinationURL: URL,
        exportedCount: Int,
        failedCount: Int
    ) -> PinWorkspaceExportReport {
        let skippedSourceCount = max(0, plan.skippedPinCount)
        return PinWorkspaceExportReport(
            destinationURL: destinationURL,
            format: format,
            requestedPinCount: plan.items.count + skippedSourceCount,
            exportedPinCount: exportedCount,
            skippedSourcePinCount: skippedSourceCount,
            failedEncodingPinCount: failedCount
        )
    }

    private func isValid(_ item: PinWorkspaceExportItem) -> Bool {
        item.ordinal > 0 && decodedImage(for: item) != nil
    }

    private func decodedImage(for item: PinWorkspaceExportItem) -> CGImage? {
        guard item.ordinal > 0,
              let source = CGImageSourceCreateWithData(item.pngData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func imageFilename(for ordinal: Int) -> String {
        String(format: "%03d.png", ordinal)
    }

    private func makeTemporaryDirectory(in parentDirectory: URL) throws -> URL {
        let url = parentDirectory.appendingPathComponent(
            ".PinboardShot-export-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    private func availableDestination(
        in parentDirectory: URL,
        baseName: String,
        pathExtension: String?
    ) -> URL {
        var suffix = 1
        while true {
            let numberedBaseName = suffix == 1 ? baseName : "\(baseName)-\(suffix)"
            var candidate = parentDirectory.appendingPathComponent(numberedBaseName)
            if let pathExtension {
                candidate.appendPathExtension(pathExtension)
            }
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private func exportBaseName(for workspaceName: String, suffix: String) -> String {
        let fixedText = "PinboardShot-\(suffix)"
        let byteBudget = max(1, 220 - fixedText.utf8.count)
        let safeName = truncateToUTF8ByteCount(
            safeWorkspaceName(workspaceName),
            maximumByteCount: byteBudget
        )
        return "PinboardShot-\(safeName)\(suffix)"
    }

    private func safeWorkspaceName(_ workspaceName: String) -> String {
        enum PreviousCharacter {
            case content
            case whitespace
            case separator
        }

        var output = ""
        var previous: PreviousCharacter?
        for character in workspaceName {
            if isUnsafeFilenameCharacter(character) {
                if previous != .separator {
                    output.append("-")
                }
                previous = .separator
            } else if character.isWhitespace {
                if previous != .whitespace {
                    output.append(" ")
                }
                previous = .whitespace
            } else {
                output.append(character)
                previous = .content
            }
        }

        let trimSet = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".-"))
        let trimmed = String(output.trimmingCharacters(in: trimSet).prefix(80))
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else {
            return "Workspace"
        }
        return trimmed
    }

    private func isUnsafeFilenameCharacter(_ character: Character) -> Bool {
        if character == "/" || character == "\\" || character == ":" {
            return true
        }
        return character.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private func truncateToUTF8ByteCount(_ text: String, maximumByteCount: Int) -> String {
        var result = ""
        for character in text {
            let candidate = result + String(character)
            guard candidate.utf8.count <= maximumByteCount else { break }
            result = candidate
        }
        return result.isEmpty ? "Workspace" : result
    }

    private func escapeMarkdown(_ text: String) -> String {
        let markdownControlCharacters = CharacterSet(charactersIn: "\\`*_{}[]<>()#+-.!|")
        var escaped = ""
        for scalar in text.unicodeScalars {
            if scalar == "\r" {
                continue
            }
            if scalar == "\n" {
                escaped.append("\n")
            } else if markdownControlCharacters.contains(scalar) {
                escaped.append("\\")
                escaped.unicodeScalars.append(scalar)
            } else if CharacterSet.controlCharacters.contains(scalar) {
                escaped.append(" ")
            } else {
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }

    private func escapeMarkdownHeading(_ text: String) -> String {
        let normalized = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return escapeMarkdown(normalized.isEmpty ? "Workspace" : normalized)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
