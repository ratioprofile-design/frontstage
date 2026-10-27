#if os(macOS)
import AppKit

@MainActor
enum ScriptCueNames {
    private static var cache = [String: [String]]()
    static func characters(in html: String) -> [String] {
        if let names = cache[html] { return names }
        guard let text = try? ScreenplayTextCodec.decode(html) else { return [] }
        var names = [String]()
        text.enumerateAttribute(.screenplayElement, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value as? String == "character" {
                names += (text.string as NSString).substring(with: range).components(separatedBy: .newlines).map { $0.replacingOccurrences(of: #"\s*\((?:CONT['’]D|V\.O\.|O\.S\.)\)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
            }
        }
        if cache.count > 256 { cache.removeAll() }; cache[html] = names
        return names
    }
    static func capitalize(in text: NSTextView) {
        guard let storage = text.textStorage, storage.length > 0, !text.hasMarkedText() else { return }
        let selected = text.selectedRange(), location = min(selected.location, storage.length - 1)
        guard ["character", "slugline", "transition"].contains(storage.attribute(.screenplayElement, at: location, effectiveRange: nil) as? String ?? "") else { return }
        let range = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        let original = (storage.string as NSString).substring(with: range), upper = original.uppercased()
        guard original != upper else { return }
        func mapped(_ position: Int) -> Int {
            if position <= range.location { return position }
            if position >= NSMaxRange(range) { return position + upper.utf16.count - original.utf16.count }
            return range.location + (original as NSString).substring(to: position - range.location).uppercased().utf16.count
        }
        let start = mapped(selected.location), end = mapped(NSMaxRange(selected)), affinity = text.selectionAffinity
        storage.replaceCharacters(in: range, with: upper)
        text.setSelectedRange(NSRange(location: start, length: max(0, end - start)), affinity: affinity, stillSelecting: false)
    }
}
#endif
