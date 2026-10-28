#if os(macOS)
import AppKit
import FrontstageCore

extension NSAttributedString.Key {
    static let screenplayDualDialogue = NSAttributedString.Key("design.ratioprofile.frontstage.dualDialogue")
    static let screenplayDualPair = NSAttributedString.Key("design.ratioprofile.frontstage.dualPair")
    static let screenplayLegacyRevisionMark = NSAttributedString.Key("design.ratioprofile.frontstage.legacyRevisionMark")
    static let screenplayElement = NSAttributedString.Key("design.ratioprofile.frontstage.element")
}

@MainActor
enum ScreenplayTypography {
    static func attributes(_ element: ScreenplayElement, width: CGFloat,
                           printing: Bool = false, settings: ScriptLayoutSettings = .init()) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        let size = settings.effectiveFontSize(for: element)
        paragraph.minimumLineHeight = max(settings.isTamil(for: element) ? size * 1.45 : size, settings.lineHeight)
        paragraph.maximumLineHeight = max(settings.isTamil(for: element) ? size * 1.45 : size, settings.lineHeight)
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
        let base = NSFont(name: settings.effectiveFontName(for: element), size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        let font: NSFont
        if settings.isBold(for: element) {
            font = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        } else { font = base }
        let styled = settings.isItalic(for: element) ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
        return [.font: styled, .underlineStyle: settings.isUnderline(for: element) ? NSUnderlineStyle.single.rawValue : 0, .paragraphStyle: paragraph,
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
    struct BlockMeta {
        let type: ScreenplayElement
        let dual: String?
        let revised: Bool
        let pair: String?
    }

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
        var events: [(Int, BlockMeta)] = []
        var removed = 0
        for match in matches {
            let key = (text.string as NSString).substring(with: match.range(at: 1))
            if let index = Int(key), marked.metas.indices.contains(index) {
                events.append((match.range.location - removed, marked.metas[index]))
            }
            removed += match.range.length
        }
        for match in matches.reversed() { text.deleteCharacters(in: match.range) }
        text.addAttribute(.screenplayElement, value: ScreenplayElement.action.rawValue,
                          range: NSRange(location: 0, length: text.length))
        for (index, event) in events.enumerated() {
            let end = index + 1 < events.count ? events[index + 1].0 : text.length
            if end > event.0 {
                let range = NSRange(location: event.0, length: end - event.0)
                text.addAttribute(.screenplayElement, value: event.1.type.rawValue, range: range)
                if let side = event.1.dual { text.addAttribute(.screenplayDualDialogue, value: side, range: range) }
                if let pair = event.1.pair { text.addAttribute(.screenplayDualPair, value: pair, range: range) }
                if event.1.revised { text.addAttribute(.screenplayLegacyRevisionMark, value: true, range: range) }
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
            let side = text.attribute(.screenplayDualDialogue, at: paragraph.location, effectiveRange: nil) as? String
            let dualClass = ["left", "right"].contains(side ?? "") ? " sc-dual-\(side!)" : ""
            let revised = text.attribute(.screenplayLegacyRevisionMark, at: paragraph.location, effectiveRange: nil) as? Bool == true ? " sc-rev" : ""
            let pair = text.attribute(.screenplayDualPair, at: paragraph.location, effectiveRange: nil) as? String
            let pairAttribute = pair.map { " data-dual-pair=\"\(escape($0))\"" } ?? ""
            blocks.append("<div class=\"sc-line sc-\(type.rawValue)\(dualClass)\(revised)\"\(pairAttribute)>\(inner.isEmpty ? "<br>" : inner)</div>")
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

    private static func markLeafBlocks(_ html: String, token: String) -> (html: String, metas: [BlockMeta]) {
        guard let tags = try? NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<(?:"[^"]*"|'[^']*'|[^'">])*>"#),
              let names = try? NSRegularExpression(pattern: #"^<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)"#),
              let classes = try? NSRegularExpression(pattern: #"\sclass\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
                                                    options: .caseInsensitive) else { return (html, []) }
        let source = html as NSString
        let blockTags: Set<String> = ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote"]
        let voidTags: Set<String> = ["br", "hr", "img", "input", "meta", "link", "wbr", "source", "area", "base", "embed", "param", "col", "track"]
        var stack: [(name: String, meta: BlockMeta, block: Int?)] = []
        var blocks: [(position: Int, meta: BlockMeta, hasChild: Bool)] = []
        for match in tags.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let tag = source.substring(with: match.range) as NSString
            guard let nameMatch = names.firstMatch(in: tag as String, range: NSRange(location: 0, length: tag.length)) else { continue }
            let name = tag.substring(with: nameMatch.range(at: 2)).lowercased()
            if nameMatch.range(at: 1).length > 0 {
                if let index = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(index...) }
                continue
            }
            var type = stack.last?.meta.type ?? .action
            var dual: String? = stack.last?.meta.dual
            var pair: String? = stack.last?.meta.pair
            if let expression = try? NSRegularExpression(pattern: #"\sdata-dual-pair\s*=\s*["']([A-Za-z0-9_-]{1,120})["']"#), let match = expression.firstMatch(in: tag as String, range: NSRange(location: 0, length: tag.length)) { pair = tag.substring(with: match.range(at: 1)) }
            var rev: Bool = stack.last?.meta.revised ?? false
            if let classMatch = classes.firstMatch(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let classText = (1...3).filter { classMatch.range(at: $0).location != NSNotFound }
                    .map { tag.substring(with: classMatch.range(at: $0)) }.joined()
                for word in classText.split(whereSeparator: { $0.isWhitespace }) {
                    if word.hasPrefix("sc-") {
                        if word == "sc-dual-left" { dual = "left" }
                        else if word == "sc-dual-right" { dual = "right" }
                        else if word == "sc-rev" { rev = true }
                        else if let explicit = ScreenplayElement(rawValue: String(word.dropFirst(3))) { type = explicit }
                    }
                }
            }
            var block: Int?
            let currentMeta = BlockMeta(type: type, dual: dual, revised: rev, pair: pair)
            if blockTags.contains(name), !stack.contains(where: { ["head", "style", "script"].contains($0.name) }) {
                if let parent = stack.last(where: { $0.block != nil })?.block { blocks[parent].hasChild = true }
                block = blocks.count
                blocks.append((NSMaxRange(match.range), currentMeta, false))
            }
            if !voidTags.contains(name), !((tag as String).hasSuffix("/>")) { stack.append((name, currentMeta, block)) }
        }
        let leaves = blocks.filter { !$0.hasChild }
        let output = NSMutableString(string: html)
        for (index, block) in leaves.enumerated().reversed() {
            output.insert("\(token)\(index)END", at: block.position)
        }
        return (output as String, leaves.map(\.meta))
    }
}
#endif
