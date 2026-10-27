#if os(macOS)
import AppKit
import FrontstageCore

extension NSAttributedString.Key {
    static let screenplayElement = NSAttributedString.Key("design.ratioprofile.frontstage.element")
}

@MainActor
enum ScreenplayTypography {
    static func attributes(_ element: ScreenplayElement, width: CGFloat,
                           printing: Bool = false, settings: ScriptLayoutSettings = .init()) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = settings.lineHeight
        paragraph.maximumLineHeight = settings.lineHeight
        paragraph.paragraphSpacing = settings.paragraphSpacing
        switch element {
        case .character:
            paragraph.headIndent = width * WorkspaceDesign.characterIndent / 100
            paragraph.tailIndent = 0
            paragraph.paragraphSpacing = 0
        case .dialogue:
            paragraph.headIndent = width * WorkspaceDesign.dialogueIndent / 100
            paragraph.tailIndent = -width * WorkspaceDesign.dialogueIndent / 100
        case .parenthetical:
            paragraph.headIndent = width * WorkspaceDesign.parentheticalIndent / 100
            paragraph.tailIndent = -width * WorkspaceDesign.parentheticalRight / 100
            paragraph.paragraphSpacing = 0
        case .transition:
            paragraph.headIndent = width * 0.55
            paragraph.alignment = .right
            paragraph.paragraphSpacingBefore = 10
        case .sceneHeading, .shot:
            paragraph.paragraphSpacingBefore = 10
        default: break
        }
        paragraph.firstLineHeadIndent = paragraph.headIndent
        let base = NSFont(name: settings.fontName, size: settings.fontSize) ?? .monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        let font: NSFont
        if [.sceneHeading, .transition, .shot].contains(element) {
            font = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        } else { font = base }
        return [.font: font, .paragraphStyle: paragraph,
                .foregroundColor: printing ? NSColor.black : NSColor.textColor,
                .screenplayElement: element.rawValue]
    }

    static func apply(_ element: ScreenplayElement, to text: NSMutableAttributedString,
                      range: NSRange, width: CGFloat, printing: Bool = false, settings: ScriptLayoutSettings = .init()) {
        guard range.length > 0 else { return }
        let attributes = attributes(element, width: width, printing: printing, settings: settings)
        // Retain inline emphasis while normalizing the screenplay font and paragraph geometry.
        var fonts: [(NSRange, NSFontTraitMask)] = []
        text.enumerateAttribute(.font, in: range) { value, run, _ in
            if let font = value as? NSFont { fonts.append((run, NSFontManager.shared.traits(of: font))) }
        }
        text.addAttributes(attributes, range: range)
        let base = attributes[.font] as! NSFont
        for (run, traits) in fonts {
            let emphasis = traits.intersection([.boldFontMask, .italicFontMask])
            if !emphasis.isEmpty {
                text.addAttribute(.font, value: NSFontManager.shared.convert(base, toHaveTrait: emphasis), range: run)
            }
        }
    }
}

/// AppKit renders HTML; temporary markers carry Backstage paragraph classes through its importer.
/// Mark only leaf blocks so a wrapper around multiple paragraphs never creates spurious blank lines.
@MainActor
enum ScreenplayTextCodec {
    static func decode(_ html: String, width: CGFloat = 432,
                       printing: Bool = false, settings: ScriptLayoutSettings = .init()) throws -> NSMutableAttributedString {
        let token = "FS\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))_"
        let marked = markLeafBlocks(html, token: token)
        let text = try NSMutableAttributedString(data: Data(marked.html.utf8), options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ], documentAttributes: nil)
        let regex = try NSRegularExpression(pattern: "\(token)([0-9]+)END")
        let matches = regex.matches(in: text.string, range: NSRange(location: 0, length: text.length))
        var events: [(Int, ScreenplayElement)] = []
        var removed = 0
        for match in matches {
            let key = (text.string as NSString).substring(with: match.range(at: 1))
            if let index = Int(key), marked.types.indices.contains(index) {
                events.append((match.range.location - removed, marked.types[index]))
            }
            removed += match.range.length
        }
        for match in matches.reversed() { text.deleteCharacters(in: match.range) }
        text.addAttribute(.screenplayElement, value: ScreenplayElement.action.rawValue,
                          range: NSRange(location: 0, length: text.length))
        for (index, event) in events.enumerated() {
            let end = index + 1 < events.count ? events[index + 1].0 : text.length
            if end > event.0 {
                text.addAttribute(.screenplayElement, value: event.1.rawValue,
                                  range: NSRange(location: event.0, length: end - event.0))
            }
        }
        var location = 0
        while location < text.length {
            let range = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            let element = element(in: text, at: location)
            ScreenplayTypography.apply(element, to: text, range: range, width: width, printing: printing, settings: settings)
            location = NSMaxRange(range)
        }
        return text
    }

    static func element(in text: NSAttributedString, at location: Int) -> ScreenplayElement {
        guard text.length > 0 else { return .action }
        return (text.attribute(.screenplayElement, at: min(max(0, location), text.length - 1),
                               effectiveRange: nil) as? String).flatMap(ScreenplayElement.init(rawValue:)) ?? .action
    }

    static func encode(_ text: NSAttributedString) -> String {
        guard text.length > 0 else { return "<div class=\"sc-line sc-action\"><br></div>" }
        let source = text.string as NSString
        var location = 0
        var blocks: [String] = []
        while location < text.length {
            let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
            var end = NSMaxRange(paragraph)
            while end > paragraph.location && [10, 13, 0x2028, 0x2029].contains(source.character(at: end - 1)) { end -= 1 }
            let range = NSRange(location: paragraph.location, length: end - paragraph.location)
            var inner = ""
            text.enumerateAttributes(in: range) { attributes, run, _ in
                var value = escape(source.substring(with: run))
                if let font = attributes[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    if traits.contains(.boldFontMask) { value = "<b>\(value)</b>" }
                    if traits.contains(.italicFontMask) { value = "<i>\(value)</i>" }
                }
                if let underline = attributes[.underlineStyle] as? Int, underline != 0 { value = "<u>\(value)</u>" }
                inner += value
            }
            let type = element(in: text, at: paragraph.location)
            blocks.append("<div class=\"sc-line sc-\(type.rawValue)\">\(inner.isEmpty ? "<br>" : inner)</div>")
            location = NSMaxRange(paragraph)
        }
        return blocks.joined()
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\t", with: "&#9;")
    }

    private static func markLeafBlocks(_ html: String, token: String) -> (html: String, types: [ScreenplayElement]) {
        // This scanner only transports paragraph metadata. AppKit handles HTML parsing and entities.
        guard let tags = try? NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<(?:"[^"]*"|'[^']*'|[^'">])*>"#),
              let names = try? NSRegularExpression(pattern: #"^<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)"#),
              let classes = try? NSRegularExpression(pattern: #"\sclass\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
                                                    options: .caseInsensitive) else { return (html, []) }
        let source = html as NSString
        let blockTags: Set<String> = ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote"]
        let voidTags: Set<String> = ["br", "hr", "img", "input", "meta", "link", "wbr", "source", "area", "base", "embed", "param", "col", "track"]
        var stack: [(name: String, type: ScreenplayElement, block: Int?)] = []
        var blocks: [(position: Int, type: ScreenplayElement, hasChild: Bool)] = []
        for match in tags.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let tag = source.substring(with: match.range) as NSString
            guard let nameMatch = names.firstMatch(in: tag as String, range: NSRange(location: 0, length: tag.length)) else { continue }
            let name = tag.substring(with: nameMatch.range(at: 2)).lowercased()
            if nameMatch.range(at: 1).length > 0 {
                if let index = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(index...) }
                continue
            }
            var type = stack.last?.type ?? .action
            if let classMatch = classes.firstMatch(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let classText = (1...3).filter { classMatch.range(at: $0).location != NSNotFound }
                    .map { tag.substring(with: classMatch.range(at: $0)) }.joined()
                for word in classText.split(whereSeparator: { $0.isWhitespace }) where word.hasPrefix("sc-") {
                    if let explicit = ScreenplayElement(rawValue: String(word.dropFirst(3))) { type = explicit }
                }
            }
            var block: Int?
            if blockTags.contains(name), !stack.contains(where: { ["head", "style", "script"].contains($0.name) }) {
                if let parent = stack.last(where: { $0.block != nil })?.block { blocks[parent].hasChild = true }
                block = blocks.count
                blocks.append((NSMaxRange(match.range), type, false))
            }
            if !voidTags.contains(name), !((tag as String).hasSuffix("/>")) { stack.append((name, type, block)) }
        }
        let leaves = blocks.filter { !$0.hasChild }
        let output = NSMutableString(string: html)
        for (index, block) in leaves.enumerated().reversed() {
            output.insert("\(token)\(index)END", at: block.position)
        }
        return (output as String, leaves.map(\.type))
    }
}
#endif
