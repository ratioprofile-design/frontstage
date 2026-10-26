#if os(macOS)
import AppKit
@MainActor enum NoteTextCodec {
    static let blockKey = NSAttributedString.Key("FrontstageNoteBlock")
    static func decode(_ safeHTML: String) throws -> NSMutableAttributedString {
        try NSMutableAttributedString(data: Data(("<html><body style='font-family:Helvetica;font-size:13px'>" + safeHTML + "</body></html>").utf8), options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
    }
    static func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    static func encode(_ text: NSAttributedString) -> String {
        let string = text.string as NSString; var offset = 0, html = ""
        while offset < text.length {
            let paragraph = string.paragraphRange(for: NSRange(location: offset, length: 0)); let attributes = text.attributes(at: offset, effectiveRange: nil)
            let line = string.substring(with: paragraph).trimmingCharacters(in: .newlines), font = attributes[.font] as? NSFont
            var kind = attributes[blockKey] as? String ?? ((font?.pointSize ?? 13) >= 23 ? "h1" : (font?.pointSize ?? 13) >= 19 ? "h2" : "p")
            var range = paragraph
            if line.hasPrefix("• ") { kind = "li"; range.location += 2; range.length -= 2 }
            var content = ""
            text.enumerateAttributes(in: range) { attributes, run, _ in
                var value = escape((text.string as NSString).substring(with: run).replacingOccurrences(of: "\n", with: ""))
                if let font = attributes[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    if traits.contains(.boldFontMask) { value = "<strong>\(value)</strong>" }; if traits.contains(.italicFontMask) { value = "<em>\(value)</em>" }
                }
                if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { value = "<s>\(value)</s>" }
                if let url = attributes[.link] as? URL, ["http", "https", "mailto"].contains(url.scheme ?? "") { value = "<a href=\"\(escape(url.absoluteString))\">\(value)</a>" }
                content += value
            }
            if kind == "hr" { html += "<hr>" }
            else if kind == "li" { html += "<ul><li>\(content)</li></ul>" }
            else { let tag = ["h1", "h2", "h3", "blockquote", "pre"].contains(kind) ? kind : "p"; html += "<\(tag)>\(content)</\(tag)>" }
            offset = NSMaxRange(paragraph)
        }
        return html
    }
}
#endif
