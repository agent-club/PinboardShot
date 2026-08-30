import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import PinboardShot

private func exporterPNG(color: NSColor, size: CGSize) throws -> Data {
    let image = NSImage(size: size)
    image.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    guard let data = image.pngData else {
        throw PinWorkspaceExporterError.noExportablePins
    }
    return data
}

private func exporterWorkspace(name: String = "设计/对稿") -> PinWorkspaceSummary {
    PinWorkspaceSummary(
        id: UUID(),
        name: name,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        pinCount: 2
    )
}

@Test("工作区图片和 Markdown 导出保持序号、元数据与冲突文件")
func pinWorkspaceExporterImagesAndMarkdown() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceExporter-\(UUID())")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: root) }

    let metadata = try PinMetadata(note: "对照 *备注*", tags: ["UI", "#重要"])
    let plan = PinWorkspaceExportPlan(
        workspace: exporterWorkspace(),
        items: [
            PinWorkspaceExportItem(
                ordinal: 1,
                pngData: try exporterPNG(color: .red, size: CGSize(width: 20, height: 10)),
                metadata: metadata
            ),
            PinWorkspaceExportItem(
                ordinal: 3,
                pngData: try exporterPNG(color: .blue, size: CGSize(width: 12, height: 18)),
                metadata: .empty
            )
        ],
        skippedPinCount: 1
    )
    let exporter = PinWorkspaceExporter(fileManager: fileManager)

    let imagesReport = try exporter.export(plan, to: root, format: .images)
    #expect(imagesReport.requestedPinCount == 3)
    #expect(imagesReport.exportedPinCount == 2)
    #expect(imagesReport.skippedPinCount == 1)
    #expect(fileManager.fileExists(atPath: imagesReport.destinationURL.appendingPathComponent("001.png").path))
    #expect(fileManager.fileExists(atPath: imagesReport.destinationURL.appendingPathComponent("003.png").path))
    #expect(!fileManager.fileExists(atPath: imagesReport.destinationURL.appendingPathComponent("manifest.json").path))

    let secondImagesReport = try exporter.export(plan, to: root, format: .images)
    #expect(secondImagesReport.destinationURL != imagesReport.destinationURL)
    #expect(secondImagesReport.destinationURL.lastPathComponent.hasSuffix("-2"))

    let markdownReport = try exporter.export(plan, to: root, format: .markdown)
    let readmeURL = markdownReport.destinationURL.appendingPathComponent("README.md")
    let readme = try String(contentsOf: readmeURL, encoding: .utf8)
    #expect(readme.contains("images/001.png"))
    #expect(readme.contains("images/003.png"))
    #expect(readme.contains("对照 \\*备注\\*"))
    #expect(readme.contains("\\#重要"))
    #expect(!readme.contains("file://"))
}

@Test("工作区 PDF 每张有效贴图生成一页且无效图片可跳过")
func pinWorkspaceExporterPDFAndPartialFailure() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceExporter-\(UUID())")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: root) }

    let plan = PinWorkspaceExportPlan(
        workspace: exporterWorkspace(name: "PDF"),
        items: [
            PinWorkspaceExportItem(
                ordinal: 1,
                pngData: try exporterPNG(color: .green, size: CGSize(width: 40, height: 20)),
                metadata: .empty
            ),
            PinWorkspaceExportItem(ordinal: 2, pngData: Data("invalid".utf8), metadata: .empty)
        ],
        skippedPinCount: 0
    )

    let report = try PinWorkspaceExporter(fileManager: fileManager).export(plan, to: root, format: .pdf)
    #expect(report.exportedPinCount == 1)
    #expect(report.failedEncodingPinCount == 1)
    #expect(report.destinationURL.pathExtension == "pdf")
    let document = try #require(CGPDFDocument(report.destinationURL as CFURL))
    #expect(document.numberOfPages == 1)
    let page = try #require(document.page(at: 1))
    let mediaBox = page.getBoxRect(.mediaBox)
    #expect(abs((mediaBox.width / mediaBox.height) - 2) < 0.001)
    let hiddenTemporaryItems = try fileManager.contentsOfDirectory(atPath: root.path)
        .filter { $0.hasPrefix(".PinboardShot-export-") }
    #expect(hiddenTemporaryItems.isEmpty)
}

@Test("工作区导出在全部图片无效时不提交最终目标")
func pinWorkspaceExporterRejectsAllInvalidImages() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("PinWorkspaceExporter-\(UUID())")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: root) }
    let plan = PinWorkspaceExportPlan(
        workspace: exporterWorkspace(name: "无效"),
        items: [PinWorkspaceExportItem(ordinal: 1, pngData: Data(), metadata: .empty)],
        skippedPinCount: 0
    )

    #expect(throws: PinWorkspaceExporterError.noExportablePins) {
        try PinWorkspaceExporter(fileManager: fileManager).export(plan, to: root, format: .images)
    }
    #expect(try fileManager.contentsOfDirectory(atPath: root.path).isEmpty)
}
