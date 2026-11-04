import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case docx

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: return "PDF"
        case .docx: return "Word (DOCX)"
        }
    }

    var fileExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .docx: return UTType(filenameExtension: "docx") ?? .data
        }
    }
}

enum ExportService {
    enum ExportError: LocalizedError {
        case pdfCreationFailed
        case docxCreationFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .pdfCreationFailed: return "ساخت فایل PDF ناموفق بود"
            case .docxCreationFailed: return "ساخت فایل Word ناموفق بود"
            case .writeFailed: return "ذخیره فایل ناموفق بود"
            }
        }
    }

    @MainActor
    static func export(session: TranscriptionSession, format: ExportFormat) throws -> URL? {
        let data: Data
        switch format {
        case .pdf:
            data = try generatePDF(session: session)
        case .docx:
            data = try generateDOCX(session: session)
        }

        let panel = NSSavePanel()
        panel.title = "ذخیره رونوشت جلسه"
        panel.nameFieldStringValue = sanitizedFilename(session.title, ext: format.fileExtension)
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw ExportError.writeFailed
        }
    }

    static func generatePDF(session: TranscriptionSession) throws -> Data {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfCreationFailed
        }

        let rtlStyle = NSMutableParagraphStyle()
        rtlStyle.baseWritingDirection = .rightToLeft
        rtlStyle.alignment = .right
        rtlStyle.lineSpacing = 4

        let ltrStyle = NSMutableParagraphStyle()
        ltrStyle.lineSpacing = 4

        func drawPage(title: String, subtitle: String? = nil, body: String, isRTL: Bool = true) {
            context.beginPDFPage(nil)
            var y: CGFloat = pageHeight - margin

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .paragraphStyle: isRTL ? rtlStyle : ltrStyle
            ]
            let titleRect = CGRect(x: margin, y: y - 28, width: contentWidth, height: 28)
            (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)
            y -= 40

            if let subtitle {
                let metaAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: isRTL ? rtlStyle : ltrStyle
                ]
                (subtitle as NSString).draw(in: CGRect(x: margin, y: y - 16, width: contentWidth, height: 16), withAttributes: metaAttrs)
                y -= 26
            }

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .paragraphStyle: isRTL ? rtlStyle : ltrStyle
            ]

            let bodyHeight = max(50, y - margin)
            (body as NSString).draw(
                in: CGRect(x: margin, y: margin, width: contentWidth, height: bodyHeight),
                withAttributes: bodyAttrs
            )
            context.endPDFPage()
        }

        let meta = "\(session.createdAt.formatted()) | \(session.wordCount) کلمه\(session.calendarEventTitle.map { " | رویداد: \($0)" } ?? "")"

        // Page 1: Dialogue transcript
        let transcriptText = session.formattedDialogue.isEmpty ? "—" : session.formattedDialogue
        drawPage(title: session.title, subtitle: meta, body: transcriptText)

        // Page 2: Summary (if present)
        if let summary = session.summary, !summary.isEmpty {
            drawPage(title: "خلاصه هوشمند جلسه", subtitle: session.title, body: summary)
        }

        // Page 3: Action Items (if present)
        if !session.actionItems.isEmpty {
            let itemsText = session.actionItems.map { item in
                let check = item.isCompleted ? "[✓]" : "[ ]"
                let assignee = item.assignee.map { " (\($0))" } ?? ""
                return "\(check) \(item.text)\(assignee)"
            }.joined(separator: "\n\n")
            drawPage(title: "اقدامات بعدی و وظایف (Action Items)", subtitle: session.title, body: itemsText)
        }

        context.closePDF()
        return pdfData as Data
    }

    static func generateDOCX(session: TranscriptionSession) throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirza-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wordDir = tempDir.appendingPathComponent("word", isDirectory: true)
        let relsDir = tempDir.appendingPathComponent("_rels", isDirectory: true)
        let wordRelsDir = wordDir.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordRelsDir, withIntermediateDirectories: true)

        try docxContentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try docxRootRels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try docxDocumentRels.write(to: wordRelsDir.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)
        try buildDocumentXML(session: session).write(
            to: wordDir.appendingPathComponent("document.xml"),
            atomically: true,
            encoding: .utf8
        )

        let docxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).docx")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = tempDir
        process.arguments = ["-r", "-q", docxURL.path, "."]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExportError.docxCreationFailed
        }

        return try Data(contentsOf: docxURL)
    }

    private static func buildDocumentXML(session: TranscriptionSession) -> String {
        var paragraphs = [
            xmlParagraph(session.title, bold: true, size: 32),
            xmlParagraph("\(session.createdAt.formatted()) | \(session.wordCount) کلمه\(session.calendarEventTitle.map { " | رویداد: \($0)" } ?? "")", size: 20),
            xmlParagraph("")
        ]

        if let summary = session.summary, !summary.isEmpty {
            paragraphs.append(xmlParagraph("خلاصه هوشمند جلسه:", bold: true, size: 26))
            paragraphs.append(xmlParagraph(summary))
            paragraphs.append(xmlParagraph(""))
        }

        if !session.actionItems.isEmpty {
            paragraphs.append(xmlParagraph("اقدامات بعدی و وظایف:", bold: true, size: 26))
            for item in session.actionItems {
                let check = item.isCompleted ? "☑" : "☐"
                let assignee = item.assignee.map { " [\($0)]" } ?? ""
                paragraphs.append(xmlParagraph("\(check) \(item.text)\(assignee)"))
            }
            paragraphs.append(xmlParagraph(""))
        }

        paragraphs.append(xmlParagraph("رونوشت کامل (گفتگو):", bold: true, size: 26))

        if !session.segments.isEmpty {
            for segment in session.segments {
                let speakerLabel = "[\(segment.speakerDisplayName)] (\(segment.formattedTime))"
                paragraphs.append(xmlParagraph(speakerLabel, bold: true, size: 20))
                paragraphs.append(xmlParagraph(segment.text, size: 22))
            }
        } else {
            paragraphs.append(xmlParagraph(session.fullText.isEmpty ? "—" : session.fullText))
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(paragraphs.joined(separator: "\n"))
            <w:sectPr/>
          </w:body>
        </w:document>
        """
    }

    private static func xmlParagraph(_ text: String, bold: Bool = false, size: Int = 24) -> String {
        let escaped = xmlEscape(text)
        let boldTag = bold ? "<w:b/>" : ""
        return """
        <w:p>
          <w:pPr><w:jc w:val="right"/><w:bidi/></w:pPr>
          <w:r>
            <w:rPr>\(boldTag)<w:sz w:val="\(size)"/><w:rtl/></w:rPr>
            <w:t xml:space="preserve">\(escaped)</w:t>
          </w:r>
        </w:p>
        """
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func sanitizedFilename(_ title: String, ext: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "session" : cleaned
        return "\(base).\(ext)"
    }

    private static let docxContentTypes = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let docxRootRels = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private static let docxDocumentRels = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
    """
}
