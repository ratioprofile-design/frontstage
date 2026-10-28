import Foundation

extension Project {
    /// Copy one scene, preserving its authored data without duplicating causal
    /// links, historical snapshots, assigned scene numbers, or production days.
    @discardableResult public mutating func duplicateBoardBeat(_ id: String) throws -> String {
        var candidate = self, board = try whiteboard()
        guard let original = board.beats.first(where: { $0.id == id }), !board.isLocked(original),
              let scene = scenes.first(where: { $0.id == original.sceneID }), !scene.isTextLocked,
              let raw = state["beats"]?.array?.first(where: { $0.object?["id"]?.decimal == scene.id })?.object else {
            throw ProjectError.invalidProject("Choose an unlocked beat to duplicate")
        }
        let sceneID = candidate.addScene(), newID = UUID().uuidString
        var fields = raw, copy = original
        fields["id"] = .number(sceneID); fields["title"] = .string(original.title + " copy")
        copy.html = DualDialogueImport.duplicatedPairIDs(original.html)
        fields["summary"] = .string(original.synopsis); fields["content"] = .string(copy.html)
        for key in ["sceneNumber", "versions", "frontstageLegacySceneID"] { fields.removeValue(forKey: key) }
        var annotationIDs = [String: String]()
        func newIDs(_ value: JSONValue) -> JSONValue {
            guard let list = value.array else { return value }
            return .array(list.map { item in guard var record = item.object else { return item }; if let old = record["id"]?.string { let new = UUID().uuidString; annotationIDs[old] = new; record["id"] = .string(new) }; return .object(record) })
        }
        if let notes = fields["notes"] { fields["notes"] = newIDs(notes) }
        for key in ["breakdown", "breakdownData"] { if let categories = fields[key]?.object { fields[key] = .object(categories.mapValues(newIDs)) } }
        copy.html = ScriptAnnotations.remap(copy.html, ids: annotationIDs); fields["content"] = .string(copy.html)
        if let html = fields["frontstageHeadingMarkup"]?.string { fields["frontstageHeadingMarkup"] = .string(ScriptAnnotations.remap(html, ids: annotationIDs)) }
        var scenes = candidate.state["beats"]!.array!
        scenes[scenes.firstIndex(where: { $0.object?["id"]?.decimal == sceneID })!] = .object(fields)
        candidate.state["beats"] = .array(scenes)
        copy.id = newID; copy.sceneID = sceneID; copy.title += " copy"
        let ordered = board.orderedBeats, index = ordered.firstIndex(where: { $0.id == id })!
        copy.order = (original.order + (index + 1 < ordered.count ? ordered[index + 1].order : original.order + 2)) / 2
        copy.start = original.start + original.duration
        var copiedContainer: (String, String)?
        if let block = board.blocks.first(where: { $0.id == original.blockID }), block.standalone == true {
            var container = block; container.id = UUID().uuidString; container.position.x += 24; container.position.y += 64
            board.blocks.append(container); copy.blockID = container.id
            copiedContainer = (block.id, container.id)
        } else if let position = copy.position { copy.position = .init(x: position.x + 24, y: position.y + 48) }
        // Seed raw records so storeWhiteboard preserves imported extension fields
        // on the new IDs as well as on the original records.
        if var rawBoard = candidate.state["frontstageWhiteboard"]?.object {
            func cloneRecord(_ key: String, from: String, to: String) {
                guard var records = rawBoard[key]?.array,
                      var record = records.first(where: { $0.object?["id"]?.string == from })?.object else { return }
                record["id"] = .string(to); records.append(.object(record)); rawBoard[key] = .array(records)
            }
            cloneRecord("beats", from: id, to: newID)
            if let pair = copiedContainer { cloneRecord("blocks", from: pair.0, to: pair.1) }
            candidate.state["frontstageWhiteboard"] = .object(rawBoard)
        }
        board.beats.append(copy)
        try board.validate(sceneIDs: Set(candidate.scenes.map(\.id))); try candidate.storeWhiteboard(board); try candidate.validateSceneModel()
        self = candidate; return newID
    }
}
