#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

struct WhiteboardCanvas: NSViewRepresentable {
    @ObservedObject var workspace: Workspace
    @Binding var selection: Set<String>
    @Binding var blockSelection: Set<String>
    var drawing: Bool
    var fitRequest: Int

    func makeNSView(context: Context) -> NativeWhiteboard {
        let view = NativeWhiteboard()
        view.workspace = workspace
        return view
    }
    func updateNSView(_ view: NativeWhiteboard, context: Context) {
        view.workspace = workspace; view.board = workspace.whiteboard
        view.selection = selection; view.blockSelection = blockSelection; view.drawingMode = drawing
        view.selected = { ids, blocks in selection = ids; blockSelection = blocks }
        if view.fitRequest != fitRequest { view.fitRequest = fitRequest; view.fitSelection() }
        view.needsDisplay = true
    }
}

@MainActor
final class NativeWhiteboard: NSView {
    weak var workspace: Workspace?
    var board = Whiteboard() { didSet { geometry = WhiteboardLayout(board) } }
    private var geometry = WhiteboardLayout(Whiteboard())
    var selection = Set<String>()
    var blockSelection = Set<String>()
    var selected: ((Set<String>, Set<String>) -> Void)?
    var drawingMode = false
    var fitRequest = 0
    private var dragStart: BoardPoint?
    private var viewStart = NSPoint.zero
    private var dragDelta = BoardPoint()
    private var panStart: BoardPoint?
    private var movingBlocks = false
    private var movingBeat: String?
    private var marquee: BoardRect?
    private var stroke: [BoardPoint] = []
    private var spaceHeld = false
    private var contextBeat: String?
    private var contextBlock: String?
    private var contextPoint = BoardPoint()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var zoom: Double { board.viewport.zoom }
    private func world(_ point: NSPoint) -> BoardPoint {
        BoardPoint(x: point.x / zoom + board.viewport.origin.x, y: point.y / zoom + board.viewport.origin.y)
    }
    private func screenRect(_ rect: BoardRect) -> NSRect? {
        guard let window else { return nil }
        let local = NSRect(x: (rect.x - board.viewport.origin.x) * zoom, y: (rect.y - board.viewport.origin.y) * zoom, width: rect.width * zoom, height: rect.height * zoom)
        return window.convertToScreen(convert(local, to: nil))
    }
    private var visible: BoardRect {
        BoardRect(x: board.viewport.origin.x, y: board.viewport.origin.y, width: bounds.width / zoom, height: bounds.height / zoom)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.46, alpha: 1).setFill(); bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -board.viewport.origin.x, y: -board.viewport.origin.y)
        let viewport = visible
        for (index, layer) in board.layers.enumerated() {
            guard let rect = geometry.layerRects[layer.id], rect.intersects(viewport) else { continue }
            NSColor(calibratedWhite: index % 2 == 0 ? 0.49 : 0.46, alpha: 1).setFill()
            NSRect(x: viewport.x, y: rect.y, width: viewport.width, height: rect.height).fill()
            label("\(layer.collapsed ? "▸" : "▾") \(layer.name)\(layer.locked ? "  🔒" : "")", at: NSRect(x: max(5, viewport.x + 5), y: rect.y + 9, width: 145, height: 18), size: 10, color: .white)
        }
        let byID = Dictionary(uniqueKeysWithValues: board.beats.map { ($0.id, $0) })
        let issueBeats = Set(board.issues.flatMap(\.beatIDs))
        for edge in board.dependencies {
            guard let a = geometry.beatRects[edge.cause], let b = geometry.beatRects[edge.effect] else { continue }
            let extent = BoardRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x) + max(a.width, b.width), height: abs(a.y - b.y) + max(a.height, b.height))
            guard extent.intersects(viewport) else { continue }
            let start = NSPoint(x: a.maxX, y: a.center.y), end = NSPoint(x: b.x, y: b.center.y)
            let path = NSBezierPath(); path.move(to: start)
            let bend = max(30, abs(end.x - start.x) * 0.45)
            path.curve(to: end, controlPoint1: NSPoint(x: start.x + bend, y: start.y), controlPoint2: NSPoint(x: end.x - bend, y: end.y))
            let invalid = !edge.reference && (byID[edge.effect]?.start ?? 0) < (byID[edge.cause]?.start ?? 0) + (byID[edge.cause]?.duration ?? 0)
            (invalid ? NSColor.systemRed : selection.contains(edge.cause) || selection.contains(edge.effect) ? NSColor.systemCyan : NSColor(calibratedWhite: 0.82, alpha: 0.65)).setStroke()
            path.lineWidth = 1.3 / max(0.6, zoom)
            if edge.reference { path.setLineDash([4, 4], count: 2, phase: 0) }
            path.stroke()
            let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: end.x - 6, y: end.y - 3)); arrow.line(to: end); arrow.line(to: NSPoint(x: end.x - 6, y: end.y + 3)); arrow.stroke()
        }
        let groups = Set(board.blocks.compactMap(\.parentID))
        let sortedBlocks = board.blocks.sorted { a, b in
            if groups.contains(a.id) != groups.contains(b.id) { return groups.contains(a.id) }
            return a.id < b.id
        }
        for block in sortedBlocks {
            guard var rect = geometry.blockRects[block.id], rect.intersects(viewport) else { continue }
            if movingBlocks && blockSelection.contains(block.id) { rect.x += dragDelta.x; rect.y += dragDelta.y }
            let frame = NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            NSColor(calibratedWhite: 0.9, alpha: groups.contains(block.id) ? 0.10 : 0.30).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).fill()
            (blockSelection.contains(block.id) ? NSColor.white : NSColor(calibratedWhite: 1, alpha: 0.15)).setStroke()
            NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).stroke()
            NSColor(calibratedWhite: 0.33, alpha: 0.9).setFill()
            let tab = NSRect(x: rect.x + 12, y: rect.y - 17, width: min(rect.width - 24, max(90, Double(block.name.count) * 6)), height: 20)
            NSBezierPath(roundedRect: tab, xRadius: 3, yRadius: 3).fill()
            label("\(block.collapsed ? "▸ " : "")\(block.name)", at: tab.insetBy(dx: 6, dy: 3), size: 10, color: .white)
        }
        for id in geometry.beats(in: viewport) {
            guard let beat = byID[id], var rect = geometry.beatRects[id] else { continue }
            if movingBlocks && blockSelection.contains(beat.blockID) { rect.x += dragDelta.x; rect.y += dragDelta.y }
            let frame = NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            let color = NSColor(boardHex: beat.color)
            (beat.omitted || board.isUnused(beat) ? color.withAlphaComponent(0.25) : color).setFill()
            let path = NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4); path.fill()
            (selection.contains(id) ? NSColor.white : NSColor(calibratedWhite: 1, alpha: 0.3)).setStroke()
            path.lineWidth = selection.contains(id) ? 2 / zoom : 1; path.stroke()
            label(beat.title, at: frame.insetBy(dx: 7, dy: 5), size: 11, color: .white)
            if issueBeats.contains(id) {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: NSRect(x: frame.maxX - 11, y: frame.minY - 7, width: 16, height: 16)).fill()
                label("!", at: NSRect(x: frame.maxX - 6, y: frame.minY - 6, width: 10, height: 14), size: 11, color: .white)
            }
        }
        for item in board.strokes { drawStroke(item.points, color: NSColor(boardHex: item.color), width: item.width) }
        if !stroke.isEmpty { drawStroke(stroke, color: .systemYellow, width: 2) }
        if let marquee {
            NSColor.systemCyan.withAlphaComponent(0.12).setFill()
            let frame = NSRect(x: marquee.x, y: marquee.y, width: marquee.width, height: marquee.height)
            frame.fill(); NSColor.systemCyan.setStroke(); NSBezierPath(rect: frame).stroke()
        }
        context.restoreGState()
    }

    private func label(_ string: String, at rect: NSRect, size: CGFloat, color: NSColor) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: paragraph])
    }
    private func drawStroke(_ points: [BoardPoint], color: NSColor, width: Double) {
        guard let first = points.first else { return }
        let path = NSBezierPath(); path.move(to: NSPoint(x: first.x, y: first.y))
        for point in points.dropFirst() { path.line(to: NSPoint(x: point.x, y: point.y)) }
        path.lineWidth = width; path.lineCapStyle = .round; color.setStroke(); path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil), worldPoint = world(point)
        viewStart = point; dragStart = worldPoint; dragDelta = .init()
        if spaceHeld || event.modifierFlags.contains(.option) { panStart = board.viewport.origin; return }
        if drawingMode { stroke = [worldPoint]; return }
        if let beat = geometry.hitBeat(worldPoint) {
            if let cause = workspace?.pendingBoardCauseID {
                workspace?.edit("Create Dependency") { try $0.connectBoardBeats(cause: cause, effect: beat) }
                workspace?.pendingBoardCauseID = nil; return
            }
            if event.modifierFlags.contains(.shift) { if !selection.insert(beat).inserted { selection.remove(beat) } }
            else if !selection.contains(beat) { selection = [beat] }
            blockSelection = []; movingBeat = beat
            workspace?.selectBoardBeat(beat)
            selected?(selection, blockSelection)
            if event.clickCount == 2 { openPopup(beat); movingBeat = nil }
        } else if let block = hitBlock(worldPoint) {
            if event.modifierFlags.contains(.shift) { if !blockSelection.insert(block).inserted { blockSelection.remove(block) } }
            else if !blockSelection.contains(block) { blockSelection = [block] }
            selection = Set(board.beats.filter { blockSelection.contains($0.blockID) }.map(\.id))
            movingBlocks = true; selected?(selection, blockSelection)
            if let id = selection.sorted().first { workspace?.selectBoardBeat(id) }
        } else {
            selection = []; blockSelection = []; selected?([], [])
            if event.clickCount == 2 {
                let layer = layerAt(worldPoint)
                workspace?.addWhiteboardBeat(layerID: layer.id, position: BoardPoint(x: max(0, worldPoint.x - 110), y: max(35, worldPoint.y - (geometry.layerRects[layer.id]?.y ?? 0))))
            } else { marquee = BoardRect(x: worldPoint.x, y: worldPoint.y, width: 0, height: 0) }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil), current = world(point)
        if let panStart {
            board.viewport.origin = BoardPoint(x: panStart.x - (point.x - viewStart.x) / zoom, y: panStart.y - (point.y - viewStart.y) / zoom)
        } else if drawingMode && !stroke.isEmpty {
            if stroke.count < 10000 { stroke.append(current) }
        } else if let start = dragStart {
            dragDelta = BoardPoint(x: current.x - start.x, y: current.y - start.y)
            if marquee != nil {
                marquee = BoardRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
                selection = geometry.beats(in: marquee!); selected?(selection, [])
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; panStart = nil; movingBlocks = false; movingBeat = nil; marquee = nil; dragDelta = .init(); stroke = []; needsDisplay = true }
        if panStart != nil { persistViewport(); return }
        if stroke.count > 1 {
            let points = stroke
            workspace?.edit("Draw Annotation") { try $0.editWhiteboard { $0.strokes.append(BoardStroke(points: points)) } }; return
        }
        guard abs(dragDelta.x) + abs(dragDelta.y) > 3 else { return }
        if movingBlocks {
            var delta = dragDelta
            let ids = blockSelection, target = layerAt(world(convert(event.locationInWindow, from: nil)))
            let sourceLayer = board.blocks.first { ids.contains($0.id) }?.layerID
            if let sourceLayer, sourceLayer != target.id {
                delta.y += (geometry.layerRects[sourceLayer]?.y ?? 0) - (geometry.layerRects[target.id]?.y ?? 0)
            }
            workspace?.edit("Move Blocks") { try $0.moveBoardBlocks(ids, delta: delta, layerID: sourceLayer == target.id ? nil : target.id) }
        } else if let beat = movingBeat {
            let point = world(convert(event.locationInWindow, from: nil))
            if let block = hitBlock(point) {
                let before = geometry.hitBeat(point)
                workspace?.edit("Move Beat") { try $0.moveBoardBeat(beat, toBlock: block, before: before == beat ? nil : before) }
            }
        }
    }

    private func hitBlock(_ point: BoardPoint) -> String? {
        geometry.blockRects.filter { $0.value.contains(point) || BoardRect(x: $0.value.x, y: $0.value.y - 18, width: $0.value.width, height: 20).contains(point) }
            .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?.key
    }
    private func layerAt(_ point: BoardPoint) -> BoardLayer {
        board.layers.first { geometry.layerRects[$0.id]?.contains(point) == true } ?? board.layers[0]
    }
    private func openPopup(_ id: String) {
        guard let workspace else { return }
        workspace.selectBoardBeat(id)
        workspace.popup.open(id, workspace: workspace, near: geometry.beatRects[id].flatMap(screenRect))
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { zoomAt(convert(event.locationInWindow, from: nil), factor: exp(-event.scrollingDeltaY * 0.015)) }
        else {
            board.viewport.origin.x += event.scrollingDeltaX / zoom
            board.viewport.origin.y += event.scrollingDeltaY / zoom
            persistViewport()
        }
        needsDisplay = true
    }
    override func magnify(with event: NSEvent) { zoomAt(convert(event.locationInWindow, from: nil), factor: 1 + event.magnification) }
    private func zoomAt(_ point: NSPoint, factor: Double) {
        let anchor = world(point)
        board.viewport.zoom = max(0.15, min(3, zoom * factor))
        board.viewport.origin = BoardPoint(x: anchor.x - point.x / zoom, y: anchor.y - point.y / zoom)
        persistViewport(); needsDisplay = true
    }
    private func persistViewport() {
        var value = board.viewport
        value.origin.x = max(-1_000_000, min(1_000_000, value.origin.x)); value.origin.y = max(-1_000_000, min(1_000_000, value.origin.y))
        workspace?.edit("Whiteboard View", key: "whiteboard-viewport") { try $0.editWhiteboard { $0.viewport = value } }
    }
    func fitSelection() {
        let frames = selection.compactMap { geometry.beatRects[$0] }
        let items = frames.isEmpty ? Array(geometry.blockRects.values) : frames
        guard let x = items.map(\.x).min(), let y = items.map(\.y).min(), let right = items.map(\.maxX).max(), let bottom = items.map(\.maxY).max() else { return }
        board.viewport.zoom = max(0.15, min(1.5, min(bounds.width / (right - x + 100), bounds.height / (bottom - y + 100))))
        board.viewport.origin = BoardPoint(x: x - 50, y: y - 50); persistViewport()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = true; return }
        if event.keyCode == 36, let id = selection.sorted().first { openPopup(id); return }
        if event.keyCode == 53 { workspace?.pendingBoardCauseID = nil; selection = []; blockSelection = []; selected?([], []); needsDisplay = true; return }
        if event.keyCode == 51 || event.keyCode == 117 {
            let ids = selection
            workspace?.edit("Delete Beats") { try $0.removeBoardBeats(ids) }; selected?([], []); return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a" {
            selection = Set(board.beats.map(\.id)); selected?(selection, []); needsDisplay = true; return
        }
        super.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) { if event.keyCode == 49 { spaceHeld = false } else { super.keyUp(with: event) } }

    override func rightMouseDown(with event: NSEvent) {
        contextPoint = world(convert(event.locationInWindow, from: nil))
        contextBeat = geometry.hitBeat(contextPoint); contextBlock = hitBlock(contextPoint)
        let menu = NSMenu()
        func item(_ name: String, _ action: Selector) { let item = NSMenuItem(title: name, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        if contextBeat != nil {
            item("Edit Beat…", #selector(editContextBeat)); item("Jump To Snippet", #selector(jumpToSnippet)); item("Show In Research", #selector(showResearch))
            menu.addItem(.separator()); item("Create Cause", #selector(createCause)); item("Create Dependency From", #selector(startDependency))
            item("Must Be Caused", #selector(toggleRequired)); item("Split Beat at Cursor…", #selector(splitContext))
            item("Insert Beat After", #selector(insertContext)); menu.addItem(.separator())
            item("Omit / Include Beat", #selector(toggleOmitted)); item("Delete Beat", #selector(deleteContext))
        } else if contextBlock != nil {
            item("Add Beat", #selector(insertContext)); item("Collapse / Expand Block", #selector(collapseContext))
            item("Lock / Unlock Block", #selector(lockContext))
        } else { item("Add Beat Here", #selector(insertContext)) }
        if blockSelection.count > 1 { item("Group Selected Blocks", #selector(groupContext)) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func editContextBeat() { if let id = contextBeat { openPopup(id) } }
    @objc private func jumpToSnippet() { if let id = contextBeat { workspace?.selectBoardBeat(id); workspace?.showBoardScript = true } }
    @objc private func showResearch() { if let id = contextBeat { workspace?.openBoardResearch(id) } }
    @objc private func startDependency() { workspace?.pendingBoardCauseID = contextBeat }
    @objc private func toggleRequired() { if let id = contextBeat { workspace?.edit("Cause Requirement") { try $0.updateBoardBeat(id) { $0.mustBeCaused.toggle() } } } }
    @objc private func splitContext() { editContextBeat() }
    @objc private func createCause() {
        guard let effect = contextBeat, let owner = board.beats.first(where: { $0.id == effect }) else { return }
        var cause: String?
        workspace?.edit("Create Cause") { project in
            cause = try project.addBoardBeat(blockID: owner.blockID, title: "Cause of \(owner.title)")
            try project.connectBoardBeats(cause: cause!, effect: effect)
            try project.updateBoardBeat(cause!) { $0.order = owner.order - 0.5; $0.start = max(0, owner.start - $0.duration) }
            try project.editWhiteboard { try $0.resolveCauses() }
        }
        if let cause { openPopup(cause) }
    }
    @objc private func insertContext() {
        let layer = layerAt(contextPoint)
        workspace?.addWhiteboardBeat(blockID: contextBlock, layerID: layer.id, position: BoardPoint(x: max(0, contextPoint.x - 110), y: max(35, contextPoint.y - (geometry.layerRects[layer.id]?.y ?? 0))))
    }
    @objc private func toggleOmitted() { if let id = contextBeat { workspace?.edit("Beat Inclusion") { try $0.updateBoardBeat(id) { $0.omitted.toggle() } } } }
    @objc private func deleteContext() { if let id = contextBeat { workspace?.edit("Delete Beat") { try $0.removeBoardBeats([id]) } } }
    @objc private func collapseContext() { if let id = contextBlock { workspace?.edit("Block Display") { try $0.editWhiteboard { board in if let i = board.blocks.firstIndex(where: { $0.id == id }) { board.blocks[i].collapsed.toggle() } } } } }
    @objc private func lockContext() { if let id = contextBlock { workspace?.edit("Block Lock") { try $0.editWhiteboard { board in if let i = board.blocks.firstIndex(where: { $0.id == id }) { board.blocks[i].locked.toggle() } } } } }
    @objc private func groupContext() { let ids = blockSelection; workspace?.edit("Group Blocks") { try $0.groupBoardBlocks(ids, name: "New Group") } }
}

extension NSColor {
    convenience init(boardHex value: String) {
        let rgb = UInt32(value.hasPrefix("#") ? String(value.dropFirst()) : value, radix: 16) ?? 0xa34eae
        self.init(calibratedRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
    }
}
#endif
