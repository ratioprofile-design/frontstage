import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension ScreenplayInterchange {
    public static func parseFDX(_ data: Data) throws -> [ScreenplayExportParagraph] {
        guard data.count <= 32 * 1024 * 1024 else { throw ProjectError.invalidProject("The script exceeds the 32 MB import limit") }
        let delegate = FDXScriptParser(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), delegate.isScript else { throw ProjectError.invalidProject("The document is not a readable Final Draft script") }
        _ = try fdx(delegate.paragraphs)
        return delegate.paragraphs
    }
    public static func parseFountain(_ source: String) throws -> [ScreenplayExportParagraph] {
        guard source.utf8.count <= 32 * 1024 * 1024 else { throw ProjectError.invalidProject("The script exceeds the 32 MB import limit") }
        var paragraphs = [ScreenplayExportParagraph](), speech = false, pairCues = [Int](), scene = 0, scenes = [String](), shot = false
        for raw in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { speech = false; continue }
            if line == "/* DOT element: shot */" { shot = true; continue }
            var element = ScreenplayElement.action, content = line, number: String?, dual = false
            if line.hasPrefix(".") || line.range(of: #"^(?:INT\.|EXT\.|INT\./EXT\.|EXT\./INT\.|I/E\.)\s"#, options: [.regularExpression, .caseInsensitive]) != nil {
                element = .sceneHeading; scene += 1; speech = false
                if line.hasPrefix(".") { content.removeFirst() }
                if let match = content.range(of: #"\s+#([^#]+)#$"#, options: .regularExpression) {
                    number = String(content[match]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                    content.removeSubrange(match)
                }
            } else if line.hasPrefix("@") {
                element = .character; content.removeFirst(); speech = true
                if content.hasSuffix(" ^") { content.removeLast(2); dual = true }
            } else if line.hasPrefix("!") { element = shot ? .shot : .action; content.removeFirst(); speech = false; shot = false }
            else if line.hasPrefix(">") { element = .transition; content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces); speech = false }
            else if line.hasPrefix("~") { element = .lyrics; content.removeFirst() }
            else if speech && line.hasPrefix("(") { element = .parenthetical }
            else if speech { element = .dialogue }
            else if line == line.uppercased(), !line.contains("."), line.count < 100 {
                element = .character; speech = true
                if content.hasSuffix(" ^") { content.removeLast(2); dual = true }
            }
            if dual { pairCues.append(paragraphs.count) }
            paragraphs.append(.init(element: element, runs: fountainRuns(content), number: number)); scenes.append(String(scene))
        }
        let lines = paragraphs.enumerated().map { DualDialogueLine(element: $0.element.element, text: $0.element.text, scene: scenes[$0.offset]) }
        for cue in pairCues {
            let plan = try DualDialogueRules.pair(in: lines, at: cue), id = UUID().uuidString
            for (range, side) in [(plan.left, "left"), (plan.right, "right")] {
                for i in range { guard paragraphs[i].dualPair == nil else { throw ProjectError.invalidProject("Ambiguous Fountain dual dialogue") }; paragraphs[i].dualPair = id; paragraphs[i].dualSide = side }
            }
        }
        return paragraphs
    }
    private static func fountainRuns(_ source: String) -> [ScreenplayExportRun] {
        let text = Array(source); var i = 0, bold = false, italic = false, underline = false, value = "", runs = [ScreenplayExportRun]()
        func flush() { if !value.isEmpty { runs.append(.init(value, bold: bold, italic: italic, underline: underline)); value = "" } }
        while i < text.count {
            if text[i] == "\\", i + 1 < text.count { value.append(text[i + 1]); i += 2; continue }
            if text[i] == "_" { flush(); underline.toggle(); i += 1; continue }
            if text[i] == "*" { flush(); if i + 1 < text.count && text[i + 1] == "*" { bold.toggle(); i += 2 } else { italic.toggle(); i += 1 }; continue }
            value.append(text[i]); i += 1
        }
        flush(); return runs
    }
}

private final class FDXScriptParser: NSObject, XMLParserDelegate {
    struct Paragraph { var value: ScreenplayExportParagraph; var wrapper = false }
    var paragraphs = [ScreenplayExportParagraph]()
    var isScript = false
    private var stack = [Paragraph]()
    private var dual: String?, right = false, cues = 0, text = "", style = "", inText = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "FinalDraft" { isScript = attributes["DocumentType"] == "Script" }
        if name == "DualDialogue" { if !stack.isEmpty { stack[stack.count - 1].wrapper = true }; dual = UUID().uuidString; cues = 0; right = false }
        if name == "Paragraph" {
            let type = attributes["Type"] == "Scene Heading" ? "slugline" : (attributes["Type"] ?? "Action").lowercased()
            let element = ScreenplayElement(rawValue: type) ?? .action
            if dual != nil && element == .character { cues += 1; right = cues > 1 }
            stack.append(Paragraph(value: .init(element: element, runs: [], number: attributes["Number"], dualPair: dual, dualSide: dual == nil ? nil : right ? "right" : "left")))
        }
        if name == "SceneProperties", let number = attributes["Number"], !stack.isEmpty { stack[stack.count - 1].value.number = number }
        if name == "Text" { inText = true; text = ""; style = attributes["Style"] ?? "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { text += string } }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { if inText { text += String(data: data, encoding: .utf8) ?? "" } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "Text" { if !stack.isEmpty { stack[stack.count - 1].value.runs.append(.init(text, bold: style.contains("Bold"), italic: style.contains("Italic"), underline: style.contains("Underline"))) }; inText = false }
        if name == "Paragraph", let value = stack.popLast(), !value.wrapper { paragraphs.append(value.value) }
        if name == "DualDialogue" { dual = nil; cues = 0 }
    }
}
