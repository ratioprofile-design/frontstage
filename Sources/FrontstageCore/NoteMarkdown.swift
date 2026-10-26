import Foundation
public enum NoteMarkdown {
    /// A compatibility source representation; the visible editor always displays formatted blocks.
    public static func source(fromHTML html: String) -> String {
        var text = html
        let pairs = [("(?is)<(?:strong|b)\\b[^>]*>(.*?)</(?:strong|b)>", "**$1**"),
                     ("(?is)<(?:em|i)\\b[^>]*>(.*?)</(?:em|i)>", "*$1*"),
                     ("(?is)<(?:s|del)\\b[^>]*>(.*?)</(?:s|del)>", "~~$1~~"),
                     ("(?is)<code\\b[^>]*>(.*?)</code>", "`$1`"),
                     ("(?is)<h1\\b[^>]*>(.*?)</h1>", "# $1\n"),
                     ("(?is)<h2\\b[^>]*>(.*?)</h2>", "## $1\n"),
                     ("(?is)<h3\\b[^>]*>(.*?)</h3>", "### $1\n"),
                     ("(?is)<li\\b[^>]*>(.*?)</li>", "- $1\n"),
                     ("(?is)<blockquote\\b[^>]*>(.*?)</blockquote>", "> $1\n"),
                     ("(?i)<br\\s*/?>|</(?:p|div|pre)>", "\n"), ("<[^>]*>", "")]
        for (pattern, replacement) in pairs { text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression) }
        return text.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "☐ ", with: "- [ ] ").replacingOccurrences(of: "☑ ", with: "- [x] ").trimmingCharacters(in: .newlines)
    }
}
