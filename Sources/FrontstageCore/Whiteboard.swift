import Foundation

public struct BoardPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
}

public struct BoardViewport: Codable, Equatable, Sendable {
    public var origin = BoardPoint()
    public var zoom = 1.0
    public init() {}
}

public struct BoardLayer: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var height: Double
    public var collapsed: Bool
    public var locked: Bool
    public var unused: Bool
    public init(id: String = UUID().uuidString, name: String, height: Double = 300, unused: Bool = false) {
        self.id = id; self.name = name; self.height = height
        collapsed = false; locked = false; self.unused = unused
    }
}

public struct BoardBlock: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var layerID: String
    public var parentID: String?
    public var position: BoardPoint
    public var width: Double
    public var collapsed: Bool
    public var locked: Bool
    public init(id: String = UUID().uuidString, name: String, layerID: String, position: BoardPoint = .init(), width: Double = 224) {
        self.id = id; self.name = name; self.layerID = layerID; self.position = position; self.width = width
        collapsed = false; locked = false
    }
}

public enum BoardBeatKind: String, Codable, CaseIterable, Sendable { case story, subtext }

public struct BoardBeat: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var sceneID: Decimal
    public var blockID: String
    public var title: String
    public var synopsis: String
    public var html: String
    public var kind: BoardBeatKind
    public var color: String
    public var characters: [String]
    public var tags: [String]
    public var mustBeCaused: Bool
    public var omitted: Bool
    public var locked: Bool
    public var order: Double
    public var start: Double
    public var duration: Double
    public init(id: String = UUID().uuidString, sceneID: Decimal, blockID: String, title: String,
                html: String = "", order: Double = 0, start: Double = 0) {
        self.id = id; self.sceneID = sceneID; self.blockID = blockID; self.title = title; self.html = html
        synopsis = ""; kind = .story; color = "#a34eae"; characters = []; tags = []
        mustBeCaused = false; omitted = false; locked = false; self.order = order; self.start = start; duration = 1.5
    }
}

public struct BoardDependency: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var cause: String
    public var effect: String
    public var reason: String
    public var reference: Bool
    public init(id: String = UUID().uuidString, cause: String, effect: String, reason: String = "", reference: Bool = false) {
        self.id = id; self.cause = cause; self.effect = effect; self.reason = reason; self.reference = reference
    }
}

public struct BoardStroke: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var points: [BoardPoint]
    public var color: String
    public var width: Double
    public init(points: [BoardPoint], color: String = "#efc85d", width: Double = 2) {
        id = UUID().uuidString; self.points = points; self.color = color; self.width = width
    }
}

public struct BoardIssue: Identifiable, Equatable, Sendable {
    public var id: String
    public var message: String
    public var beatIDs: Set<String>
}

public struct Whiteboard: Codable, Equatable, Sendable {
    public var version = 1
    public var layers: [BoardLayer] = [BoardLayer(id: "main", name: "Main Layer"), BoardLayer(id: "unused", name: "Unused", unused: true)]
    public var blocks: [BoardBlock] = []
    public var beats: [BoardBeat] = []
    public var dependencies: [BoardDependency] = []
    public var strokes: [BoardStroke] = []
    public var viewport = BoardViewport()
    public init() {}

    public var orderedBeats: [BoardBeat] { beats.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order } }
    public func isUnused(_ beat: BoardBeat) -> Bool {
        guard let block = blocks.first(where: { $0.id == beat.blockID }) else { return false }
        return layers.first { $0.id == block.layerID }?.unused == true
    }
    public func isLocked(_ beat: BoardBeat) -> Bool {
        beat.locked || isBlockLocked(beat.blockID)
    }
    public func isBlockLocked(_ id: String) -> Bool {
        var current: String? = id, visited = Set<String>()
        while let key = current, let block = blocks.first(where: { $0.id == key }), visited.insert(key).inserted {
            if block.locked || layers.first(where: { $0.id == block.layerID })?.locked == true { return true }
            current = block.parentID
        }
        return false
    }

    public var issues: [BoardIssue] {
        var result: [BoardIssue] = []
        let unusedLayers = Set(layers.filter(\.unused).map(\.id)), unusedBlocks = Set(blocks.filter { unusedLayers.contains($0.layerID) }.map(\.id))
        let live = beats.filter { !$0.omitted && !unusedBlocks.contains($0.blockID) }, byID = Dictionary(uniqueKeysWithValues: beats.map { ($0.id, $0) })
        let incoming = Dictionary(grouping: dependencies.filter { !$0.reference }, by: \.effect)
        for beat in live where beat.mustBeCaused {
            let satisfied = (incoming[beat.id] ?? []).contains { edge in
                guard let cause = byID[edge.cause] else { return false }
                return !cause.omitted && !unusedBlocks.contains(cause.blockID)
            }
            if !satisfied { result.append(BoardIssue(id: "missing-\(beat.id)", message: "\(beat.title) must be caused, but has no active cause.", beatIDs: [beat.id])) }
        }
        for edge in dependencies where !edge.reference {
            guard let a = byID[edge.cause], let b = byID[edge.effect], !a.omitted, !b.omitted, !unusedBlocks.contains(a.blockID), !unusedBlocks.contains(b.blockID) else { continue }
            if b.start + 0.00001 < a.start + a.duration {
                result.append(BoardIssue(id: edge.id, message: "\(b.title) begins before \(a.title) finishes.", beatIDs: [a.id, b.id]))
            }
        }
        if (try? causalOrder()) == nil { result.append(BoardIssue(id: "cycle", message: "A causal loop must be repaired before ripple can run.", beatIDs: Set(beats.map(\.id)))) }
        return result
    }

    public func causalOrder() throws -> [String] {
        var incoming = Dictionary(uniqueKeysWithValues: beats.map { ($0.id, 0) })
        let outgoing = Dictionary(grouping: dependencies.filter { !$0.reference }, by: \.cause)
        for edge in dependencies where !edge.reference { incoming[edge.effect, default: 0] += 1 }
        var queue = orderedBeats.filter { incoming[$0.id] == 0 }.map(\.id), cursor = 0
        while cursor < queue.count {
            let id = queue[cursor]; cursor += 1
            for edge in (outgoing[id] ?? []).sorted(by: { $0.id < $1.id }) {
                incoming[edge.effect, default: 0] -= 1
                if incoming[edge.effect] == 0 { queue.append(edge.effect) }
            }
        }
        guard queue.count == beats.count else { throw ProjectError.invalidProject("causal dependency loop") }
        return queue
    }

    public func validate(sceneIDs: Set<Decimal>) throws {
        guard version == 1 else { throw ProjectError.invalidProject("whiteboard version \(version) is unsupported") }
        func unique(_ ids: [String]) -> Bool { ids.allSatisfy { !$0.isEmpty } && Set(ids).count == ids.count }
        func coordinate(_ n: Double) -> Bool { n.isFinite && abs(n) <= 1_000_000 }
        guard unique(layers.map(\.id)), unique(blocks.map(\.id)), unique(beats.map(\.id)), unique(dependencies.map(\.id)), unique(strokes.map(\.id)),
              !layers.isEmpty, layers.allSatisfy({ $0.height.isFinite && $0.height >= 100 && $0.height <= 10000 }),
              coordinate(viewport.origin.x), coordinate(viewport.origin.y), viewport.zoom.isFinite, (0.15...3).contains(viewport.zoom) else {
            throw ProjectError.invalidProject("invalid whiteboard identifiers, layers or viewport")
        }
        let layerIDs = Set(layers.map(\.id)), blockIDs = Set(blocks.map(\.id)), beatIDs = Set(beats.map(\.id))
        for block in blocks {
            guard layerIDs.contains(block.layerID), coordinate(block.position.x), coordinate(block.position.y), block.width.isFinite,
                  (140...2000).contains(block.width), block.parentID.map(blockIDs.contains) ?? true else { throw ProjectError.invalidProject("invalid whiteboard block") }
            var parent = block.parentID, seen: Set<String> = [block.id]
            while let id = parent {
                guard seen.insert(id).inserted else { throw ProjectError.invalidProject("nested block loop") }
                parent = blocks.first { $0.id == id }?.parentID
            }
        }
        guard beats.allSatisfy({ sceneIDs.contains($0.sceneID) && blockIDs.contains($0.blockID) && coordinate($0.order) && coordinate($0.start) && $0.start >= 0 && $0.duration.isFinite && (0.05...1000).contains($0.duration) }),
              dependencies.allSatisfy({ beatIDs.contains($0.cause) && beatIDs.contains($0.effect) && $0.cause != $0.effect }),
              strokes.allSatisfy({ $0.points.count <= 10000 && $0.points.allSatisfy { coordinate($0.x) && coordinate($0.y) } && $0.width.isFinite && (0.5...30).contains($0.width) }) else {
            throw ProjectError.invalidProject("invalid whiteboard beats, dependencies or drawing")
        }
    }

    public mutating func resolveCauses() throws {
        let order = try causalOrder(), incoming = Dictionary(grouping: dependencies.filter { !$0.reference }, by: \.effect)
        let indices = Dictionary(uniqueKeysWithValues: beats.indices.map { (beats[$0].id, $0) })
        let unusedLayers = Set(layers.filter(\.unused).map(\.id)), unusedBlocks = Set(blocks.filter { unusedLayers.contains($0.layerID) }.map(\.id))
        var candidate = self
        for id in order {
            guard let i = indices[id], !candidate.beats[i].omitted, !unusedBlocks.contains(candidate.beats[i].blockID) else { continue }
            let required = (incoming[id] ?? []).compactMap { edge -> Double? in
                guard let j = indices[edge.cause], !candidate.beats[j].omitted, !unusedBlocks.contains(candidate.beats[j].blockID) else { return nil }
                return candidate.beats[j].start + candidate.beats[j].duration
            }.max() ?? 0
            if candidate.beats[i].start < required {
                guard !candidate.isLocked(candidate.beats[i]) else { throw ProjectError.invalidProject("\(candidate.beats[i].title) is locked and blocks the causal ripple") }
                candidate.beats[i].start = required
            }
        }
        self = candidate
    }

    /// Explicitly remove time gaps; free board positions and editorial order remain independent.
    public mutating func compactCauses() throws {
        let order = try causalOrder(), incoming = Dictionary(grouping: dependencies.filter { !$0.reference }, by: \.effect)
        let indices = Dictionary(uniqueKeysWithValues: beats.indices.map { (beats[$0].id, $0) })
        let unusedLayers = Set(layers.filter(\.unused).map(\.id)), unusedBlocks = Set(blocks.filter { unusedLayers.contains($0.layerID) }.map(\.id))
        var candidate = self
        for id in order {
            guard let i = indices[id], !candidate.beats[i].omitted, !unusedBlocks.contains(candidate.beats[i].blockID) else { continue }
            let earliest = (incoming[id] ?? []).compactMap { edge -> Double? in
                guard let j = indices[edge.cause], !candidate.beats[j].omitted, !unusedBlocks.contains(candidate.beats[j].blockID) else { return nil }
                return candidate.beats[j].start + candidate.beats[j].duration
            }.max() ?? 0
            if candidate.isLocked(candidate.beats[i]) {
                guard candidate.beats[i].start >= earliest else { throw ProjectError.invalidProject("\(candidate.beats[i].title) is locked and blocks causal compaction") }
            } else { candidate.beats[i].start = earliest }
        }
        self = candidate
    }
}

extension Project {
    public func whiteboard() throws -> Whiteboard {
        if let stored = state["frontstageWhiteboard"] {
            let board = try JSONDecoder().decode(Whiteboard.self, from: JSONEncoder().encode(stored))
            try board.validate(sceneIDs: Set(scenes.map(\.id)))
            return board
        }
        var board = Whiteboard()
        let graph = storyGraph, lanes = storySequencer().lanes
        for lane in lanes where lane.index > 0 && !lane.isUnused {
            board.layers.insert(BoardLayer(id: "legacy-layer-\(lane.index)", name: lane.label), at: board.layers.count - 1)
        }
        let raw = Dictionary(uniqueKeysWithValues: (state["beats"]?.array ?? []).compactMap { v -> (Decimal, [String: JSONValue])? in
            guard let fields = v.object, let id = fields["id"]?.decimal else { return nil }; return (id, fields)
        })
        for (index, scene) in scenes.enumerated() {
            let id = "scene-\(scene.id)", blockID = "block-\(scene.id)", fields = raw[scene.id] ?? [:]
            let lane = max(0, min(lanes.count - 1, NSDecimalNumber(decimal: fields["trackIndex"]?.decimal ?? 0).intValue))
            let layerID = lanes[lane].isUnused ? "unused" : lane == 0 ? "main" : "legacy-layer-\(lane)"
            let position = BoardPoint(x: max(0, min(900000, fields["x"]?.double ?? Double(index) * 260)), y: 60)
            board.blocks.append(BoardBlock(id: blockID, name: scene.heading.location.isEmpty ? scene.title : scene.heading.location, layerID: layerID, position: position))
            var beat = BoardBeat(id: id, sceneID: scene.id, blockID: blockID, title: scene.title, html: scene.html, order: Double(index), start: Double(index) * 1.5)
            beat.synopsis = scene.summary; beat.omitted = scene.isDisabled
            beat.color = ["#39798c", "#a34eae", "#ab7d22", "#34834b"][index % 4]
            beat.characters = fields["characters"]?.array?.compactMap(\.string) ?? []
            board.beats.append(beat)
        }
        for link in graph.links {
            board.dependencies.append(BoardDependency(id: link.id, cause: "scene-\(link.from)", effect: "scene-\(link.to)", reason: link.label, reference: link.kind == .reference))
        }
        return board
    }

    /// The document is committed only after validation; existing unknown entity fields survive.
    public mutating func editWhiteboard(_ operation: (inout Whiteboard) throws -> Void) throws {
        var candidate = self, board = try whiteboard()
        try operation(&board)
        try board.validate(sceneIDs: Set(candidate.scenes.map(\.id)))
        try candidate.storeWhiteboard(board)
        self = candidate
    }

    private mutating func storeWhiteboard(_ board: Whiteboard) throws {
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(board))
        var fields = state["frontstageWhiteboard"]?.object ?? [:]
        for (key, value) in encoded.object ?? [:] {
            if let items = value.array, let oldItems = fields[key]?.array, ["layers", "blocks", "beats", "dependencies", "strokes"].contains(key) {
                let old = oldItems.reduce(into: [String: [String: JSONValue]]()) { map, item in
                    if let id = item.object?["id"]?.string { map[id] = item.object }
                }
                fields[key] = .array(items.map { item in
                    guard let current = item.object, let id = current["id"]?.string else { return item }
                    var merged = old[id] ?? [:]
                    // Optional parent IDs need explicit removal when a block is ungrouped.
                    if key == "blocks" && current["parentID"] == nil { merged.removeValue(forKey: "parentID") }
                    current.forEach { merged[$0.key] = $0.value }; return .object(merged)
                })
            } else { fields[key] = value }
        }
        state["frontstageWhiteboard"] = .object(fields)
        let snippets = Dictionary(grouping: board.orderedBeats, by: \.sceneID)
        let unusedLayers = Set(board.layers.filter(\.unused).map(\.id)), unusedBlocks = Set(board.blocks.filter { unusedLayers.contains($0.layerID) }.map(\.id))
        var rawScenes = state["beats"]?.array ?? []
        for i in rawScenes.indices {
            guard var fields = rawScenes[i].object, let id = fields["id"]?.decimal, let linked = snippets[id] else { continue }
            let active = linked.filter { !$0.omitted && !unusedBlocks.contains($0.blockID) }, html = active.map(\.html).joined()
            guard fields["frontstageTextLocked"] != .bool(true) || fields["content"]?.string == html else { throw ProjectError.invalidProject("unlock \(fields["title"]?.string ?? "this scene")'s script before changing its snippet text or inclusion") }
            fields["content"] = .string(html); fields["isDisabled"] = .bool(active.isEmpty)
            fields["characters"] = .array(Array(Set(active.flatMap(\.characters))).sorted().map(JSONValue.string))
            rawScenes[i] = .object(fields)
        }
        state["beats"] = .array(rawScenes)
    }

    @discardableResult
    public mutating func addBoardBeat(blockID: String? = nil, layerID: String = "main", position: BoardPoint = .init(x: 60, y: 60), title: String = "Untitled Beat") throws -> String {
        var candidate = self
        let existing = try candidate.whiteboard()
        guard existing.layers.contains(where: { $0.id == layerID }), !existing.layers.first(where: { $0.id == layerID })!.locked else { throw ProjectError.invalidProject("unlock the destination layer") }
        if let blockID { guard existing.blocks.contains(where: { $0.id == blockID }), !existing.isBlockLocked(blockID) else { throw ProjectError.invalidProject("unlock the destination block") } }
        let sceneID: Decimal
        if let blockID, let owner = existing.beats.first(where: { $0.blockID == blockID }) { sceneID = owner.sceneID }
        else { sceneID = candidate.addScene(); try candidate.updateScene(id: sceneID, title: title) }
        // Preserve the projection taken before addScene, which otherwise introduces a duplicate legacy beat.
        var board = existing
        let destination = blockID ?? UUID().uuidString
        if blockID == nil { board.blocks.append(BoardBlock(id: destination, name: "Untitled Block", layerID: layerID, position: position)) }
        let id = UUID().uuidString
        let last = board.orderedBeats.last
        board.beats.append(BoardBeat(id: id, sceneID: sceneID, blockID: destination, title: title, order: (last?.order ?? -1) + 1, start: (last?.start ?? -1.5) + 1.5))
        try board.validate(sceneIDs: Set(candidate.scenes.map(\.id)))
        try candidate.storeWhiteboard(board)
        self = candidate
        return id
    }

    public mutating func updateBoardBeat(_ id: String, _ operation: (inout BoardBeat) throws -> Void) throws {
        try editWhiteboard { board in
            guard let i = board.beats.firstIndex(where: { $0.id == id }) else { throw ProjectError.sceneNotFound }
            try operation(&board.beats[i])
        }
    }

    public mutating func connectBoardBeats(cause: String, effect: String, reason: String = "", reference: Bool = false) throws {
        try editWhiteboard { board in
            guard cause != effect, !board.dependencies.contains(where: { $0.cause == cause && $0.effect == effect }) else { throw ProjectError.invalidProject("this connection already exists or points to itself") }
            board.dependencies.append(BoardDependency(cause: cause, effect: effect, reason: reason, reference: reference))
            _ = try board.causalOrder()
        }
    }

    public mutating func removeBoardBeats(_ ids: Set<String>) throws {
        let old = try whiteboard(), affected = Set(old.beats.filter { ids.contains($0.id) }.map(\.sceneID))
        guard old.beats.filter({ ids.contains($0.id) }).allSatisfy({ !old.isLocked($0) }),
              !scenes.contains(where: { affected.contains($0.id) && $0.isTextLocked }) else {
            throw ProjectError.invalidProject("unlock the selected beats and scene scripts before deleting")
        }
        var candidate = self
        try candidate.editWhiteboard { board in
            guard ids.isSubset(of: Set(board.beats.map(\.id))) else { throw ProjectError.sceneNotFound }
            board.beats.removeAll { ids.contains($0.id) }
            board.dependencies.removeAll { ids.contains($0.cause) || ids.contains($0.effect) }
        }
        let remaining = Set(try candidate.whiteboard().beats.map(\.sceneID))
        for id in affected.subtracting(remaining) { try candidate.editBeat(id) { $0["content"] = .string(""); $0["isDisabled"] = .bool(true) } }
        self = candidate
    }

    @discardableResult
    public mutating func splitBoardBeat(_ id: String, firstHTML: String, secondHTML: String) throws -> String {
        let nextID = UUID().uuidString
        try editWhiteboard { board in
            guard let i = board.beats.firstIndex(where: { $0.id == id }), !board.isLocked(board.beats[i]) else { throw ProjectError.invalidProject("select an unlocked beat") }
            var next = board.beats[i]; next.id = nextID; next.title += " (continued)"; next.html = secondHTML
            let ordered = board.orderedBeats, orderIndex = ordered.firstIndex { $0.id == id }!
            let after = orderIndex + 1 < ordered.count ? ordered[orderIndex + 1].order : next.order + 2
            next.order = (next.order + after) / 2; next.start += next.duration / 2; next.duration /= 2
            board.beats[i].html = firstHTML; board.beats[i].duration = next.duration
            for j in board.dependencies.indices where board.dependencies[j].cause == id { board.dependencies[j].cause = nextID }
            board.beats.append(next)
            board.dependencies.append(BoardDependency(cause: id, effect: nextID))
        }
        return nextID
    }

    public mutating func moveBoardBlocks(_ ids: Set<String>, delta: BoardPoint, layerID: String? = nil, snap: Bool = true, ripple: Bool = false) throws {
        try editWhiteboard { board in
            guard ids.isSubset(of: Set(board.blocks.map(\.id))), delta.x.isFinite, delta.y.isFinite else { throw ProjectError.invalidProject("invalid block movement") }
            var moving = ids, changed = true
            while changed {
                let children = Set(board.blocks.filter { $0.parentID.map(moving.contains) == true }.map(\.id))
                let old = moving; moving.formUnion(children); changed = moving != old
            }
            guard moving.allSatisfy({ !board.isBlockLocked($0) }), layerID.map({ id in board.layers.contains { $0.id == id && !$0.locked } }) ?? true else { throw ProjectError.invalidProject("unlock the block or destination layer") }
            let members = board.blocks.filter { moving.contains($0.id) }
            let dx = max(snap ? (delta.x / 10).rounded() * 10 : delta.x, -(members.map { $0.position.x }.min() ?? 0))
            let dy = max(snap ? (delta.y / 10).rounded() * 10 : delta.y, 32 - (members.map { $0.position.y }.min() ?? 32))
            for i in board.blocks.indices where moving.contains(board.blocks[i].id) {
                board.blocks[i].position.x = max(0, board.blocks[i].position.x + dx)
                board.blocks[i].position.y = max(32, board.blocks[i].position.y + dy)
                if let layerID { board.blocks[i].layerID = layerID }
            }
            if ripple {
                let before = Dictionary(uniqueKeysWithValues: board.beats.map { ($0.id, $0.start) })
                for i in board.beats.indices where moving.contains(board.beats[i].blockID) { board.beats[i].start = max(0, board.beats[i].start + dx / 120) }
                let requested = Dictionary(uniqueKeysWithValues: board.beats.map { ($0.id, $0.start) })
                try board.resolveCauses()
                var pushes: [String: Double] = [:]
                for beat in board.beats {
                    let baseline = moving.contains(beat.blockID) ? requested[beat.id]! : before[beat.id]!
                    pushes[beat.blockID] = max(pushes[beat.blockID] ?? 0, beat.start - baseline)
                }
                for i in board.blocks.indices { board.blocks[i].position.x += (pushes[board.blocks[i].id] ?? 0) * 120 }
            }
        }
    }

    public mutating func resizeBoardBlock(_ id: String, width: Double) throws {
        try editWhiteboard { board in
            guard let index = board.blocks.firstIndex(where: { $0.id == id }), !board.isBlockLocked(id),
                  width.isFinite, (140...2000).contains(width) else { throw ProjectError.invalidProject("unlock the block and choose a width from 140 to 2000") }
            board.blocks[index].width = width
        }
    }

    public mutating func moveBoardBeat(_ id: String, toBlock: String, before: String? = nil) throws {
        try moveBoardBeats([id], toBlock: toBlock, before: before)
    }

    public mutating func moveBoardBeats(_ ids: Set<String>, toBlock: String, before: String? = nil) throws {
        try editWhiteboard { board in
            let moving = board.orderedBeats.filter { ids.contains($0.id) }
            guard !ids.isEmpty, moving.count == ids.count, moving.allSatisfy({ !board.isLocked($0) }),
                  board.blocks.contains(where: { $0.id == toBlock }), !board.isBlockLocked(toBlock),
                  before.map({ target in !ids.contains(target) && board.beats.contains(where: { $0.id == target }) }) ?? true else { throw ProjectError.invalidProject("invalid beat move or locked block") }
            var items = board.orderedBeats.filter { !ids.contains($0.id) }
            let index = before.flatMap { target in items.firstIndex { $0.id == target } } ?? (items.lastIndex { $0.blockID == toBlock }.map { $0 + 1 } ?? items.count)
            items.insert(contentsOf: moving, at: index)
            let ranks = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, Double($0.offset)) })
            for i in board.beats.indices {
                board.beats[i].order = ranks[board.beats[i].id]!
                if ids.contains(board.beats[i].id) { board.beats[i].blockID = toBlock }
            }
        }
    }

    public mutating func mergeBoardBeats(_ ids: Set<String>) throws {
        try editWhiteboard { board in
            let chosen = board.orderedBeats.filter { ids.contains($0.id) }
            guard chosen.count == ids.count, chosen.count > 1, Set(chosen.map(\.sceneID)).count == 1,
                  chosen.allSatisfy({ !board.isLocked($0) }) else { throw ProjectError.invalidProject("select at least two unlocked snippets from one scene") }
            let inScene = board.orderedBeats.filter { $0.sceneID == chosen[0].sceneID }
            guard let first = inScene.firstIndex(where: { $0.id == chosen.first!.id }),
                  let last = inScene.firstIndex(where: { $0.id == chosen.last!.id }), last - first + 1 == chosen.count else {
                throw ProjectError.invalidProject("merge consecutive snippets to preserve their text order")
            }
            var survivor = chosen[0]
            survivor.html = chosen.map(\.html).joined()
            survivor.characters = Array(Set(chosen.flatMap(\.characters))).sorted()
            survivor.tags = Array(Set(chosen.flatMap(\.tags))).sorted()
            survivor.duration = max(0.05, (chosen.map { $0.start + $0.duration }.max() ?? survivor.start + survivor.duration) - survivor.start)
            board.beats.removeAll { ids.contains($0.id) }; board.beats.append(survivor)
            var seen = Set<String>()
            board.dependencies = board.dependencies.compactMap { edge in
                var edge = edge
                if ids.contains(edge.cause) { edge.cause = survivor.id }
                if ids.contains(edge.effect) { edge.effect = survivor.id }
                guard edge.cause != edge.effect, seen.insert(edge.cause + "→" + edge.effect).inserted else { return nil }
                return edge
            }
            _ = try board.causalOrder()
        }
    }

    public mutating func groupBoardBlocks(_ ids: Set<String>, name: String) throws {
        try editWhiteboard { board in
            let items = board.blocks.filter { ids.contains($0.id) }
            guard items.count == ids.count, items.count > 1, Set(items.map(\.layerID)).count == 1, items.allSatisfy({ !board.isBlockLocked($0.id) }) else { throw ProjectError.invalidProject("select unlocked blocks in one layer") }
            guard items.allSatisfy({ $0.parentID == items[0].parentID }) else { throw ProjectError.invalidProject("group blocks that share the same parent") }
            let selected = Set(items.map(\.id)), id = UUID().uuidString
            var group = BoardBlock(id: id, name: name, layerID: items[0].layerID,
                position: BoardPoint(x: max(0, (items.map { $0.position.x }.min() ?? 0) - 18), y: max(32, (items.map { $0.position.y }.min() ?? 0) - 28)))
            group.width = min(2000, max(224, (items.map { $0.position.x + $0.width }.max() ?? 224) - group.position.x + 18))
            group.parentID = items[0].parentID
            for i in board.blocks.indices where selected.contains(board.blocks[i].id) { board.blocks[i].parentID = id }
            board.blocks.append(group)
        }
    }

    public mutating func ungroupBoardBlocks(_ ids: Set<String>) throws {
        try editWhiteboard { board in
            let groups = board.blocks.filter { ids.contains($0.id) }
            guard !ids.isEmpty, groups.count == ids.count,
                  groups.allSatisfy({ group in !board.isBlockLocked(group.id) && board.blocks.contains(where: { $0.parentID == group.id }) }) else {
                throw ProjectError.invalidProject("select unlocked groups to ungroup")
            }
            let byID = Dictionary(uniqueKeysWithValues: board.blocks.map { ($0.id, $0) })
            for i in board.blocks.indices {
                var parent = board.blocks[i].parentID
                while let id = parent, ids.contains(id) { parent = byID[id]?.parentID }
                if parent != board.blocks[i].parentID {
                    guard !board.isBlockLocked(board.blocks[i].id) else { throw ProjectError.invalidProject("unlock the group members before ungrouping") }
                    board.blocks[i].parentID = parent
                }
            }
            let occupied = Set(board.beats.map(\.blockID))
            board.blocks.removeAll { ids.contains($0.id) && !occupied.contains($0.id) }
        }
    }

    public mutating func removeBoardBlocks(_ ids: Set<String>) throws {
        var candidate = self, board = try whiteboard(), deleting = ids, changed = true
        guard !ids.isEmpty, ids.isSubset(of: Set(board.blocks.map(\.id))) else { throw ProjectError.invalidProject("select existing blocks") }
        while changed {
            let old = deleting
            deleting.formUnion(board.blocks.filter { $0.parentID.map(deleting.contains) == true }.map(\.id))
            changed = old != deleting
        }
        guard deleting.allSatisfy({ !board.isBlockLocked($0) }) else { throw ProjectError.invalidProject("unlock the blocks before deleting") }
        let beats = Set(board.beats.filter { deleting.contains($0.blockID) }.map(\.id))
        if !beats.isEmpty { try candidate.removeBoardBeats(beats) }
        board = try candidate.whiteboard(); board.blocks.removeAll { deleting.contains($0.id) }
        try candidate.editWhiteboard { $0 = board }
        self = candidate
    }

    public mutating func applyWhiteboardStoryOrder() throws {
        var candidate = self
        try candidate.editWhiteboard { board in
            let order = board.beats.sorted { $0.start == $1.start ? ($0.order == $1.order ? $0.id < $1.id : $0.order < $1.order) : $0.start < $1.start }
            let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element.id, Double($0.offset)) })
            for i in board.beats.indices { board.beats[i].order = ranks[board.beats[i].id]! }
        }
        let board = try candidate.whiteboard(), order = board.orderedBeats
        var seen = Set<Decimal>()
        let ids = order.map(\.sceneID).filter { seen.insert($0).inserted }
        let raw = candidate.state["beats"]?.array ?? [], map = Dictionary(uniqueKeysWithValues: raw.compactMap { value -> (Decimal, JSONValue)? in
            guard let id = value.object?["id"]?.decimal else { return nil }; return (id, value)
        })
        candidate.state["beats"] = .array(ids.compactMap { map[$0] } + raw.filter { $0.object?["id"]?.decimal.map { !seen.contains($0) } ?? true })
        self = candidate
    }
}
