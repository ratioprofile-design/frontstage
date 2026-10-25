#if os(macOS)
import SwiftUI
import AppKit

struct ScriptColorOptions: View {
    @AppStorage("frontstage-synopsis-color") private var synopsis = "#0000aa"
    @AppStorage("frontstage-screenplay-color") private var screenplay = "#111111"
    static let colors = [("Black", "#111111"), ("Blue", "#0000aa"), ("Red", "#aa0000"), ("Green", "#006600"), ("Purple", "#660099")]
    var body: some View {
        Picker("Synopsis text color", selection: $synopsis) { ForEach(Self.colors, id: \.1) { Text($0.0).tag($0.1) } }
        Picker("Screenplay text color", selection: $screenplay) { ForEach(Self.colors, id: \.1) { Text($0.0).tag($0.1) } }
    }
}
struct ScriptSynopsisPreview: View {
    let text: String
    @State private var expanded = false
    @AppStorage("frontstage-synopsis-color") private var color = "#0000aa"
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView { Text(text).foregroundStyle(Color(boardHex: color)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(height: expanded ? 240 : min(80, max(24, Double(text.count) / 2)))
            if text.count > 180 || text.components(separatedBy: "\n").count > 3 {
                Button(expanded ? "Collapse synopsis" : "Expand synopsis") { expanded.toggle() }.font(.caption)
            }
        }.padding(8).fixedSize(horizontal: false, vertical: true)
    }
}
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
        let prefix = ((storage.string as NSString).substring(with: NSRange(location: range.location, length: max(0, selected.location - range.location))) as NSString)
        storage.replaceCharacters(in: range, with: upper)
        text.setSelectedRange(NSRange(location: range.location + (prefix as String).uppercased().utf16.count, length: 0))
    }
}
#endif
