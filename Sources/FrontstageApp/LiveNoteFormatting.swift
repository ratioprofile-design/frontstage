#if os(macOS)
import AppKit
@MainActor enum LiveNoteFormatting {
    static func apply(to text: NSTextView) {
        guard !text.hasMarkedText(), text.selectedRange().length == 0, let storage = text.textStorage, storage.length > 0 else { return }
        let caret = min(text.selectedRange().location, storage.length), lineRange = (text.string as NSString).paragraphRange(for: NSRange(location: caret, length: 0))
        let line = (text.string as NSString).substring(with: lineRange).trimmingCharacters(in: .newlines)
        let markers: [(String, String, CGFloat)] = [("### ", "", 16), ("## ", "", 19), ("# ", "", 23), ("> ", "❯ ", 13), ("- ", "• ", 13), ("* ", "• ", 13), ("1. ", "1. ", 13), ("[] ", "☐ ", 13), ("[ ] ", "☐ ", 13), ("---", "────────", 13), ("```", "", 13)]
        if let marker = markers.first(where: { $0.0 == line && $0.0 != $0.1 }) {
            var attributes: [NSAttributedString.Key: Any] = [.font: marker.0.hasPrefix("#") ? NSFont.boldSystemFont(ofSize: marker.2) : NSFont.systemFont(ofSize: marker.2)]
            attributes[NoteTextCodec.blockKey] = marker.0 == "# " ? "h1" : marker.0 == "## " ? "h2" : marker.0 == "### " ? "h3" : marker.0 == "> " ? "blockquote" : marker.0 == "```" ? "pre" : marker.0 == "---" ? "hr" : marker.1 == "• " ? "li" : "p"
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: line.utf16.count), with: NSAttributedString(string: marker.1, attributes: attributes))
            text.setSelectedRange(NSRange(location: lineRange.location + marker.1.utf16.count, length: 0)); text.typingAttributes = attributes; return
        }
        let before = (text.string as NSString).substring(with: NSRange(location: lineRange.location, length: max(0, caret - lineRange.location)))
        let patterns: [(String, String)] = [("\\*\\*([^*]+)\\*\\*$", "bold"), ("~~([^~]+)~~$", "strike"), ("`([^`]+)`$", "code"), ("(?<!\\*)\\*([^*]+)\\*$", "italic")]
        for (pattern, style) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: before, range: NSRange(location: 0, length: before.utf16.count)) else { continue }
            let value = (before as NSString).substring(with: match.range(at: 1)), range = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            var attributes = storage.attributes(at: range.location, effectiveRange: nil)
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 13)
            if style == "strike" { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            else if style == "code" { attributes[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) }
            else { attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: style == "bold" ? .boldFontMask : .italicFontMask) }
            storage.replaceCharacters(in: range, with: NSAttributedString(string: value, attributes: attributes)); text.setSelectedRange(NSRange(location: range.location + value.utf16.count, length: 0)); return
        }
    }
}
#endif
