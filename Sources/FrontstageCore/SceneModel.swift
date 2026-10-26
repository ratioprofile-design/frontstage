import Foundation

public struct SceneConversionGroup: Identifiable, Sendable {
    public let scene: Scene
    public let beats: [BoardBeat]
    public let conflict: Bool
    public var id: Decimal { scene.id }
}
extension Project {
    public func legacySceneRevisions(_ sceneID: Decimal) -> [SceneRevision] {
        guard let fields = state["beats"]?.array?.first(where: { $0.object?["id"]?.decimal == sceneID })?.object,
              let originalID = fields["frontstageLegacySceneID"]?.decimal, let legacy = state["frontstageLegacyScenes"]?.object else { return [] }
        var project = Project(); project.state = legacy; return project.revisions(for: originalID)
    }
    public var usesOneBeatPerScene: Bool { state["frontstageSceneModel"]?.string == "oneBeatPerScene" }
    public func validateSceneModel() throws {
        guard usesOneBeatPerScene, state["frontstageWhiteboard"] != nil else { return }
        let board = try whiteboard()
        let archived = try (state["frontstagePullouts"]?.array ?? []).map { try JSONDecoder().decode(BoardBeat.self, from: JSONEncoder().encode($0.object?["beat"] ?? .null)) }
        for scene in scenes {
            let owned = (board.beats + archived).filter { $0.sceneID == scene.id }
            guard owned.count == 1, owned[0].title == scene.title, owned[0].synopsis == scene.summary else { throw ProjectError.invalidProject("This project requires one beat per scene with matching titles and summaries. Update Frontstage or review a converted copy.") }
        }
    }
    public func sceneConversionGroups() throws -> [SceneConversionGroup] {
        let board = try whiteboard()
        let archived = try (state["frontstagePullouts"]?.array ?? []).map { try JSONDecoder().decode(BoardBeat.self, from: JSONEncoder().encode($0.object?["beat"] ?? .null)) }
        return scenes.map { scene in
            let beats = (board.beats + archived).filter { $0.sceneID == scene.id }.sorted { $0.order < $1.order }
            return SceneConversionGroup(scene: scene, beats: beats, conflict: beats.contains { $0.title != scene.title || $0.synopsis != scene.summary })
        }
    }
    public func convertedSceneCopy(choices: [Decimal: [String: Set<String>]] = [:]) throws -> Project {
        var copy = self
        copy.state.removeValue(forKey: "frontstageSceneModel")
        copy.state["frontstageLegacyScenes"] = .object(state)
        copy.name += " — converted"
        var board = try whiteboard(), archive = state["frontstagePullouts"]?.array ?? []
        var nextID = (scenes.map(\.id).max() ?? 0) + 1, output = [JSONValue]()
        let categories = ["notes": ["notes"], "breakdown": ["breakdown", "breakdownData"], "attachments": ["attachments"], "production": ["productionNotes", "shootingNotes"]]
        for group in try sceneConversionGroups() {
            let scene = group.scene
            var owned = group.beats
            if owned.isEmpty {
                let block = BoardBlock(name: "", layerID: board.layers[0].id, position: .init(x: 60, y: 60))
                var container = block; container.standalone = true; board.blocks.append(container)
                var beat = BoardBeat(sceneID: scene.id, blockID: block.id, title: scene.title, html: scene.html, order: Double(board.beats.count))
                beat.synopsis = scene.summary; beat.omitted = scene.isDisabled; board.beats.append(beat); owned = [beat]
            }
            var destinations = [String: Decimal]()
            for (index, beat) in owned.enumerated() {
                var fields = state["beats"]!.array!.first { $0.object?["id"]?.decimal == scene.id }!.object!
                let id = index == 0 ? scene.id : nextID
                if index > 0 { nextID += 1; fields.removeValue(forKey: "sceneNumber") }
                fields["id"] = .number(id); fields["title"] = .string(beat.title); fields["summary"] = .string(beat.synopsis)
                fields["content"] = .string(beat.omitted ? "" : beat.html); fields["isDisabled"] = .bool(beat.omitted)
                fields["frontstageLegacySceneID"] = .number(scene.id); fields.removeValue(forKey: "versions")
                for (category, keys) in categories {
                    let targets = choices[scene.id]?[category] ?? [owned[0].id]
                    for key in keys {
                        if !targets.contains(beat.id) { fields.removeValue(forKey: key) }
                        else if index > 0, let items = fields[key]?.array {
                            fields[key] = .array(items.map { value in guard var record = value.object else { return value }; record["frontstageSourceID"] = record["id"]; record["id"] = .string(UUID().uuidString); return .object(record) })
                        }
                    }
                }
                if let i = board.beats.firstIndex(where: { $0.id == beat.id }) { board.beats[i].sceneID = id }
                if let i = archive.firstIndex(where: { $0.object?["id"]?.string == beat.id }), var entry = archive[i].object, var raw = entry["beat"]?.object { raw["sceneID"] = .number(id); entry["beat"] = .object(raw); archive[i] = .object(entry); fields["content"] = .string(""); fields["isDisabled"] = .bool(true) }
                destinations[beat.id] = id; output.append(.object(fields))
            }
            if var production = copy.state["frontstageProduction"]?.object, let days = production["days"]?.array {
                production["days"] = .array(days.map { day in
                    guard var fields = day.object, let ids = fields["sceneIDs"]?.array, ids.contains(.number(scene.id)) else { return day }
                    let targets = choices[scene.id]?["production"] ?? [owned[0].id]
                    fields["sceneIDs"] = .array(ids.filter { $0 != .number(scene.id) } + owned.filter { targets.contains($0.id) }.compactMap { destinations[$0.id].map(JSONValue.number) }); return .object(fields)
                }); copy.state["frontstageProduction"] = .object(production)
            }
        }
        copy.state["beats"] = .array(output); copy.state["nextId"] = .number(nextID); copy.state["frontstagePullouts"] = .array(archive)
        copy.state["frontstageSceneModel"] = .string("oneBeatPerScene")
        try copy.storeWhiteboard(board); try copy.validateSceneModel(); return copy
    }
    public mutating func updateBeatCard(_ id: String, title: String? = nil, synopsis: String? = nil) throws {
        let board = try whiteboard()
        guard let beat = board.beats.first(where: { $0.id == id }), !board.isLocked(beat), scenes.first(where: { $0.id == beat.sceneID })?.isTextLocked == false else { throw ProjectError.invalidProject("Unlock this scene before editing") }
        try updateBoardBeat(id) { if let title { $0.title = title }; if let synopsis { $0.synopsis = synopsis } }
    }
}
