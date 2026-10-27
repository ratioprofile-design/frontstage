import Foundation

extension SceneHeading {
    public static let timeSuggestions = ["DAY", "NIGHT", "MORNING", "AFTERNOON", "EVENING", "DAWN", "DUSK", "LATER", "CONTINUOUS", "SAME TIME"]

    /// Full prefixes through the caret; TextKit replaces only its partial-word range.
    public static func completions(for prefix: String, headings: [SceneHeading]) -> [String] {
        let prefixes = ["INT.", "EXT.", "INT./EXT.", "EXT./INT.", "I/E."]
        let source = prefix.uppercased()
        let separator = source.range(of: #"\s[-–—]\s*"#, options: [.regularExpression, .backwards])
        let choices: [String]
        if let separator {
            let base = String(source[..<separator.upperBound])
            choices = timeSuggestions.map { base + $0 }
        } else if let kind = prefixes.first(where: { source.hasPrefix($0 + " ") }) {
            let base = kind + " "
            choices = headings.map { base + $0.location.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        } else { choices = prefixes }
        var seen = Set<String>()
        return choices.filter { $0.hasPrefix(source) && $0 != source && seen.insert($0).inserted }
    }
}
