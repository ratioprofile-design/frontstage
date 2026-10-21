import Foundation

extension ProjectMerge {
    /// Snippets own native scene text. Merge them first, then rebuild their derived scene fields.
    public static func mergeDocuments(base: JSONValue, local: JSONValue, remote: JSONValue) -> ProjectMergeResult {
        guard let b = SnippetMergeDocument(base), let l = SnippetMergeDocument(local), let r = SnippetMergeDocument(remote), b.enveloped == l.enveloped, b.enveloped == r.enveloped else {
            var result = merge(base: base, local: local, remote: remote)
            if let shape = SnippetMergeDocument(result.value) {
                let prefix = shape.enveloped ? "/project" : ""
                let inconsistent = shape.projections.keys.filter { !shape.isCanonical($0) }
                if !inconsistent.isEmpty {
                    result.value = local; result.conflicts += inconsistent.map { prefix + "/beats/\($0)/content" }
                    result.conflicts = Array(Set(result.conflicts)).sorted()
                }
            } else if let root = result.value.object {
                let state = root["format"]?.string == "frontstage" ? root["project"]?.object : root
                if state?["frontstageWhiteboard"] != nil { result.value = local; result.conflicts.append((root["format"]?.string == "frontstage" ? "/project" : "") + "/frontstageWhiteboard") }
            }
            return result
        }
        let eligible = Set(b.projections.keys).intersection(l.projections.keys).intersection(r.projections.keys).filter {
            b.isCanonical($0) && l.isCanonical($0) && r.isCanonical($0)
        }
        let ids = Set(eligible)
        var result = merge(base: b.normalized(ids), local: l.normalized(ids), remote: r.normalized(ids))
        let prefix = b.enveloped ? "/project" : ""
        guard var merged = SnippetMergeDocument(result.value) else {
            return ProjectMergeResult(value: local, conflicts: Array(Set(result.conflicts + [prefix + "/frontstageWhiteboard"])).sorted())
        }
        var scenes = merged.state["beats"]!.array!
        for i in scenes.indices {
            guard var scene = scenes[i].object, let id = scene["id"]?.decimal, ids.contains(id) else { continue }
            let projection = merged.projections[id] ?? SnippetProjection(html: "", characters: [], disabled: true)
            if scene["frontstageTextLocked"] == .bool(true) {
                let lockedVersions = [b, l, r].filter { $0.scenes[id]?["frontstageTextLocked"] == .bool(true) }
                if !lockedVersions.contains(where: { $0.projections[id]?.html == projection.html }) { result.conflicts.append(prefix + "/beats/\(id)/content") }
            }
            scene["content"] = .string(projection.html); scene["isDisabled"] = .bool(projection.disabled)
            scene["characters"] = .array(projection.characters.map(JSONValue.string)); scenes[i] = .object(scene)
        }
        merged.state["beats"] = .array(scenes); result.value = merged.value
        do {
            let project = try Project(data: JSONEncoder().encode(result.value)); _ = try project.whiteboard()
        } catch {
            result.value = local; result.conflicts.append(prefix + "/frontstageWhiteboard")
        }
        result.conflicts = Array(Set(result.conflicts)).sorted()
        return result
    }
}

private struct SnippetProjection {
    var html: String
    var characters: [String]
    var disabled: Bool
}

private struct SnippetMergeDocument {
    var root: [String: JSONValue]
    var state: [String: JSONValue]
    let enveloped: Bool
    let scenes: [Decimal: [String: JSONValue]]
    let projections: [Decimal: SnippetProjection]

    init?(_ value: JSONValue) {
        guard let root = value.object else { return nil }
        self.root = root; enveloped = root["format"]?.string == "frontstage"
        guard let state = enveloped ? root["project"]?.object : root,
              let encoded = state["frontstageWhiteboard"], let raw = state["beats"]?.array,
              let board = try? JSONDecoder().decode(Whiteboard.self, from: JSONEncoder().encode(encoded)) else { return nil }
        let entries = raw.compactMap { item -> (Decimal, [String: JSONValue])? in
            guard let fields = item.object, let id = fields["id"]?.decimal else { return nil }; return (id, fields)
        }
        guard entries.count == raw.count, Set(entries.map(\.0)).count == entries.count,
              (try? board.validate(sceneIDs: Set(entries.map(\.0)))) != nil else { return nil }
        self.state = state; scenes = Dictionary(uniqueKeysWithValues: entries)
        let unused = Set(board.layers.filter(\.unused).map(\.id)), inactive = Set(board.blocks.filter { unused.contains($0.layerID) }.map(\.id))
        projections = Dictionary(grouping: board.orderedBeats, by: \.sceneID).mapValues { snippets in
            let active = snippets.filter { !$0.omitted && !inactive.contains($0.blockID) }
            return SnippetProjection(html: active.map(\.html).joined(), characters: Array(Set(active.flatMap(\.characters))).sorted(), disabled: active.isEmpty)
        }
    }
    var value: JSONValue {
        if enveloped { var output = root; output["project"] = .object(state); return .object(output) }
        return .object(state)
    }
    func isCanonical(_ id: Decimal) -> Bool {
        guard let scene = scenes[id], let projection = projections[id], scene["content"]?.string == projection.html,
              (scene["isDisabled"] == .bool(true)) == projection.disabled else { return false }
        if let stored = scene["characters"] {
            guard let array = stored.array, array.compactMap(\.string).count == array.count,
                  Set(array.compactMap(\.string)) == Set(projection.characters) else { return false }
        } else if !projection.characters.isEmpty { return false }
        return true
    }
    func normalized(_ ids: Set<Decimal>) -> JSONValue {
        var output = self
        output.state["beats"] = .array(state["beats"]!.array!.map { value in
            guard var fields = value.object, let id = fields["id"]?.decimal, ids.contains(id) else { return value }
            for key in ["content", "characters", "isDisabled"] { fields.removeValue(forKey: key) }
            return .object(fields)
        })
        return output.value
    }
}
