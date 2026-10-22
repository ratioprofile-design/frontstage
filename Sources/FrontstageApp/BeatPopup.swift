#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

@MainActor
final class BeatPopupPresenter: NSObject, NSWindowDelegate {
    private(set) var panel: NSPanel?
    private(set) var beatID: String?
    private(set) var controller: ScreenplayEditorController?
    private(set) var panels: [String: NSPanel] = [:]
    private var controllers: [String: ScreenplayEditorController] = [:]
    func controller(for id: String) -> ScreenplayEditorController? { controllers[id] }
    func focusedController(in focusedWindow: NSWindow?) -> ScreenplayEditorController? {
        guard let focusedWindow else { return nil }
        return controllers.values.first { editor in
            guard let text = editor.textView, let window = text.window else { return false }
            return focusedWindow === window && window.firstResponder === text
        }
    }
    func refreshTitles(_ board: Whiteboard) {
        guard !panels.isEmpty else { return }
        let titles = Dictionary(uniqueKeysWithValues: board.beats.map { ($0.id, $0.title) })
        for (id, window) in panels { window.title = titles[id].map { $0.isEmpty ? "Edit Beat" : $0 } ?? "Beat removed" }
    }

    func open(_ id: String, workspace: Workspace, near anchor: NSRect? = nil) {
        guard let beat = workspace.whiteboard.beats.first(where: { $0.id == id }) else { return }
        if let panel = panels[id] { panel.makeKeyAndOrderFront(nil); return }
        let editor = ScreenplayEditorController()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: WorkspaceDesign.popupWidth, height: WorkspaceDesign.popupHeight),
            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = beat.title.isEmpty ? "Edit Beat" : beat.title
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 640, height: 440)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: BeatPopupView(workspace: workspace, beatID: id, controller: editor, dismiss: { [weak self] in self?.close(id) }).preferredColorScheme(.dark))
        let screen = NSScreen.screens.first { screen in anchor.map { screen.frame.intersects($0) } ?? false } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var point = anchor.map { NSPoint(x: $0.maxX + 12, y: $0.maxY - panel.frame.height) }
            ?? NSPoint(x: visible.midX - 330 + CGFloat(panels.count % 6) * 28, y: visible.midY - 370 - CGFloat(panels.count % 6) * 28)
        point.x = min(max(visible.minX + 8, point.x), visible.maxX - panel.frame.width - 8)
        point.y = min(max(visible.minY + 8, point.y), visible.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(point)
        self.panel = panel; beatID = id; controller = editor
        panels[id] = panel; controllers[id] = editor
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        for id in Array(panels.keys) { close(id) }
        panel = nil; beatID = nil; controller = nil
    }
    func close(_ id: String) {
        guard let window = panels[id] else { return }
        window.close()
        window.contentView = nil
        panels.removeValue(forKey: id); controllers.removeValue(forKey: id)
        if beatID == id { panel = nil; beatID = nil; controller = nil }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSPanel, let id = panels.first(where: { $0.value === window })?.key else { return }
        panel = window; beatID = id; controller = controllers[id]
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSPanel, let id = panels.first(where: { $0.value === window })?.key else { return }
        panels.removeValue(forKey: id); controllers.removeValue(forKey: id)
        window.contentView = nil
        if beatID == id { panel = nil; beatID = nil; controller = nil }
    }
}

struct BeatPopupView: View {
    @ObservedObject var workspace: Workspace
    let beatID: String
    @ObservedObject var controller: ScreenplayEditorController
    let dismiss: () -> Void
    private var beat: BoardBeat? { workspace.whiteboard.beats.first { $0.id == beatID } }

    private func text(_ path: WritableKeyPath<BoardBeat, String>, label: String) -> Binding<String> {
        Binding(get: { beat?[keyPath: path] ?? "" }, set: { value in
            workspace.edit(label, key: "popup-\(beatID)-\(label)") { try $0.updateBoardBeat(beatID) { $0[keyPath: path] = value } }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let beat {
                HStack {
                    Circle().fill(Color(boardHex: beat.color)).frame(width: 9, height: 9)
                    TextField("Beat name", text: text(\.title, label: "Beat Title"))
                        .font(.title3.weight(.semibold)).textFieldStyle(.plain)
                    Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
                }
                TextField("Synopsis", text: text(\.synopsis, label: "Beat Synopsis"))
                HStack {
                    Picker("Type", selection: Binding(get: { beat.kind }, set: { kind in
                        workspace.edit("Beat Type") { try $0.updateBoardBeat(beatID) { $0.kind = kind } }
                    })) { Text("Story Beat").tag(BoardBeatKind.story); Text("Subtext Beat").tag(BoardBeatKind.subtext) }
                    .pickerStyle(.segmented)
                    Toggle("Must Be Caused", isOn: Binding(get: { beat.mustBeCaused }, set: { value in
                        workspace.edit("Cause Requirement") { try $0.updateBoardBeat(beatID) { $0.mustBeCaused = value } }
                    }))
                }
                HStack {
                    TextField("Characters, separated by commas", text: Binding(get: { beat.characters.joined(separator: ", ") }, set: { value in
                        workspace.edit("Beat Characters", key: "characters-\(beatID)") { try $0.updateBoardBeat(beatID) { $0.characters = value.boardList } }
                    }))
                    TextField("Tags", text: Binding(get: { beat.tags.joined(separator: ", ") }, set: { value in
                        workspace.edit("Beat Tags", key: "tags-\(beatID)") { try $0.updateBoardBeat(beatID) { $0.tags = value.boardList } }
                    }))
                }
                if let scene = workspace.project.scenes.first(where: { $0.id == beat.sceneID }) {
                    SceneHeadingFields(scene: scene, workspace: workspace)
                    Text(scene.heading.text).font(.custom("Courier", size: 12).bold())
                }
                Divider()
                HStack {
                Picker("Format", selection: Binding(get: { controller.activeElement }, set: { controller.format($0) })) {
                    ForEach(ScreenplayElement.editable, id: \.self) { Text($0.label).tag($0) }
                }.frame(width: 200)
                InlineFormatButtons(controller: controller)
                Spacer()
                }
                ScreenplaySuggestions(workspace: workspace, controller: controller)
                    .disabled(workspace.project.scenes.first { $0.id == beat.sceneID }?.isTextLocked == true)
                ScreenplayEditor(html: text(\.html, label: "Snippet Text"), controller: controller, width: 432, typography: workspace.project.scriptLayout,
                    onError: { workspace.errorMessage = $0 }, editable: workspace.project.scenes.first { $0.id == beat.sceneID }?.isTextLocked != true, paper: true).id(beatID)
                    .frame(width: WorkspaceDesign.paperWidth).frame(maxWidth: .infinity)
                    .environment(\.colorScheme, .light)
                    .border(Color.black.opacity(0.2)).shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                HStack {
                    Text("Changes save to your project as you type. Esc closes this editor.")
                    Spacer()
                    Button("Split at Cursor") { workspace.splitBoardBeat(beatID, controller: controller) }
                }.font(.caption).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("This beat was removed", systemImage: "rectangle.slash")
                Button("Close", action: dismiss)
            }
        }.padding(14).textFieldStyle(.roundedBorder)
    }
}

extension String {
    var boardList: [String] {
        var seen = Set<String>()
        return split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

extension Color {
    init(boardHex value: String) {
        let rgb = UInt32(value.hasPrefix("#") ? String(value.dropFirst()) : value, radix: 16) ?? 0xa34eae
        self.init(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

extension Workspace {
    func openBoardResearch(_ id: String) {
        var record = (try? project.studio().records.first { $0.beatID == id && $0.kind == .research })?.id
        let beat = whiteboard.beats.first { $0.id == id }
        if record == nil {
            edit("Add Beat Research") { record = try $0.addStudioRecord(kind: .research, title: beat?.title ?? "Beat Research", sceneID: beat?.sceneID, beatID: id) }
        }
        selectedResearchID = record; mode = .studio
    }

    var whiteboard: Whiteboard { whiteboardCache ?? (try? project.whiteboard()) ?? Whiteboard() }
    var selectedBoardBeat: BoardBeat? { whiteboard.beats.first { $0.id == selectedBoardBeatID } }

    func selectBoardBeat(_ id: String) {
        selectedBoardBeatID = id
        if let beat = whiteboard.beats.first(where: { $0.id == id }) { selectedSceneID = beat.sceneID }
    }

    func createBeatGroup(_ selection: Set<String>) {
        if selection.isEmpty {
            var created: String?
            edit("Create Beat Group") { project in
                created = try project.addBoardBeat(position: .init(x: max(70, (whiteboard.blocks.map { $0.position.x + $0.width }.max() ?? -214) + 60), y: 70))
                if let created { try project.editWhiteboard { board in
                    let owner = board.beats.first { $0.id == created }?.blockID
                    if let i = board.blocks.firstIndex(where: { $0.id == owner }) { board.blocks[i].containerKind = "beatGroup"; board.blocks[i].name = "Beat Group" }
                } }
            }
            if let created { selectBoardBeat(created); popup.open(created, workspace: self) }
        } else { edit("Group Beats") { try $0.groupBoardBeats(selection) } }
    }

    func addWhiteboardBeat(blockID: String? = nil, layerID: String = "main", position: BoardPoint? = nil, before: String? = nil, standalone: Bool = true, sceneID: Decimal? = nil, after: String? = nil) {
        var created: String?
        let location = position ?? BoardPoint(x: min(900000, max(70, (whiteboard.blocks.map { $0.position.x + $0.width }.max() ?? -214) + 60)), y: 70)
        edit("Add Whiteboard Beat") { project in
            created = try project.addBoardBeat(blockID: blockID, layerID: layerID, position: location, sceneID: sceneID)
            if blockID == nil, standalone, let created {
                try project.editWhiteboard { board in
                    if let owner = board.beats.first(where: { $0.id == created })?.blockID,
                       let index = board.blocks.firstIndex(where: { $0.id == owner }) { board.blocks[index].standalone = true }
                }
            }
            if let created, let after {
                try project.editWhiteboard { board in
                    let ordered = board.orderedBeats.filter { $0.id != created }
                    if let index = ordered.firstIndex(where: { $0.id == after }), let target = board.beats.firstIndex(where: { $0.id == created }) {
                        board.beats[target].order = (ordered[index].order + (index + 1 < ordered.count ? ordered[index + 1].order : ordered[index].order + 2)) / 2
                    }
                }
            }
            if let created, let blockID, let before { try project.moveBoardBeat(created, toBlock: blockID, before: before) }
        }
        if let created { selectBoardBeat(created); popup.open(created, workspace: self) }
    }

    func splitBoardBeat(_ id: String, controller: ScreenplayEditorController? = nil) {
        guard let beat = whiteboard.beats.first(where: { $0.id == id }) else { return }
        do {
            let source = try ScreenplayTextCodec.decode(beat.html)
            let caret = (controller ?? popup.controller(for: id))?.textView?.selectedRange().location ?? source.length / 2
            guard caret > 0, caret < source.length else { throw ProjectError.invalidProject("place the cursor inside the snippet before splitting") }
            let first = ScreenplayTextCodec.encode(source.attributedSubstring(from: NSRange(location: 0, length: caret)))
            let second = ScreenplayTextCodec.encode(source.attributedSubstring(from: NSRange(location: caret, length: source.length - caret)))
            var created: String?
            edit("Split Beat") { created = try $0.splitBoardBeat(id, firstHTML: first, secondHTML: second) }
            if let created { selectBoardBeat(created); popup.open(created, workspace: self) }
        } catch { errorMessage = error.localizedDescription }
    }
}
#endif
