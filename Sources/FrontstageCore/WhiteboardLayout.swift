import Foundation

public struct BoardRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var center: BoardPoint { BoardPoint(x: x + width / 2, y: y + height / 2) }
    public func contains(_ p: BoardPoint) -> Bool { p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY }
    public func intersects(_ r: BoardRect) -> Bool { maxX >= r.x && x <= r.maxX && maxY >= r.y && y <= r.maxY }
}

/// One geometry source drives drawing, hit-testing, marquee selection and viewport culling.
public struct WhiteboardLayout: Sendable {
    public let layerRects: [String: BoardRect]
    public let blockRects: [String: BoardRect]
    public let beatRects: [String: BoardRect]
    public let width: Double
    public let height: Double
    private let cells: [String: Set<String>]
    private let largeItems: Set<String>
    private static let cellSize = 320.0

    public init(_ board: Whiteboard) {
        var layers = [String: BoardRect](), blocks = [String: BoardRect](), beats = [String: BoardRect]()
        let blockByID = Dictionary(uniqueKeysWithValues: board.blocks.map { ($0.id, $0) })
        let byBlock = Dictionary(grouping: board.orderedBeats, by: \.blockID)
        var offset = 0.0, maximumX = 1400.0
        func hidden(_ block: BoardBlock) -> Bool {
            var parent = block.parentID, seen = Set<String>()
            while let id = parent, seen.insert(id).inserted, let item = blockByID[id] {
                if item.collapsed { return true }; parent = item.parentID
            }
            return false
        }
        for layer in board.layers {
            let items = board.blocks.filter { $0.layerID == layer.id && !hidden($0) }
            let contentHeight = items.map { $0.position.y + ($0.collapsed ? 32 : Double((byBlock[$0.id] ?? []).count) * 44 + 42) }.max() ?? 0
            let layerHeight = layer.collapsed ? 38 : max(layer.height, contentHeight + 45)
            layers[layer.id] = BoardRect(x: 0, y: offset, width: 1_000_000, height: layerHeight)
            if !layer.collapsed {
                for block in items {
                    let members = byBlock[block.id] ?? []
                    let rect = BoardRect(x: 110 + block.position.x, y: offset + block.position.y,
                        width: block.width, height: block.collapsed ? 28 : max(60, Double(members.count) * 44 + 32))
                    blocks[block.id] = rect; maximumX = max(maximumX, rect.maxX + 120)
                    if !block.collapsed {
                        for (index, beat) in members.enumerated() {
                            beats[beat.id] = BoardRect(x: rect.x + 6, y: rect.y + 24 + Double(index) * 44, width: rect.width - 12, height: 40)
                        }
                    }
                }
            }
            offset += layerHeight
        }
        // Parent groups enclose descendants without changing their persisted free placement.
        for _ in 0..<min(32, board.blocks.count) {
            var changed = false
            for block in board.blocks where !block.collapsed {
                guard var r = blocks[block.id] else { continue }
                for child in board.blocks where child.parentID == block.id {
                    guard let c = blocks[child.id] else { continue }
                    let new = BoardRect(x: min(r.x, c.x - 12), y: min(r.y, c.y - 28),
                        width: max(r.maxX, c.maxX + 12) - min(r.x, c.x - 12), height: max(r.maxY, c.maxY + 12) - min(r.y, c.y - 28))
                    if new != r { changed = true; r = new }
                }
                blocks[block.id] = r
            }
            if !changed { break }
        }
        var index = [String: Set<String>](), big = Set<String>()
        for (id, rect) in beats {
            let left = Int(floor(rect.x / Self.cellSize)), right = Int(floor(rect.maxX / Self.cellSize))
            let top = Int(floor(rect.y / Self.cellSize)), bottom = Int(floor(rect.maxY / Self.cellSize))
            if (right - left + 1) * (bottom - top + 1) > 400 { big.insert(id); continue }
            for x in left...right { for y in top...bottom { index["\(x),\(y)", default: []].insert(id) } }
        }
        layerRects = layers; blockRects = blocks; beatRects = beats; width = maximumX; height = max(800, offset)
        cells = index; largeItems = big
    }

    public func beats(in rect: BoardRect) -> Set<String> {
        guard rect.width >= 0, rect.height >= 0, rect.x.isFinite, rect.y.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { return [] }
        let left = Int(floor(rect.x / Self.cellSize)), right = Int(floor(rect.maxX / Self.cellSize))
        let top = Int(floor(rect.y / Self.cellSize)), bottom = Int(floor(rect.maxY / Self.cellSize))
        if (right - left + 1) * (bottom - top + 1) > 10000 { return Set(beatRects.filter { $0.value.intersects(rect) }.map(\.key)) }
        var result = largeItems
        for x in left...right { for y in top...bottom { result.formUnion(cells["\(x),\(y)"] ?? []) } }
        return result.filter { beatRects[$0]?.intersects(rect) == true }
    }

    public func hitBeat(_ point: BoardPoint) -> String? {
        beats(in: BoardRect(x: point.x, y: point.y, width: 0, height: 0)).sorted().last { beatRects[$0]?.contains(point) == true }
    }
}
