#if os(macOS)
import AppKit
import FrontstageCore

@MainActor
enum ScriptCueNames {
    private static var cache = [String: [String]]()
    static func characters(in html: String) -> [String] {
        if let names = cache[html] { return names }
        guard let text = try? ScreenplayTextCodec.decode(html) else { return [] }
        let names = committed(in: text)
        if cache.count > 256 { cache.removeAll() }; cache[html] = names
        return names
    }
    static func committed(in text: NSAttributedString, excluding excluded: NSRange? = nil) -> [String] {
        var names = [String](), location = 0, candidate: String?
        while location < text.length {
            let range = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            let kind = ScreenplayTextCodec.element(in: text, at: location)
            if kind == .character { candidate = range == excluded ? nil : CharacterCue((text.string as NSString).substring(with: range)).name }
            else if kind == .dialogue { if let candidate, !candidate.isEmpty { names.append(candidate) } }
            else if kind != .parenthetical { candidate = nil }
            location = NSMaxRange(range)
        }
        return Array(Set(names)).sorted()
    }
    static func capitalize(in text: NSTextView, settings: ScriptLayoutSettings = .init()) {
        guard let storage = text.textStorage, storage.length > 0, !text.hasMarkedText() else { return }
        let selected = text.selectedRange(), location = min(selected.location, storage.length - 1)
        guard let raw = storage.attribute(.screenplayElement, at: location, effectiveRange: nil) as? String, let element = ScreenplayElement(rawValue: raw), settings.isUppercase(for: element) else { return }
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
