import Foundation

public enum BoardPaletteItem: String, CaseIterable, Sendable { case lane, block, group, beat }

extension Whiteboard {
    public func usesBlocks(_ layerID: String) -> Bool {
        layers.first { $0.id == layerID }?.useBlocks == true
    }
}

extension Project {
    public mutating func setLayerUsesBlocks(_ id: String, enabled: Bool) throws {
        try editWhiteboard { board in
            guard let index = board.layers.firstIndex(where: { $0.id == id }), !board.layers[index].locked else { throw ProjectError.invalidProject("Unlock the layer first") }
            board.layers[index].useBlocks = enabled
            // Validation rejects incompatible existing content atomically, without inventing containers.
        }
    }

    @discardableResult
    public mutating func createBoardItem(_ kind: BoardPaletteItem, layerID: String, position: BoardPoint, parentID: String? = nil) throws -> String {
        var candidate = self
        let board = try whiteboard()
        guard position.x.isFinite, position.y.isFinite, abs(position.x) <= 1_000_000, abs(position.y) <= 1_000_000 else { throw ProjectError.invalidProject("Invalid drop position") }
        if kind == .lane {
            var lane = BoardLayer(name: "New Layer"); lane.useBlocks = false
            try candidate.editWhiteboard { board in
                let index = board.layers.firstIndex { $0.id == layerID }.map { $0 + 1 } ?? board.layers.count
                board.layers.insert(lane, at: index)
            }
            self = candidate; return lane.id
        }
        guard board.layers.contains(where: { $0.id == layerID && !$0.locked }) else { throw ProjectError.invalidProject("Unlock the destination layer") }
        let parent = parentID.flatMap { id in board.blocks.first { $0.id == id } }
        if let parentID { guard let parent, parent.layerID == layerID, !board.isBlockLocked(parentID), parent.standalone != true else { throw ProjectError.invalidProject("Choose an unlocked block or group") } }
        if kind == .block {
            guard board.usesBlocks(layerID) else { throw ProjectError.invalidProject("Enable Use Blocks in the layer settings before creating a block") }
        } else if board.usesBlocks(layerID) && parent == nil {
            throw ProjectError.invalidProject("This layer uses blocks. Drop inside a block")
        }
        if board.layers.first(where: { $0.id == layerID })?.useBlocks == nil && !board.blocks.contains(where: { $0.layerID == layerID }) {
            try candidate.setLayerUsesBlocks(layerID, enabled: false)
        }
        if kind == .beat {
            let id = try candidate.addBoardBeat(blockID: parentID, layerID: layerID, position: position)
            try candidate.editWhiteboard { board in
                if let index = board.beats.firstIndex(where: { $0.id == id }) {
                    if let parent { board.beats[index].position = .init(x: max(6, position.x - parent.position.x), y: max(24, position.y - parent.position.y)) }
                    else if let owner = board.blocks.firstIndex(where: { $0.id == board.beats[index].blockID }) { board.blocks[owner].standalone = true }
                }
            }
            self = candidate; return id
        }
        var container = BoardBlock(name: kind == .group ? "Beat Group" : "Untitled Block", layerID: layerID, position: position, width: kind == .block ? 500 : 224)
        container.containerKind = kind == .group ? "beatGroup" : nil
        container.parentID = parentID
        try candidate.editWhiteboard { $0.blocks.append(container) }
        self = candidate; return container.id
    }
}
