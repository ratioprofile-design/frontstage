import Foundation

public struct ScreenplayExportRun: Codable, Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public init(_ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false) { self.text = text; self.bold = bold; self.italic = italic; self.underline = underline }
}
public struct ScreenplayExportParagraph: Codable, Equatable, Sendable {
    public var element: ScreenplayElement
    public var runs: [ScreenplayExportRun]
    public var number: String?
    public var dualPair: String?
    public var dualSide: String?
    public var text: String { runs.map(\.text).joined() }
    public init(element: ScreenplayElement, runs: [ScreenplayExportRun], number: String? = nil, dualPair: String? = nil, dualSide: String? = nil) { self.element = element; self.runs = runs; self.number = number; self.dualPair = dualPair; self.dualSide = dualSide }
}
public enum ScreenplayInterchange {
    private static func type(_ element: ScreenplayElement) -> String { element == .sceneHeading ? "Scene Heading" : element.rawValue.capitalized }
    public static func fdx(_ paragraphs: [ScreenplayExportParagraph]) throws -> String {
        func paragraph(_ p: ScreenplayExportParagraph) -> String {
            let number = p.number.map { " Number=\"\(OfficeArchive.xml($0))\"" } ?? ""
            let runs = p.runs.map { run in
                let style = [(run.bold ? "Bold" : nil), (run.italic ? "Italic" : nil), (run.underline ? "Underline" : nil)].compactMap { $0 }.joined(separator: "+")
                return "<Text\(style.isEmpty ? "" : " Style=\"\(style)\"")>\(OfficeArchive.xml(run.text))</Text>"
            }.joined()
            return "<Paragraph Type=\"\(type(p.element))\"\(number)>\(runs)</Paragraph>"
        }
        var result = "", index = 0
        while index < paragraphs.count {
            let p = paragraphs[index]
            if let pair = p.dualPair {
                var end = index + 1
                while end < paragraphs.count && paragraphs[end].dualPair == pair { end += 1 }
                let values = Array(paragraphs[index..<end])
                guard let right = values.firstIndex(where: { $0.dualSide == "right" }), values.prefix(right).allSatisfy({ $0.dualSide == "left" }), values.suffix(from: right).allSatisfy({ $0.dualSide == "right" }) else { throw ProjectError.invalidProject("Repair incomplete dual dialogue before exporting") }
                let plan = try DualDialogueRules.pair(in: values.map { .init(element: $0.element, text: $0.text, scene: pair) }, at: right)
                guard plan.left.lowerBound == 0, plan.right.upperBound == values.count else { throw ProjectError.invalidProject("Ambiguous dual dialogue cannot be exported") }
                result += "<Paragraph Type=\"General\"><DualDialogue>" + values.map(paragraph).joined() + "</DualDialogue></Paragraph>"
                index = end
            } else {
                // Unreviewed legacy sides have no stable pair identity; preserve them in the project,
                // and require review rather than exporting a misleading simultaneous exchange.
                guard p.dualSide == nil else { throw ProjectError.invalidProject("Review legacy dual dialogue before exporting") }
                result += paragraph(p); index += 1
            }
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"1\"><Content>\(result)</Content></FinalDraft>"
    }
    public static func fountain(_ paragraphs: [ScreenplayExportParagraph]) throws -> String {
        _ = try fdx(paragraphs) // The same pair validation applies to both export formats.
        var output = [String]()
        for (index, p) in paragraphs.enumerated() {
            var runs = p.runs
            if p.element == .parenthetical {
                if let first = runs.firstIndex(where: { !$0.text.isEmpty }), runs[first].text.hasPrefix("(") { runs[first].text.removeFirst() }
                if let last = runs.lastIndex(where: { !$0.text.isEmpty }), runs[last].text.hasSuffix(")") { runs[last].text.removeLast() }
            }
            let first = runs.firstIndex { !$0.text.isEmpty }
            let text = runs.enumerated().map { index, run in
                guard !run.text.isEmpty else { return "" }
                var text = run.text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "_", with: "\\_")
                if p.element == .dialogue, index == first, let character = run.text.first, "(.!@>~#=".contains(character) { text = "\\" + text }
                if run.underline { text = "_" + text + "_" }
                if run.italic { text = "*" + text + "*" }
                if run.bold { text = "**" + text + "**" }
                return text
            }.joined()
            switch p.element {
            case .sceneHeading: output += ["", "." + text + (p.number.map { " #\($0)#" } ?? ""), ""]
            case .character: output += ["", "@" + text + (p.dualSide == "right" ? " ^" : "")]
            case .parenthetical: output.append("(" + text + ")")
            case .dialogue:
                output.append(text)
                if index + 1 == paragraphs.count || ![.dialogue, .parenthetical].contains(paragraphs[index + 1].element) { output.append("") }
            case .transition: output += ["", "> " + text, ""]
            case .lyrics: output.append("~" + text)
            case .shot: output += ["", "/* DOT element: shot */", "!" + text, ""]
            case .action: output += ["", "!" + text, ""]
            }
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }
}
