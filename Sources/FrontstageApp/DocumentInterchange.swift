#if os(macOS)
import AppKit
import FrontstageCore
import PDFKit
import UniformTypeIdentifiers

@MainActor
enum ScreenplayDOCX {
    static func render(_ project: Project, paper: ScreenplayPaper = .letter) throws -> Data {
        _ = try ScreenplayInterchange.fdx(ScreenplayInterchangeDocument.paragraphs(project))
        let xml = OfficeArchive.xml
        var paragraphs = ""
        for segment in try project.orderedScript() {
            let scene = segment.scene
            paragraphs += paragraph("\(segment.number)  \(scene.heading.text)\(segment.isContinuation ? " (CONTINUED)" : "")", element: .sceneHeading, newPage: scene.startsNewPage)
            let text = DialoguePresentation.materialized(try ScreenplayTextCodec.decode(scene.html, settings: project.scriptLayout)), source = text.string as NSString
            var offset = 0
            var bodyParagraphs = [(xml: String, pair: String?, side: String?)]()
            while offset < text.length {
                let range = source.paragraphRange(for: NSRange(location: offset, length: 0))
                let element = ScreenplayTextCodec.element(in: text, at: offset)
                var runs = ""
                text.enumerateAttributes(in: range) { attributes, range, _ in
                    let value = source.substring(with: range).trimmingCharacters(in: .newlines)
                    let traits = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
                    let properties = (traits.contains(.boldFontMask) ? "<w:b/>" : "") + (traits.contains(.italicFontMask) ? "<w:i/>" : "") + ((attributes[.underlineStyle] as? Int ?? 0) > 0 ? "<w:u w:val=\"single\"/>" : "")
                    let font = project.scriptLayout.effectiveFontName(for: element), size = project.scriptLayout.effectiveFontSize(for: element)
                    runs += "<w:r><w:rPr><w:rFonts w:ascii=\"\(xml(font))\" w:hAnsi=\"\(xml(font))\" w:cs=\"\(xml(font))\"/><w:sz w:val=\"\(Int(size * 2))\"/>\(properties)</w:rPr><w:t xml:space=\"preserve\">\(xml(value))</w:t></w:r>"
                }
                let pair = text.attribute(.screenplayDualPair, at: offset, effectiveRange: nil) as? String
                let side = text.attribute(.screenplayDualDialogue, at: offset, effectiveRange: nil) as? String
                var geometry = ""
                if pair != nil {
                    let left = Int(paper.contentWidth * 10 * (element == .character ? WorkspaceDesign.characterIndent : element == .dialogue ? WorkspaceDesign.dialogueIndent : element == .parenthetical ? WorkspaceDesign.parentheticalIndent : 0) / 100)
                    let right = Int(paper.contentWidth * 10 * (element == .dialogue ? WorkspaceDesign.dialogueIndent : element == .parenthetical ? WorkspaceDesign.parentheticalRight : 0) / 100)
                    geometry = "<w:ind w:left=\"\(left)\" w:right=\"\(right)\"/>"
                }
                bodyParagraphs.append(("<w:p><w:pPr><w:pStyle w:val=\"\(element.rawValue)\"/>\(geometry)</w:pPr>\(runs)</w:p>", pair, side))
                offset = NSMaxRange(range)
            }
            var index = 0
            while index < bodyParagraphs.count {
                let item = bodyParagraphs[index]
                if let pair = item.pair {
                    var end = index + 1
                    while end < bodyParagraphs.count && bodyParagraphs[end].pair == pair { end += 1 }
                    let values = bodyParagraphs[index..<end]
                    let width = Int(paper.contentWidth * 10)
                    func cell(_ side: String) -> String { "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/><w:vAlign w:val=\"top\"/></w:tcPr>" + values.filter { $0.side == side }.map(\.xml).joined() + "</w:tc>" }
                    paragraphs += "<w:tbl><w:tblPr><w:tblLayout w:type=\"fixed\"/><w:tblW w:w=\"\(width * 2)\" w:type=\"dxa\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"\(width)\"/><w:gridCol w:w=\"\(width)\"/></w:tblGrid><w:tr>" + cell("left") + cell("right") + "</w:tr></w:tbl><w:p/>"
                    index = end
                } else { paragraphs += item.xml; index += 1 }
            }
        }
        let namespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let document = "<w:document xmlns:w=\"\(namespace)\"><w:body>\(paragraphs)<w:sectPr><w:pgSz w:w=\"\(Int(paper.width * 20))\" w:h=\"\(Int(paper.height * 20))\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"2160\"/></w:sectPr></w:body></w:document>"
        var styles = "<w:styles xmlns:w=\"\(namespace)\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"\(xml(project.scriptLayout.fontName))\" w:hAnsi=\"\(xml(project.scriptLayout.fontName))\"/><w:sz w:val=\"\(Int(project.scriptLayout.fontSize * 2))\"/></w:rPr></w:rPrDefault></w:docDefaults>"
        for type in ScreenplayElement.allCases {
            let indent = Int(paper.contentWidth * 20 * (type == .character ? WorkspaceDesign.characterIndent : type == .dialogue ? WorkspaceDesign.dialogueIndent : type == .parenthetical ? WorkspaceDesign.parentheticalIndent : 0) / 100)
            let right = Int(paper.contentWidth * 20 * (type == .dialogue ? WorkspaceDesign.dialogueIndent : type == .parenthetical ? WorkspaceDesign.parentheticalRight : 0) / 100)
            styles += "<w:style w:type=\"paragraph\" w:styleId=\"\(type.rawValue)\"><w:name w:val=\"\(type.label)\"/><w:pPr><w:ind w:left=\"\(indent)\" w:right=\"\(right)\"/><w:spacing w:after=\"\(type == .character || type == .parenthetical ? 0 : 160)\"/>\(type.keepsWithNext ? "<w:keepNext/>" : "")</w:pPr></w:style>"
        }
        styles += "</w:styles>"
        return try OfficeArchive.zip([
            "[Content_Types].xml": Data("<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>".utf8),
            "_rels/.rels": Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>".utf8),
            "word/_rels/document.xml.rels": Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>".utf8),
            "word/document.xml": Data(document.utf8), "word/styles.xml": Data(styles.utf8)
        ])
    }
    private static func paragraph(_ text: String, element: ScreenplayElement, newPage: Bool = false) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"\(element.rawValue)\"/>\(newPage ? "<w:pageBreakBefore/>" : "")</w:pPr><w:r><w:t xml:space=\"preserve\">\(OfficeArchive.xml(text))</w:t></w:r></w:p>"
    }
}

extension Workspace {
    func importScriptDocument() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf, .rtf, .plainText, UTType(filenameExtension: "docx") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text: NSAttributedString
            if url.pathExtension.lowercased() == "pdf" {
                guard let document = PDFDocument(url: url), let value = document.string, !value.isEmpty else { throw ProjectError.invalidProject("this PDF has no extractable text; scanned pages require OCR") }
                text = NSAttributedString(string: value)
            } else if url.pathExtension.lowercased() == "txt" || url.pathExtension.lowercased() == "fountain" {
                text = NSAttributedString(string: try String(contentsOf: url, encoding: .utf8))
            } else if url.pathExtension.lowercased() == "docx" { text = try OfficeImport.docx(url) }
            else { text = try NSAttributedString(url: url, options: [:], documentAttributes: nil) }
            let html = ScreenplayTextCodec.encode(text)
            var id: String?
            edit("Import Script Document") { project in
                id = try project.addBoardBeat(title: url.deletingPathExtension().lastPathComponent)
                try project.updateBoardBeat(id!) { $0.html = html }
            }
            if let id { selectBoardBeat(id); mode = .board; popup.open(id, workspace: self) }
        } catch { errorMessage = error.localizedDescription }
    }
    func exportDOCX() {
        do { try saveOffice(try ScreenplayDOCX.render(project, paper: paper), ext: "docx", name: project.name) }
        catch { errorMessage = error.localizedDescription }
    }
    func exportScheduleXLSX() {
        do { try saveOffice(try OfficeArchive.spreadsheet(rows: OfficeArchive.parseCSV(project.scheduleCSV())), ext: "xlsx", name: project.name + " Schedule") }
        catch { errorMessage = error.localizedDescription }
    }
    private func saveOffice(_ data: Data, ext: String, name: String) throws {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]; panel.nameFieldStringValue = name.replacingOccurrences(of: "/", with: "-") + "." + ext
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try OfficeArchive.save(data, to: url, extension: ext)
    }
}
#endif
