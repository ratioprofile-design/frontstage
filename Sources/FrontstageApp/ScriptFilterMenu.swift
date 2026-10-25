#if os(macOS)
import SwiftUI
import FrontstageCore

struct ScriptFilterMenu: View {
    @ObservedObject var workspace: Workspace
    @Binding var state: ScriptFilters
    @State private var past = [ScriptFilters]()
    @State private var future = [ScriptFilters]()
    private func update(_ change: (inout ScriptFilters) -> Void) { past.append(state); future = []; change(&state) }
    private func toggle(_ label: String, _ key: WritableKeyPath<ScriptFilters, Bool>) -> some View {
        Toggle(label, isOn: Binding(get: { state[keyPath: key] }, set: { value in update { $0[keyPath: key] = value } }))
    }
    private func choices(_ kind: String) -> [(String, String)] {
        let board = workspace.whiteboard
        switch kind {
        case "Beats": return board.orderedBeats.map { ($0.id, $0.title) }
        case "Blocks": return board.blocks.filter { $0.standalone != true }.map { ($0.id, $0.name) }
        case "Lanes": return board.layers.map { ($0.id, $0.name) }
        default:
            let values = kind == "Tags" ? board.beats.flatMap(\.tags) : kind == "Characters" ? board.beats.flatMap { ScriptFilters.characters($0) } : workspace.project.scenes.map { $0.heading.location }
            return Array(Set(values)).sorted().map { ($0, $0.isEmpty ? "Untitled scene" : $0) }
        }
    }
    var body: some View {
        Menu {
            Button("Filter On Selection") { if let id = workspace.selectedBoardBeatID { update { $0.facets["Beats", default: .init()].values = [id] } } }.keyboardShortcut("l", modifiers: .command).disabled(workspace.selectedBoardBeatID == nil)
            Button("Go Back") { if let previous = past.popLast() { future.append(state); state = previous } }.disabled(past.isEmpty)
            Button("Go Forward") { if let next = future.popLast() { past.append(state); state = next } }.disabled(future.isEmpty)
            Button("Reset Filter") { update { $0 = .init() }; workspace.reader.filter = "" }
            Section("Filter By") {
                ForEach(ScriptFilters.kinds, id: \.self) { kind in
                    Menu(kind + "…") {
                        Toggle("Hide selected", isOn: Binding(get: { state.facets[kind]?.hide ?? false }, set: { value in update { $0.facets[kind, default: .init()].hide = value } }))
                        if ["Tags", "Characters"].contains(kind) { Toggle("Match all (AND)", isOn: Binding(get: { state.facets[kind]?.all ?? false }, set: { value in update { $0.facets[kind, default: .init()].all = value } })) }
                        ForEach(choices(kind), id: \.0) { id, name in
                            Toggle(name, isOn: Binding(get: { state.facets[kind]?.values.contains(id) ?? false }, set: { selected in update { if selected { $0.facets[kind, default: .init()].values.insert(id) } else { $0.facets[kind, default: .init()].values.remove(id) } } }))
                        }
                    }
                }
            }
            Picker("Gaps", selection: Binding(get: { state.gaps }, set: { value in update { $0.gaps = value } })) { ForEach(["Time", "Pages", "Events"], id: \.self) { Text($0).tag($0) } }
            Section("Always-On Filters") {
                toggle("Hide Disabled Beats", \.hideDisabled); toggle("Hide Empty Beats", \.hideEmpty)
                toggle("Hide Scene Headings", \.hideHeadings); toggle("Hide Breaks", \.hideBreaks); toggle("Hide Filter Gaps", \.hideGaps)
            }
        } label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }
    }
}
#endif
