import Foundation

public enum StoryLinkKind: String, CaseIterable, Sendable {
    case cause, reference
    public var label: String { self == .cause ? "Cause → effect" : "Reference" }
}

public struct StoryLane: Identifiable, Equatable, Sendable {
    public let id: String
    public let index: Int
    public let label: String
    public let color: String
    public let isUnused: Bool
    public let isLocked: Bool
    public let isCollapsed: Bool
}

public struct SequencerBeat: Identifiable, Equatable, Sendable {
    public let node: StoryNode
    public let lane: Int
    public var x: Double
    public var width: Double
    public let groupID: String?
    public let isLocked: Bool
    public var id: Decimal { node.id }
    public var end: Double { x + width }
    public var pages: Double { width / StorySequencer.pointsPerPage }
}

public struct StoryMilestone: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let x: Double
}

public struct StorySequenceGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let laneID: String
}

public struct SequencerIssue: Identifiable, Equatable, Sendable {
    public let id: String
    public let message: String
    public let sceneIDs: Set<Decimal>
}

/// Coordinates are document points. A page is an estimated story duration, not a printed page count.
public struct StorySequencer: Equatable, Sendable {
    public static let pointsPerPage = 120.0
    public static let laneHeight = 144.0
    public static let gap = 24.0
    public let lanes: [StoryLane]
    public let beats: [SequencerBeat]
    public let links: [StoryLink]
    public let milestones: [StoryMilestone]
    public let groups: [StorySequenceGroup]

    public var issues: [SequencerIssue] {
        var result: [SequencerIssue] = []
        let byID = Dictionary(uniqueKeysWithValues: beats.map { ($0.id, $0) })
        for link in links where link.kind == .cause {
            guard let a = byID[link.from], let b = byID[link.to] else { continue }
            if b.x + 0.001 < a.end + Self.gap {
                result.append(SequencerIssue(id: link.id, message: "\(b.node.title) occurs before its cause \(a.node.title) finishes.", sceneIDs: [a.id, b.id]))
            }
        }
        for lane in lanes {
            let items = beats.filter { $0.lane == lane.index }.sorted(by: Self.ordered)
            for (a, b) in zip(items, items.dropFirst()) where b.x + 0.001 < a.end + Self.gap {
                result.append(SequencerIssue(id: "overlap-\(a.id)-\(b.id)", message: "\(a.node.title) and \(b.node.title) overlap in \(lane.label).", sceneIDs: [a.id, b.id]))
            }
        }
        return result
    }

    public func snappedX(_ x: Double, lane: Int, excluding: Set<Decimal>, threshold: Double = 16) -> Double {
        var candidates = [(x / 30).rounded() * 30]
        for beat in beats where !excluding.contains(beat.id) {
            candidates.append(beat.x)
            if beat.lane == lane { candidates.append(beat.end + Self.gap) }
        }
        candidates.append(contentsOf: milestones.map(\.x))
        return candidates.filter { abs($0 - x) <= threshold }.min {
            abs($0 - x) == abs($1 - x) ? $0 < $1 : abs($0 - x) < abs($1 - x)
        } ?? x
    }

    static func ordered(_ a: SequencerBeat, _ b: SequencerBeat) -> Bool { a.x == b.x ? a.id < b.id : a.x < b.x }
}

extension Project {
    public func storySequencer(boardID: Int = 0) -> StorySequencer {
        let graph = storyGraph
        let rawBeats = Dictionary(uniqueKeysWithValues: (state["beats"]?.array ?? []).compactMap { value -> (Decimal, [String: JSONValue])? in
            guard let fields = value.object, let id = fields["id"]?.decimal else { return nil }
            return (id, fields)
        })
        let nodes = graph.nodes.filter { $0.boardID == boardID }
        let maximumLane = graph.nodes.map { Self.laneIndex(rawBeats[$0.id]?["trackIndex"]) }.max() ?? 0
        let storedLanes = state["causalityLanes"]?.array ?? []
        let defaults = ["Main Plot", "Character Arc", "Subplot A", "Subplot B", "Unused"]
        let palette = ["#eab308", "#38bdf8", "#ef4444", "#8b5cf6", "#22c55e"]
        let laneCount = min(128, max(storedLanes.isEmpty ? 5 : storedLanes.count, maximumLane + 1))
        let lanes = (0..<laneCount).map { index -> StoryLane in
            let item = index < storedLanes.count ? storedLanes[index].object ?? [:] : [:]
            return StoryLane(id: item["id"]?.string ?? "frontstage-lane-\(index)", index: index,
                label: item["label"]?.string ?? (index < defaults.count ? defaults[index] : "Lane \(index + 1)"),
                color: item["color"]?.string ?? palette[index % palette.count], isUnused: item["isUnused"] == .bool(true) || (item.isEmpty && index == 4),
                isLocked: item["frontstageLocked"] == .bool(true), isCollapsed: item["collapsed"] == .bool(true))
        }
        let beats = nodes.map { node -> SequencerBeat in
            let fields = rawBeats[node.id] ?? [:]
            let width = fields["w"]?.double ?? fields["durationWidth"]?.double
                ?? (fields["durationPages"]?.double.map { $0 * StorySequencer.pointsPerPage }) ?? 220
            let rawX = fields["x"]?.double ?? (fields["startTime"]?.double ?? 0) * StorySequencer.pointsPerPage
            return SequencerBeat(node: node, lane: Self.laneIndex(fields["trackIndex"]),
                x: rawX.isFinite ? max(0, min(1_000_000, rawX)) : 0,
                width: width.isFinite ? min(2400, max(60, width)) : 220,
                groupID: fields["groupId"]?.string, isLocked: fields["frontstageLocked"] == .bool(true))
        }
        let ids = Set(nodes.map(\.id))
        let milestones = (state["sectionBreaks"]?.array ?? []).compactMap { value -> StoryMilestone? in
            guard let item = value.object, let id = item["id"]?.string, let unit = item["unit"]?.double,
                  unit.isFinite, unit >= 0, unit <= 1_000_000 / StorySequencer.pointsPerPage else { return nil }
            return StoryMilestone(id: id, title: item["title"]?.string ?? "Milestone", x: unit * StorySequencer.pointsPerPage)
        }
        let groups = (state["causalityGroups"]?.array ?? []).compactMap { value -> StorySequenceGroup? in
            guard let item = value.object, let id = item["id"]?.string else { return nil }
            return StorySequenceGroup(id: id, title: item["title"]?.string ?? "Sequence", laneID: item["laneId"]?.string ?? "")
        }
        return StorySequencer(lanes: lanes, beats: beats, links: graph.links.filter { ids.contains($0.from) && ids.contains($0.to) }, milestones: milestones, groups: groups)
    }

    private static func laneIndex(_ value: JSONValue?) -> Int {
        min(127, max(0, NSDecimalNumber(decimal: value?.decimal ?? 0).intValue))
    }

    public mutating func updateStoryLane(_ index: Int, label: String? = nil, color: String? = nil,
                                         locked: Bool? = nil, collapsed: Bool? = nil) throws {
        let lanes = storySequencer().lanes
        guard lanes.indices.contains(index), state["causalityLanes"] == nil || state["causalityLanes"]?.array != nil else {
            throw ProjectError.invalidProject("the lane cannot be edited")
        }
        var stored = state["causalityLanes"]?.array ?? []
        for lane in lanes.dropFirst(stored.count) {
            stored.append(.object(["id": .string(lane.id), "label": .string(lane.label), "color": .string(lane.color), "isUnused": .bool(lane.isUnused)]))
        }
        guard var fields = stored[index].object else { throw ProjectError.invalidProject("the lane has unsupported data") }
        if let label { fields["label"] = .string(label) }
        if let color { fields["color"] = .string(color) }
        if let locked { fields["frontstageLocked"] = .bool(locked) }
        if let collapsed { fields["collapsed"] = .bool(collapsed) }
        stored[index] = .object(fields)
        state["causalityLanes"] = .array(stored)
    }

    @discardableResult
    public mutating func addStoryLane(label: String) throws -> Int {
        let count = storySequencer().lanes.count
        guard count < 128 else { throw ProjectError.invalidProject("maximum 128 story lanes") }
        try updateStoryLane(count - 1)
        var stored = state["causalityLanes"]!.array!
        stored.append(.object(["id": .string(UUID().uuidString), "label": .string(label), "color": .string("#ec4899")]))
        state["causalityLanes"] = .array(stored)
        return count
    }

    public mutating func setStoryBeatLocked(_ id: Decimal, locked: Bool) throws {
        try editBeat(id) { $0["frontstageLocked"] = .bool(locked) }
    }

    public mutating func setStoryBoard(_ id: Decimal, boardID: Int) throws {
        try editBeat(id) { $0["boardId"] = .number(Decimal(boardID)) }
    }

    /// One atomic gesture. All lane and causal constraints are solved together in topological order.
    /// This handles converging causes and propagates changes caused by lane collisions as well.
    public mutating func moveStoryBeats(_ ids: Set<Decimal>, by delta: Double, toLane: Int? = nil,
                                        boardID: Int = 0, ripple: Bool = true, snap: Bool = true) throws {
        let model = storySequencer(boardID: boardID)
        guard !ids.isEmpty, delta.isFinite, abs(delta) <= 1_000_000 else { throw ProjectError.invalidProject("invalid story movement") }
        var beats = model.beats
        let selected = beats.filter { ids.contains($0.id) }.sorted(by: StorySequencer.ordered)
        guard selected.count == ids.count else { throw ProjectError.sceneNotFound }
        if let toLane { guard model.lanes.indices.contains(toLane) else { throw ProjectError.invalidProject("missing story lane") } }
        guard selected.allSatisfy({ !$0.isLocked && !model.lanes[$0.lane].isLocked }),
              toLane.map({ !model.lanes[$0].isLocked }) ?? true else { throw ProjectError.invalidProject("unlock the beat or lane before moving it") }
        let anchor = selected[0]
        var movement = max(delta, -(selected.map(\.x).min() ?? 0))
        if snap { movement = max(-anchor.x, model.snappedX(anchor.x + movement, lane: toLane ?? anchor.lane, excluding: ids) - anchor.x) }
        for index in beats.indices where ids.contains(beats[index].id) {
            let old = beats[index]
            beats[index] = SequencerBeat(node: old.node, lane: toLane ?? old.lane, x: old.x + movement,
                                        width: old.width, groupID: old.groupID, isLocked: old.isLocked)
        }
        if ripple { beats = try Self.solveStory(beats, original: model.beats, lanes: model.lanes, links: model.links, preserveLaneOrder: toLane == nil) }
        try commitStory(beats, comparedTo: model.beats)
    }

    public mutating func resizeStoryBeat(_ id: Decimal, pages: Double, boardID: Int = 0, ripple: Bool = true) throws {
        guard pages.isFinite, pages >= 0.5, pages <= 20 else { throw ProjectError.invalidProject("story duration must be between 0.5 and 20 pages") }
        let model = storySequencer(boardID: boardID)
        var beats = model.beats
        guard let index = beats.firstIndex(where: { $0.id == id }) else { throw ProjectError.sceneNotFound }
        guard !beats[index].isLocked, !model.lanes[beats[index].lane].isLocked else { throw ProjectError.invalidProject("unlock the beat or lane before resizing it") }
        beats[index].width = pages * StorySequencer.pointsPerPage
        if ripple { beats = try Self.solveStory(beats, original: model.beats, lanes: model.lanes, links: model.links) }
        try commitStory(beats, comparedTo: model.beats)
    }

    public mutating func resolveStory(boardID: Int = 0, compactLane: Int? = nil) throws {
        let model = storySequencer(boardID: boardID)
        var beats = model.beats
        if let lane = compactLane {
            guard model.lanes.indices.contains(lane), !model.lanes[lane].isLocked else { throw ProjectError.invalidProject("unlock the lane before compacting it") }
            let ordered = beats.indices.filter { beats[$0].lane == lane }.sorted { StorySequencer.ordered(beats[$0], beats[$1]) }
            var cursor = 0.0
            for i in ordered {
                if !beats[i].isLocked { beats[i].x = cursor }
                cursor = beats[i].end + StorySequencer.gap
            }
        }
        beats = try Self.solveStory(beats, original: model.beats, lanes: model.lanes, links: model.links)
        try commitStory(beats, comparedTo: model.beats)
    }

    private static func solveStory(_ input: [SequencerBeat], original: [SequencerBeat], lanes: [StoryLane],
                                    links: [StoryLink], preserveLaneOrder: Bool = true) throws -> [SequencerBeat] {
        var beats = input
        let indices = Dictionary(uniqueKeysWithValues: beats.indices.map { (beats[$0].id, $0) })
        var successors = [Decimal: Set<Decimal>](), indegree = Dictionary(uniqueKeysWithValues: beats.map { ($0.id, 0) })
        func edge(_ a: Decimal, _ b: Decimal) {
            if successors[a, default: []].insert(b).inserted { indegree[b, default: 0] += 1 }
        }
        for lane in lanes {
            let order = (preserveLaneOrder ? original : beats).filter { $0.lane == lane.index }.sorted(by: StorySequencer.ordered)
            for (a, b) in zip(order, order.dropFirst()) { edge(a.id, b.id) }
        }
        for link in links where link.kind == .cause { edge(link.from, link.to) }
        var queue = beats.filter { indegree[$0.id] == 0 }.sorted(by: StorySequencer.ordered).map(\.id), cursor = 0
        while cursor < queue.count {
            let id = queue[cursor]; cursor += 1
            guard let i = indices[id] else { continue }
            for next in (successors[id] ?? []).sorted() {
                guard let j = indices[next] else { continue }
                let required = beats[i].end + StorySequencer.gap
                if beats[j].x + 0.001 < required {
                    guard !beats[j].isLocked, !lanes[beats[j].lane].isLocked else {
                        throw ProjectError.invalidProject("\(beats[j].node.title) is locked and blocks the ripple")
                    }
                    beats[j].x = required
                }
                indegree[next, default: 0] -= 1
                if indegree[next] == 0 { queue.append(next) }
            }
        }
        guard cursor == beats.count else { throw ProjectError.invalidProject("causes conflict with lane order; move the effect after its cause with Ripple off, or remove the conflicting link") }
        return beats
    }

    private mutating func commitStory(_ beats: [SequencerBeat], comparedTo original: [SequencerBeat]) throws {
        guard beats.allSatisfy({ $0.x.isFinite && $0.x >= 0 && $0.end <= 1_000_000 }) else { throw ProjectError.invalidProject("story coordinates are out of range") }
        var copy = self
        let before = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0) })
        for beat in beats where before[beat.id] != beat {
            try copy.editBeat(beat.id) {
                $0["x"] = .number(Decimal(beat.x)); $0["startTime"] = .number(Decimal(beat.x / StorySequencer.pointsPerPage))
                $0["y"] = .number(Decimal(Double(beat.lane) * StorySequencer.laneHeight + 36))
                $0["trackIndex"] = .number(Decimal(beat.lane))
                $0["w"] = .number(Decimal(beat.width)); $0["durationWidth"] = .number(Decimal(beat.width))
                $0["durationPages"] = .number(Decimal(beat.pages))
            }
        }
        // Keep the legacy timeline's group bounds consistent with member movement and duration.
        if var groups = copy.state["causalityGroups"]?.array {
            for index in groups.indices {
                guard var fields = groups[index].object, let id = fields["id"]?.string else { continue }
                let members = beats.filter { $0.groupID == id }
                guard let first = members.first, let start = members.map(\.x).min(), let end = members.map(\.end).max() else { continue }
                fields["startUnit"] = .number(Decimal(start / StorySequencer.pointsPerPage))
                fields["durationUnits"] = .number(Decimal((end - start) / StorySequencer.pointsPerPage))
                if Set(members.map(\.lane)).count == 1 { fields["laneId"] = .string(copy.storySequencer(boardID: first.node.boardID).lanes[first.lane].id) }
                groups[index] = .object(fields)
            }
            copy.state["causalityGroups"] = .array(groups)
        }
        self = copy
    }

    public mutating func updateStoryLink(from: Decimal, to: Decimal, label: String) throws {
        guard var links = state["connections"]?.array,
              let index = links.firstIndex(where: { $0.object?["from"]?.decimal == from && $0.object?["to"]?.decimal == to }),
              var fields = links[index].object else { throw ProjectError.invalidProject("missing story connection") }
        fields["label"] = .string(label); links[index] = .object(fields)
        state["connections"] = .array(links)
    }

    public mutating func renameStoryGroup(_ id: String, title: String) throws {
        guard var groups = state["causalityGroups"]?.array,
              let index = groups.firstIndex(where: { $0.object?["id"]?.string == id }),
              var fields = groups[index].object else { throw ProjectError.invalidProject("missing story sequence") }
        fields["title"] = .string(title); groups[index] = .object(fields)
        state["causalityGroups"] = .array(groups)
    }

    public mutating func removeStoryBeats(_ ids: Set<Decimal>) throws {
        let beats = (state["beats"]?.array ?? [])
        let found = beats.filter { $0.object?["id"]?.decimal.map(ids.contains) == true }
        guard found.count == ids.count else { throw ProjectError.sceneNotFound }
        state["beats"] = .array(beats.filter { $0.object?["id"]?.decimal.map(ids.contains) != true })
        if let connections = state["connections"]?.array {
            state["connections"] = .array(connections.filter {
                $0.object?["from"]?.decimal.map(ids.contains) != true && $0.object?["to"]?.decimal.map(ids.contains) != true
            })
        }
    }

    @discardableResult
    public mutating func groupStoryBeats(_ ids: Set<Decimal>, title: String, boardID: Int = 0) throws -> String {
        let model = storySequencer(boardID: boardID), selected = storySequencer(boardID: boardID).beats.filter { ids.contains($0.id) }
        guard !selected.isEmpty, selected.count == ids.count, Set(selected.map(\.lane)).count == 1,
              selected.allSatisfy({ !$0.isLocked && !model.lanes[$0.lane].isLocked }),
              state["causalityGroups"] == nil || state["causalityGroups"]?.array != nil else { throw ProjectError.invalidProject("select unlocked beats in one lane to group them") }
        let id = UUID().uuidString, start = selected.map(\.x).min() ?? 0, end = selected.map(\.end).max() ?? 0
        var copy = self
        var groups = state["causalityGroups"]?.array ?? []
        groups.append(.object(["id": .string(id), "title": .string(title), "laneId": .string(model.lanes[selected[0].lane].id),
                               "startUnit": .number(Decimal(start / StorySequencer.pointsPerPage)), "durationUnits": .number(Decimal((end - start) / StorySequencer.pointsPerPage)), "boardId": .number(Decimal(boardID))]))
        copy.state["causalityGroups"] = .array(groups)
        for beat in selected { try copy.editBeat(beat.id) { $0["groupId"] = .string(id) } }
        self = copy
        return id
    }

    public mutating func ungroupStoryBeats(_ ids: Set<Decimal>) throws {
        var copy = self
        for id in ids { try copy.editBeat(id) { $0.removeValue(forKey: "groupId") } }
        self = copy
    }

    @discardableResult
    public mutating func addStoryMilestone(title: String, page: Double) throws -> String {
        guard page.isFinite, page >= 0, page <= 1_000_000 / StorySequencer.pointsPerPage,
              state["sectionBreaks"] == nil || state["sectionBreaks"]?.array != nil else { throw ProjectError.invalidProject("invalid milestone position") }
        var items = state["sectionBreaks"]?.array ?? []
        let id = UUID().uuidString
        items.append(.object(["id": .string(id), "title": .string(title), "unit": .number(Decimal(page)), "type": .string("custom")]))
        state["sectionBreaks"] = .array(items)
        return id
    }

    public mutating func removeStoryMilestone(_ id: String) {
        state["sectionBreaks"] = .array((state["sectionBreaks"]?.array ?? []).filter { $0.object?["id"]?.string != id })
    }

    /// Explicitly updates editorial order; moving beats alone never silently reorders the screenplay.
    public mutating func applyStoryOrder(boardID: Int = 0) throws {
        let model = storySequencer(boardID: boardID)
        let ordered = model.beats.sorted(by: StorySequencer.ordered).map(\.id)
        var beats = state["beats"]?.array ?? []
        let byID = Dictionary(uniqueKeysWithValues: beats.compactMap { value -> (Decimal, JSONValue)? in
            guard let id = value.object?["id"]?.decimal else { return nil }; return (id, value)
        })
        let ids = Set(ordered)
        var cursor = 0
        for i in beats.indices where beats[i].object?["id"]?.decimal.map({ ids.contains($0) }) == true {
            beats[i] = byID[ordered[cursor]]!; cursor += 1
        }
        state["beats"] = .array(beats)
    }
}
