#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

@MainActor
final class BeatPopupPresenter: NSObject, NSWindowDelegate {
    private(set) var panel: NSPanel?
    private(set) var beatID: String?
    private(set) var controller: ScreenplayEditorController?

    func open(_ id: String, workspace: Workspace, near anchor: NSRect? = nil) {
        guard (try? workspace.project.whiteboard().beats.contains { $0.id == id }) == true else { return }
        if beatID == id, let panel { panel.makeKeyAndOrderFront(nil); return }
        close()
        let editor = ScreenplayEditorController()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 530),
            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Edit Beat"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 450, height: 340)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: BeatPopupView(workspace: workspace, beatID: id, controller: editor, dismiss: { [weak self] in self?.close() }))
        let screen = NSScreen.screens.first { screen in anchor.map { screen.frame.intersects($0) } ?? false } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var point = anchor.map { NSPoint(x: $0.maxX + 12, y: $0.maxY - panel.frame.height) }
            ?? NSPoint(x: visible.midX - 290, y: visible.midY - 265)
        point.x = min(max(visible.minX + 8, point.x), visible.maxX - panel.frame.width - 8)
        point.y = min(max(visible.minY + 8, point.y), visible.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(point)
        self.panel = panel; beatID = id; controller = editor
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.contentView = nil
        panel?.close()
        panel = nil; beatID = nil; controller = nil
    }
    func windowWillClose(_ notification: Notification) {
        panel?.contentView = nil
        panel = nil; beatID = nil; controller = nil
    }
}

struct BeatPopupView: View {
    @ObservedObject var workspace: Workspace
    let beatID: String
    @ObservedObject var controller: ScreenplayEditorController
    let dismiss: () -> Void
    private var beat: BoardBeat? { try? workspace.project.whiteboard().beats.first { $0.id == beatID } }

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
                Divider()
                Picker("Format", selection: Binding(get: { controller.activeElement }, set: { controller.format($0) })) {
                    ForEach(ScreenplayElement.editable, id: \.self) { Text($0.label).tag($0) }
                }.frame(width: 200)
                ScreenplayEditor(html: text(\.html, label: "Snippet Text"), controller: controller, width: 432, typography: workspace.project.scriptLayout,
                    onError: { workspace.errorMessage = $0 }).id(beatID)
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
    var whiteboard: Whiteboard { (try? project.whiteboard()) ?? Whiteboard() }
    var selectedBoardBeat: BoardBeat? { whiteboard.beats.first { $0.id == selectedBoardBeatID } }

    func selectBoardBeat(_ id: String) {
        selectedBoardBeatID = id
        if let beat = whiteboard.beats.first(where: { $0.id == id }) { selectedSceneID = beat.sceneID }
    }

    func addWhiteboardBeat(blockID: String? = nil, layerID: String = "main", position: BoardPoint = .init(x: 70, y: 60)) {
        var created: String?
        edit("Add Whiteboard Beat") { created = try $0.addBoardBeat(blockID: blockID, layerID: layerID, position: position) }
        if let created { selectBoardBeat(created); popup.open(created, workspace: self) }
    }

    func splitBoardBeat(_ id: String, controller: ScreenplayEditorController? = nil) {
        guard let beat = whiteboard.beats.first(where: { $0.id == id }) else { return }
        do {
            let source = try ScreenplayTextCodec.decode(beat.html)
            let caret = (controller ?? popup.controller)?.textView?.selectedRange().location ?? source.length / 2
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
