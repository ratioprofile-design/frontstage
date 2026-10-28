#if os(macOS)
import SwiftUI
import FrontstageCore

struct ProductionBaselineControls: View {
    @ObservedObject var workspace: Workspace
    private var revision: ProductionRevision? { workspace.project.currentRevision }
    var body: some View {
        GroupBox("Production baseline") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Capture scene text for comparison. Baseline locking does not freeze pagination or production numbering.").font(.caption).foregroundStyle(.secondary)
                if let revision {
                    HStack { Circle().fill(revision.color.swiftUIColor).frame(width: 14, height: 14); Text(revision.color.rawValue).font(.caption) }
                    Picker("Revision color", selection: Binding(get: { revision.color }, set: { color in workspace.edit("Revision Color") { $0.setRevisionColor(color) } })) {
                        ForEach(RevisionColor.allCases, id: \.self) { color in Text(color.rawValue).tag(color) }
                    }
                    TextField("Label", text: Binding(get: { revision.label }, set: { label in workspace.edit("Revision Label", key: "revision-label") { $0.updateRevisionLabel(label) } }))
                    Text(revision.date, style: .date).font(.caption)
                    Button(revision.isLocked ? "Unlock Baseline" : "Lock Baseline") { workspace.edit("Baseline Lock") { $0.toggleProductionLock() } }
                    ForEach(workspace.project.scenes) { scene in
                        Text("\(scene.title): \(workspace.project.productionSceneChanged(scene.id) ? "Changed since baseline" : "Unchanged")").font(.caption)
                    }
                }
                Button(revision == nil ? "Capture Production Baseline" : "Start Next Revision") {
                    workspace.endScriptTypingGroup()
                    workspace.edit("Capture Production Baseline") { project in
                        if project.currentRevision == nil { project.toggleProductionLock() } else { project.startNextRevision() }
                    }
                }
                Text("\(workspace.project.preservedState["productionRevisionHistory"]?.array?.count ?? 0) previous baselines retained").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
}
#endif
