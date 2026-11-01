import Foundation

/// Device-local display modes; authored beat colors and dependencies remain unchanged.
public enum BoardColorMode: String, CaseIterable, Sendable { case authored, characters, tags }
public struct BoardFlowLine: Equatable, Sendable {
    public var cause: String
    public var effect: String
}
extension Whiteboard {
    public func trackNames(for beat: BoardBeat, kind: String) -> [String] {
        let names = kind == "characters" ? beat.characters : kind == "tags" ? beat.tags : []
        return Array(Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping }.filter { !$0.isEmpty })).sorted()
    }
    public func displayColors(for beat: BoardBeat, mode: BoardColorMode) -> [String] {
        let colors = trackNames(for: beat, kind: mode.rawValue).map(StoryTimeline.color)
        return colors.isEmpty ? [beat.color] : colors
    }
    public func flowLines(kind: String, name: String) -> [BoardFlowLine] {
        guard ["characters", "tags"].contains(kind), !name.isEmpty else { return [] }
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        let matching = orderedBeats.filter { !$0.omitted && !isUnused($0) && trackNames(for: $0, kind: kind).contains(target) }
        return zip(matching, matching.dropFirst()).map { .init(cause: $0.0.id, effect: $0.1.id) }
    }
}
