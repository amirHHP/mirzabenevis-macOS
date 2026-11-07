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
        let pageWidth: CGFloat = 595.28  // A4
        let pageHeight: CGFloat = 841.89 // A4
        let margin: CGFloat = 46
        let contentWidth = pageWidth - margin * 2

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfCreationFailed
        }

        let isRTL = LanguageManager.shared.currentLanguage == .persian

        let baseParagraphStyle = NSMutableParagraphStyle()
        baseParagraphStyle.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
        baseParagraphStyle.alignment = isRTL ? .right : .left
        baseParagraphStyle.lineSpacing = 4

        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center

        var currentPage = 0
        var y: CGFloat = 0

        func drawFooter(page: Int) {
            let footerText = isRTL ? "صفحه \(page)" : "Page \(page)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: centerStyle
            ]
            let rect = CGRect(x: margin, y: margin - 22, width: contentWidth, height: 16)
            (footerText as NSString).draw(in: rect, withAttributes: attrs)
        }

        func drawRunningHeader() {
            let headerText = "\(session.title) — Mirza Benevis"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: baseParagraphStyle
            ]
            let rect = CGRect(x: margin, y: pageHeight - margin + 8, width: contentWidth, height: 16)
            (headerText as NSString).draw(in: rect, withAttributes: attrs)

            // Header line
            context.saveGState()
            context.setStrokeColor(NSColor.separatorColor.cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: pageHeight - margin + 4))
            context.addLine(to: CGPoint(x: pageWidth - margin, y: pageHeight - margin + 4))
            context.strokePath()
            context.restoreGState()
        }

        func startNewPage() {
            if currentPage > 0 {
                drawFooter(page: currentPage)
                context.endPDFPage()
            }
            currentPage += 1
            context.beginPDFPage(nil)
            y = pageHeight - margin

            if currentPage > 1 {
                drawRunningHeader()
                y -= 20
            }
        }

        func drawDivider() {
            if y - 16 < margin + 30 {
                startNewPage()
            }
            y -= 8
            context.saveGState()
            context.setStrokeColor(NSColor.separatorColor.cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: y))
            context.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            context.strokePath()
            context.restoreGState()
            y -= 12
        }

        func drawText(
            _ text: String,
            font: NSFont,
            color: NSColor = .textColor,
            spacingAfter: CGFloat = 8,
            forceNewPageIfNeeded: Bool = false
        ) {
            guard !text.isEmpty else { return }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: baseParagraphStyle
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)

            let boundingRect = attrStr.boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let blockHeight = ceil(boundingRect.height)

            if forceNewPageIfNeeded && (y - blockHeight < margin + 30) {
                startNewPage()
            } else if y - blockHeight < margin + 30 {
                // If text fits in a whole page, start new page
                if blockHeight <= (pageHeight - margin * 2 - 40) {
                    startNewPage()
                } else {
                    // Very long text: split by paragraphs / lines
                    let lines = text.components(separatedBy: "\n")
                    for line in lines {
                        drawText(line, font: font, color: color, spacingAfter: 4, forceNewPageIfNeeded: true)
                    }
                    return
                }
            }

            let drawRect = CGRect(x: margin, y: y - blockHeight, width: contentWidth, height: blockHeight)
            attrStr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            y -= (blockHeight + spacingAfter)
        }

        // --- Begin document ---
        startNewPage()

        // Document Title
        drawText(session.title, font: NSFont.boldSystemFont(ofSize: 20), color: .textColor, spacingAfter: 6)

        // Metadata subtitle
        let meta = "\(session.createdAt.formatted()) | \(session.wordCount) \(isRTL ? "کلمه" : "words")\(session.calendarEventTitle.map { isRTL ? " | رویداد: \($0)" : " | Event: \($0)" } ?? "")"
        drawText(meta, font: NSFont.systemFont(ofSize: 10), color: .secondaryLabelColor, spacingAfter: 12)

        drawDivider()

        // 1. Summary Section (if present)
        if let summary = session.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let summaryTitle = isRTL ? "خلاصه هوشمند جلسه" : "Meeting Summary"
            drawText(summaryTitle, font: NSFont.boldSystemFont(ofSize: 14), color: .systemIndigo, spacingAfter: 6, forceNewPageIfNeeded: true)
            drawText(summary, font: NSFont.systemFont(ofSize: 11), color: .textColor, spacingAfter: 12)
            drawDivider()
        }

        // 2. Action Items Section (if present)
        if !session.actionItems.isEmpty {
            let itemsTitle = isRTL ? "اقدامات بعدی و وظایف (Action Items)" : "Action Items & Next Steps"
            drawText(itemsTitle, font: NSFont.boldSystemFont(ofSize: 14), color: .systemGreen, spacingAfter: 8, forceNewPageIfNeeded: true)

            for item in session.actionItems {
                let check = item.isCompleted ? "[✓]" : "[ ]"
                let assignee = item.assignee.map { " (\($0))" } ?? ""
                let itemLine = "\(check) \(item.text)\(assignee)"
                let itemColor: NSColor = item.isCompleted ? .secondaryLabelColor : .textColor
                drawText(itemLine, font: NSFont.systemFont(ofSize: 11), color: itemColor, spacingAfter: 4, forceNewPageIfNeeded: false)
            }
            y -= 4
            drawDivider()
        }

        // 3. Transcript Section
        let transcriptTitle = isRTL ? "رونوشت کامل (گفتگو)" : "Full Transcript"
        drawText(transcriptTitle, font: NSFont.boldSystemFont(ofSize: 14), color: .systemBlue, spacingAfter: 10, forceNewPageIfNeeded: true)

        if !session.segments.isEmpty {
            for segment in session.segments {
                let speakerLabel = "[\(segment.speakerDisplayName)] (\(segment.formattedTime))"
                let speakerColor: NSColor = (segment.speaker == .user) ? .systemBlue : .systemPurple

                // Ensure speaker header and at least first line of text stay together
                if y - 45 < margin + 30 {
                    startNewPage()
                }

                drawText(speakerLabel, font: NSFont.boldSystemFont(ofSize: 11), color: speakerColor, spacingAfter: 2)
                drawText(segment.text, font: NSFont.systemFont(ofSize: 11), color: .textColor, spacingAfter: 10)
            }
        } else {
            let fallbackText = session.formattedDialogue.isEmpty ? "—" : session.formattedDialogue
            drawText(fallbackText, font: NSFont.systemFont(ofSize: 11), color: .textColor, spacingAfter: 10)
        }

        // Finalize last page
        drawFooter(page: currentPage)
        context.endPDFPage()
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
