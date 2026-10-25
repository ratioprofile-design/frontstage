import Foundation

public struct ScriptFilters: Equatable, Sendable {
    public struct Facet: Equatable, Sendable {
        public var values = Set<String>()
        public var hide = false
        public var all = false
        public init() {}
    }
    public static let kinds = ["Beats", "Tags", "Characters", "Locations", "Blocks", "Lanes"]
    public var facets = [String: Facet]()
    public var hideDisabled = false, hideEmpty = false, hideHeadings = false, hideBreaks = false, hideGaps = false
    public var gaps = "Pages"
    public init() {}
    public func matches(_ beat: BoardBeat, board: Whiteboard, scenes: [Scene]) -> Bool {
        let scene = scenes.first { $0.id == beat.sceneID }, owner = board.blocks.first { $0.id == beat.blockID }
        if hideDisabled && (beat.omitted || scene?.isDisabled == true) { return false }
        if hideEmpty && Self.plain(beat.html).isEmpty { return false }
        var ancestors = Set<String>(), current = owner
        while let block = current, ancestors.insert(block.id).inserted { current = board.blocks.first { $0.id == block.parentID } }
        let values: [String: [String]] = ["Beats": [beat.id], "Tags": beat.tags, "Characters": Self.characters(beat),
            "Locations": [scene?.heading.location ?? ""], "Blocks": Array(ancestors), "Lanes": [owner?.layerID ?? ""]]
        return facets.allSatisfy { kind, facet in
            guard !facet.values.isEmpty else { return true }
            let available = Set((values[kind] ?? []).map { $0.precomposedStringWithCanonicalMapping.uppercased() })
            let tests = facet.values.map { available.contains($0.precomposedStringWithCanonicalMapping.uppercased()) }
            let match = facet.all ? tests.allSatisfy { $0 } : tests.contains(true)
            return facet.hide ? !match : match
        }
    }
    public static func characters(_ beat: BoardBeat) -> [String] {
        let source = beat.html as NSString
        let regex = try? NSRegularExpression(pattern: #"<(?:p|div)[^>]*class=["'][^"']*sc-character[^"']*["'][^>]*>([\s\S]*?)</(?:p|div)>"#, options: .caseInsensitive)
        return beat.characters + (regex?.matches(in: beat.html, range: NSRange(location: 0, length: source.length)) ?? []).map { plain(source.substring(with: $0.range(at: 1))).replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression) }
    }
    public static func plain(_ html: String) -> String { html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression).replacingOccurrences(of: "&nbsp;", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
    public func gap(before id: String, board: Whiteboard, scenes: [Scene]) -> String? {
        guard !hideGaps, let index = board.orderedBeats.firstIndex(where: { $0.id == id }) else { return nil }
        var skipped = [BoardBeat]()
        for beat in board.orderedBeats[..<index].reversed() { if matches(beat, board: board, scenes: scenes) { break }; skipped.append(beat) }
        guard !skipped.isEmpty else { return nil }
        if gaps == "Time" { return String(format: "%.1f seconds omitted", skipped.reduce(0) { $0 + $1.duration }) }
        if gaps == "Pages" { return String(format: "≈ %.1f pages omitted", Double(skipped.reduce(0) { $0 + Self.plain($1.html).count }) / 1800) }
        return "\(skipped.count) beats omitted"
    }
}
