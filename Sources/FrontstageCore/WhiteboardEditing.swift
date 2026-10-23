import Foundation

extension Project {
    public mutating func splitBoardGroup(at beatID: String) throws {
        try editWhiteboard { board in
            guard let beat = board.beats.first(where: { $0.id == beatID }), let group = board.blocks.first(where: { $0.id == beat.blockID && $0.containerKind == "beatGroup" }), !board.isBlockLocked(group.id) else { throw ProjectError.invalidProject("Choose an unlocked group member") }
            let members = board.orderedBeats.filter { $0.blockID == group.id }
            guard let index = members.firstIndex(where: { $0.id == beatID }), index > 0 else { throw ProjectError.invalidProject("Split after the first beat of a group") }
            let ids = Set(members[index...].map(\.id))
            guard !board.beats.contains(where: { ids.contains($0.id) && $0.locked }) else { throw ProjectError.invalidProject("Unlock the group members") }
            var next = group; next.id = UUID().uuidString; next.name += " (2)"; next.position.x += group.width + 24
            board.blocks.append(next)
            for i in board.beats.indices where ids.contains(board.beats[i].id) { board.beats[i].blockID = next.id; board.beats[i].position = nil }
        }
    }
    public mutating func mergeBoardContainers(_ ids: Set<String>) throws {
        try editWhiteboard { board in
            let containers = board.blocks.filter { ids.contains($0.id) }.sorted { $0.position.x < $1.position.x }
            guard containers.count == ids.count, let target = containers.first, containers.count > 1,
                  containers.allSatisfy({ $0.layerID == target.layerID && $0.parentID == target.parentID && $0.containerKind == target.containerKind && $0.standalone != true && !board.isBlockLocked($0.id) }),
                  !board.beats.contains(where: { ids.contains($0.blockID) && $0.locked }) else { throw ProjectError.invalidProject("Select unlocked sibling groups or blocks of the same kind") }
            let map = Dictionary(uniqueKeysWithValues: containers.map { ($0.id, $0) })
            for i in board.beats.indices where ids.contains(board.beats[i].blockID) {
                let source = map[board.beats[i].blockID]!
                if target.containerKind == "beatGroup" { board.beats[i].position = nil }
                else { let p = board.beats[i].position ?? .init(x: 6, y: 24); board.beats[i].position = .init(x: max(6, source.position.x + p.x - target.position.x), y: max(24, source.position.y + p.y - target.position.y)) }
                board.beats[i].blockID = target.id
            }
            for i in board.blocks.indices where board.blocks[i].parentID.map(ids.contains) == true { board.blocks[i].parentID = target.id }
            board.blocks.removeAll { ids.contains($0.id) && $0.id != target.id }
            if let i = board.blocks.firstIndex(where: { $0.id == target.id }) {
                board.blocks[i].width = min(2000, max(target.width, containers.map { $0.position.x + $0.width - target.position.x }.max() ?? target.width))
                board.blocks[i].synopsis = containers.compactMap(\.synopsis).filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
    }
    public mutating func pushWhiteboard(from x: Double, by distance: Double) throws {
        let board = try whiteboard()
        let roots = board.blocks.filter { $0.parentID == nil && $0.position.x >= x }
        guard !roots.isEmpty else { return }
        var delta = distance
        if delta < 0 {
            for root in roots {
                let edge = board.blocks.filter { $0.parentID == nil && $0.layerID == root.layerID && $0.position.x < x }.map { $0.position.x + $0.width + 12 }.max() ?? 0
                delta = max(delta, min(0, edge - root.position.x))
            }
        }
        try moveBoardBlocks(Set(roots.map(\.id)), delta: .init(x: delta, y: 0), ripple: false)
    }
}

extension Project {
    public mutating func splitBoardBlock(_ id: String, at x: Double) throws {
        try editWhiteboard { board in
            guard let block = board.blocks.first(where: { $0.id == id && $0.containerKind != "beatGroup" && $0.standalone != true }), !board.isBlockLocked(id), x > block.position.x + 12 else { throw ProjectError.invalidProject("Split inside an unlocked block") }
            let children = board.blocks.filter { $0.parentID == id && $0.position.x >= x }
            let beats = board.beats.filter { $0.blockID == id && block.position.x + ($0.position?.x ?? 6) >= x }
            guard !children.isEmpty || !beats.isEmpty else { throw ProjectError.invalidProject("Choose a split point with content to its right") }
            guard children.allSatisfy({ !board.isBlockLocked($0.id) }), !beats.contains(where: \.locked) else { throw ProjectError.invalidProject("Unlock the content before splitting") }
            var next = block; next.id = UUID().uuidString; next.name += " (2)"; next.position.x = x; next.width = max(140, block.position.x + block.width - x)
            let childIDs = Set(children.map(\.id)), beatIDs = Set(beats.map(\.id))
            for i in board.blocks.indices where childIDs.contains(board.blocks[i].id) { board.blocks[i].parentID = next.id }
            for i in board.beats.indices where beatIDs.contains(board.beats[i].id) {
                let p = board.beats[i].position ?? .init(x: 6, y: 24)
                board.beats[i].blockID = next.id; board.beats[i].position = .init(x: max(6, block.position.x + p.x - x), y: p.y)
            }
            if let i = board.blocks.firstIndex(where: { $0.id == id }) { board.blocks[i].width = max(140, x - block.position.x - 12) }
            board.blocks.append(next)
        }
    }
}

extension Project {
    public mutating func reorderTimelineBeats(_ ids: Set<String>, before targetID: String) throws {
        try editWhiteboard { board in
            let ordered = board.orderedBeats, moving = ordered.filter { ids.contains($0.id) }
            guard !moving.isEmpty, moving.count == ids.count, !ids.contains(targetID), ordered.contains(where: { $0.id == targetID }), !moving.contains(where: { board.isLocked($0) }) else { throw ProjectError.invalidProject("Choose unlocked beats and a different insertion point") }
            var sequence = ordered.filter { !ids.contains($0.id) }
            let index = sequence.firstIndex { $0.id == targetID }!
            sequence.insert(contentsOf: moving, at: index)
            let ranks = Dictionary(uniqueKeysWithValues: sequence.enumerated().map { ($0.element.id, Double($0.offset)) })
            for group in board.blocks where group.containerKind == "beatGroup" {
                let members = sequence.enumerated().filter { $0.element.blockID == group.id }.map(\.offset)
                if let first = members.first, let last = members.last, last - first + 1 != members.count { throw ProjectError.invalidProject("Keep a group's beats together, or convert it to free beats before intercutting") }
            }
            for i in board.beats.indices {
                let rank = ranks[board.beats[i].id]!
                if rank != board.beats[i].order && board.isLocked(board.beats[i]) { throw ProjectError.invalidProject("This reorder would move a locked beat") }
                board.beats[i].order = rank
            }
            let original = board
            for i in board.blocks.indices {
                let id = board.blocks[i].id
                var descendants: Set<String> = [id]
                while true { let next = descendants.union(board.blocks.filter { $0.parentID.map(descendants.contains) == true }.map(\.id)); if next == descendants { break }; descendants = next }
                let members = board.beats.filter { descendants.contains($0.blockID) }
                guard let first = members.map(\.order).min() else { continue }
                let x = 40 + first * 60
                if x != board.blocks[i].position.x && original.isBlockLocked(id) { throw ProjectError.invalidProject("This reorder would move a locked container") }
                board.blocks[i].position.x = x
                if board.blocks[i].containerKind == "beatGroup" {
                    for j in board.beats.indices where board.beats[j].blockID == id { board.beats[j].position = nil }
                } else if board.blocks[i].standalone != true {
                    for j in board.beats.indices where board.beats[j].blockID == id { board.beats[j].position = .init(x: 6 + (board.beats[j].order - first) * 60, y: board.beats[j].position?.y ?? 24) }
                }
            }
        }
    }
}
