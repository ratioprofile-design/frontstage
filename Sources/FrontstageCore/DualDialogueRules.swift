import Foundation

public struct DualDialogueLine: Sendable {
    public var element: ScreenplayElement
    public var text: String
    public var scene: String
    public init(element: ScreenplayElement, text: String, scene: String) { self.element = element; self.text = text; self.scene = scene }
}
public struct DualDialoguePairPlan: Equatable, Sendable {
    public let left: Range<Int>
    public let right: Range<Int>
}
public enum DualDialogueRules {
    /// Pair two adjacent complete speech blocks. Actions, headings and scene boundaries are barriers.
    public static func pair(in lines: [DualDialogueLine], at index: Int) throws -> DualDialoguePairPlan {
        guard lines.indices.contains(index) else { throw ProjectError.invalidProject("Select the second speech block") }
        var cue = index
        while cue > 0 && [.dialogue, .parenthetical].contains(lines[cue].element) { cue -= 1 }
        guard lines[cue].element == .character, !CharacterCue(lines[cue].text).name.isEmpty else { throw ProjectError.invalidProject("Select a complete character and dialogue block") }
        func end(_ start: Int) throws -> Int {
            var i = start + 1, spoken = false
            while i < lines.count && [.dialogue, .parenthetical].contains(lines[i].element) {
                guard lines[i].scene == lines[start].scene else { throw ProjectError.invalidProject("Dual dialogue must stay within one scene") }
                if lines[i].element == .dialogue && !lines[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { spoken = true }
                i += 1
            }
            guard spoken else { throw ProjectError.invalidProject("Both characters need dialogue before pairing") }
            return i
        }
        let rightEnd = try end(cue)
        guard cue > 0 else { throw ProjectError.invalidProject("A preceding speech block is required") }
        var left = cue - 1
        while left > 0 && [.dialogue, .parenthetical].contains(lines[left].element) { left -= 1 }
        guard lines[left].element == .character, !CharacterCue(lines[left].text).name.isEmpty,
              lines[left].scene == lines[cue].scene, try end(left) == cue else { throw ProjectError.invalidProject("Pair adjacent speech blocks in the same scene; intervening action cannot be paired") }
        return DualDialoguePairPlan(left: left..<cue, right: cue..<rightEnd)
    }
}
