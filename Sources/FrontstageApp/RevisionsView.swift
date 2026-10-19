#if os(macOS)
import SwiftUI
import FrontstageCore

struct RevisionsView: View {
    @ObservedObject var workspace: Workspace
    @State private var label = ""
    @State private var selectedID: String?

    private var revisions: [SceneRevision] {
        workspace.selectedSceneID.map { workspace.project.revisions(for: $0) } ?? []
    }
    private var selected: SceneRevision? { revisions.first { $0.id == selectedID } }
    private var diff: [RevisionDiffLine] {
        guard let selected, let scene = workspace.selectedScene else { return [] }
        let before = (try? ScreenplayTextCodec.decode(selected.html).string) ?? selected.html
        let after = (try? ScreenplayTextCodec.decode(scene.html).string) ?? scene.html
        return RevisionDiffLine.compare(before: before, after: after)
    }

    var body: some View {
        if let scene = workspace.selectedScene {
            VStack(alignment: .leading, spacing: 14) {
                Text("Revisions · \(scene.title)").font(.title2)
                HStack {
                    TextField("Revision name", text: $label).textFieldStyle(.roundedBorder)
                    Button("Capture Revision") {
                        workspace.edit("Capture Revision") { try $0.saveRevision(sceneID: scene.id, label: label) }
                        selectedID = workspace.project.revisions(for: scene.id).first?.id
                        label = ""
                    }.disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HSplitView {
                    List(revisions, selection: $selectedID) { revision in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(revision.label).fontWeight(.medium)
                            Text(revision.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }.tag(revision.id)
                    }.frame(minWidth: 190, idealWidth: 230)
                    VStack(alignment: .leading) {
                        if let selected {
                            Text("\(selected.label) → Current text").font(.headline)
                            Text("− removed from revision   + added in current text").font(.caption).foregroundStyle(.secondary)
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 3) {
                                    ForEach(diff) { line in
                                        Text("\(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ") \(line.text)")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundStyle(line.kind == .added ? Color.green : line.kind == .removed ? Color.red : Color.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }.textSelection(.enabled).padding()
                            }
                            Button("Restore Selected Revision") {
                                workspace.edit("Restore Revision") { try $0.restoreRevision(sceneID: scene.id, revisionID: selected.id) }
                            }
                            Text("Restoring first captures a backup of the current scene. Other production data stays current.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ContentUnavailableView("Select a revision", systemImage: "clock.arrow.circlepath",
                                description: Text("Capture a named snapshot to compare or restore it later."))
                        }
                    }.frame(minWidth: 300)
                }
            }.padding(24).onChange(of: workspace.selectedSceneID) { _, _ in selectedID = nil }
        } else {
            ContentUnavailableView("Select a scene", systemImage: "clock.arrow.circlepath")
        }
    }
}
#endif
