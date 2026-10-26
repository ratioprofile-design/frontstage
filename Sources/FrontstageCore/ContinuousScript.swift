import Foundation
public struct ScriptHeadingEdit: Sendable {
    public var sceneID: Decimal
    public var text: String
    public init(sceneID: Decimal, text: String) { self.sceneID = sceneID; self.text = text }
}
extension SceneHeading {
    public init(inline text: String) {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let prefixes = ["INT./EXT.", "EXT./INT.", "INT.", "EXT.", "I/E."]
        let prefix = prefixes.first { source.hasPrefix($0) } ?? ""
        let rest = String(source.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        let split = rest.range(of: " - ", options: .backwards) ?? rest.range(of: " – ", options: .backwards)
        self.init(prefix: prefix, location: split.map { String(rest[..<$0.lowerBound]) } ?? rest, time: split.map { String(rest[$0.upperBound...]) } ?? "")
    }
}
extension Project {
    public mutating func applyScriptDocument(beatHTML: [String: String], headings: [ScriptHeadingEdit]) throws {
        var candidate = self
        let original = try whiteboard()
        for (id, html) in beatHTML {
            guard let beat = original.beats.first(where: { $0.id == id }) else { throw ProjectError.invalidProject("A screenplay beat no longer exists") }
            if beat.html != html && (original.isLocked(beat) || beat.omitted || original.isUnused(beat) || scenes.first(where: { $0.id == beat.sceneID })?.isTextLocked == true) { throw ProjectError.invalidProject("This selection contains locked or inactive text") }
        }
        for heading in headings {
            guard let scene = candidate.scenes.first(where: { $0.id == heading.sceneID }) else { throw ProjectError.sceneNotFound }
            let value = SceneHeading(inline: heading.text)
            if value != scene.heading { try candidate.updateScene(id: heading.sceneID, heading: value) }
        }
        try candidate.editWhiteboard { board in
            for index in board.beats.indices { if let html = beatHTML[board.beats[index].id] { board.beats[index].html = html } }
        }
        self = candidate
    }
    @discardableResult public mutating func insertScriptScene(afterSplitting beatID: String, beforeHTML: String, afterHTML: String, heading: String) throws -> String {
        var candidate = self
        var board = try whiteboard()
        guard let index = board.beats.firstIndex(where: { $0.id == beatID }), !board.isLocked(board.beats[index]), !board.beats[index].omitted, scenes.first(where: { $0.id == board.beats[index].sceneID })?.isTextLocked == false else { throw ProjectError.invalidProject("Select an unlocked active beat") }
        let original = board.beats[index], ordered = board.orderedBeats, rank = ordered.firstIndex { $0.id == beatID }!
        let newScene = candidate.addScene(); try candidate.updateScene(id: newScene, heading: SceneHeading(inline: heading))
        var fragment = original; fragment.id = UUID().uuidString; fragment.sceneID = newScene; fragment.html = afterHTML; fragment.title = "Untitled Beat"; fragment.synopsis = ""
        fragment.order = (original.order + (rank + 1 < ordered.count ? ordered[rank + 1].order : original.order + 2)) / 2
        fragment.duration = original.duration / 2; fragment.start = original.start + fragment.duration
        board.beats[index].html = beforeHTML; board.beats[index].duration = fragment.duration
        for next in ordered.dropFirst(rank + 1) {
            guard next.sceneID == original.sceneID else { break }
            guard !board.isLocked(next) else { throw ProjectError.invalidProject("A locked beat prevents inserting this scene") }
            if let i = board.beats.firstIndex(where: { $0.id == next.id }) { board.beats[i].sceneID = newScene }
        }
        if let owner = board.blocks.first(where: { $0.id == original.blockID }), owner.standalone == true {
            var container = owner; container.id = UUID().uuidString; container.position.y += 60
            board.blocks.append(container); fragment.blockID = container.id
        }
        board.beats.append(fragment)
        try board.validate(sceneIDs: Set(candidate.scenes.map(\.id))); try candidate.storeWhiteboard(board)
        self = candidate; return fragment.id
    }
}
