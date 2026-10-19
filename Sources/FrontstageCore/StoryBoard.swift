import Foundation

public struct StoryNode: Identifiable, Equatable, Sendable {
    public let id: Decimal
    public let title: String
    public let summary: String
    public let x: Double
    public let y: Double
    public let boardID: Int
    public let isDisabled: Bool
}

public struct StoryLink: Identifiable, Equatable, Sendable {
    public let from: Decimal
    public let to: Decimal
    public let label: String
    public var id: String { "\(from)->\(to)" }
}

public struct StoryGraph: Equatable, Sendable {
    public let nodes: [StoryNode]
    public let links: [StoryLink]
    public let danglingConnections: Int
    public var boardIDs: [Int] { Array(Set(nodes.map(\.boardID))).sorted() }

    public func hasPath(from: Decimal, to: Decimal) -> Bool {
        var queue = [from], visited = Set<Decimal>()
        while let next = queue.popLast() {
            if next == to { return true }
            guard visited.insert(next).inserted else { continue }
            queue.append(contentsOf: links.filter { $0.from == next }.map(\.to))
        }
        return false
    }

    public var hasCycle: Bool { links.contains { hasPath(from: $0.to, to: $0.from) } }
}

extension JSONValue {
    var decimal: Decimal? { if case .number(let value) = self { return value }; return nil }
    var double: Double? { decimal.map { NSDecimalNumber(decimal: $0).doubleValue } }
}

extension Project {
    public var storyGraph: StoryGraph {
        let nodes = (state["beats"]?.array ?? []).compactMap { value -> StoryNode? in
            guard let fields = value.object, let id = fields["id"]?.decimal else { return nil }
            return StoryNode(id: id, title: fields["title"]?.string ?? "", summary: fields["summary"]?.string ?? "",
                x: fields["x"]?.double.flatMap { $0.isFinite ? $0 : nil } ?? 0,
                y: fields["y"]?.double.flatMap { $0.isFinite ? $0 : nil } ?? 0,
                boardID: Int(clamping: NSDecimalNumber(decimal: fields["boardId"]?.decimal ?? 0).int64Value),
                isDisabled: fields["isDisabled"] == .bool(true))
        }
        let ids = Set(nodes.map(\.id))
        var dangling = 0, seen = Set<String>()
        let links = (state["connections"]?.array ?? []).compactMap { value -> StoryLink? in
            guard let item = value.object, let from = item["from"]?.decimal, let to = item["to"]?.decimal,
                  ids.contains(from), ids.contains(to) else { dangling += 1; return nil }
            let link = StoryLink(from: from, to: to, label: item["label"]?.string ?? "")
            return seen.insert(link.id).inserted ? link : nil
        }
        return StoryGraph(nodes: nodes, links: links, danglingConnections: dangling)
    }

    public mutating func moveStoryNode(_ id: Decimal, x: Double, y: Double) throws {
        guard x.isFinite, y.isFinite, abs(x) <= 1_000_000, abs(y) <= 1_000_000 else {
            throw ProjectError.invalidProject("board coordinates are out of range")
        }
        try editBeat(id) { $0["x"] = .number(Decimal(x)); $0["y"] = .number(Decimal(y)) }
    }

    public mutating func arrangeStoryBoard(_ boardID: Int) throws {
        let nodes = storyGraph.nodes.filter { $0.boardID == boardID }
        for (index, node) in nodes.enumerated() {
            try moveStoryNode(node.id, x: Double(index % 4) * 280, y: Double(index / 4) * 180)
        }
    }

    public mutating func connectScenes(from: Decimal, to: Decimal, label: String = "") throws {
        let graph = storyGraph
        guard let source = graph.nodes.first(where: { $0.id == from }),
              let target = graph.nodes.first(where: { $0.id == to }) else { throw ProjectError.sceneNotFound }
        guard source.boardID == target.boardID else { throw ProjectError.invalidProject("connect scenes on the same board") }
        guard from != to, !graph.hasPath(from: to, to: from) else { throw ProjectError.invalidProject("a connection cannot create a cycle") }
        guard !graph.links.contains(where: { $0.from == from && $0.to == to }) else {
            throw ProjectError.invalidProject("these scenes are already connected")
        }
        var links = state["connections"]?.array ?? []
        links.append(.object(["from": .number(from), "to": .number(to), "label": .string(label),
                              "style": .string("curve"), "boardId": .number(Decimal(source.boardID))]))
        state["connections"] = .array(links)
    }

    public mutating func disconnectScenes(from: Decimal, to: Decimal) {
        state["connections"] = .array((state["connections"]?.array ?? []).filter {
            !($0.object?["from"] == .number(from) && $0.object?["to"] == .number(to))
        })
    }

    public mutating func setSceneOmitted(_ id: Decimal, omitted: Bool) throws {
        try editBeat(id) { $0["isDisabled"] = .bool(omitted) }
    }

    public mutating func moveSceneInScript(_ id: Decimal, offset: Int) throws {
        var beats = state["beats"]?.array ?? []
        guard let index = beats.firstIndex(where: { $0.object?["id"] == .number(id) }) else { throw ProjectError.sceneNotFound }
        let target = min(max(0, index + offset), beats.count - 1)
        guard target != index else { return }
        let beat = beats.remove(at: index)
        beats.insert(beat, at: target)
        state["beats"] = .array(beats)
    }
}
