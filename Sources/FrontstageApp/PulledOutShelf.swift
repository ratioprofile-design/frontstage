#if os(macOS)
import SwiftUI
import FrontstageCore
struct PulledOutShelf: View {
    @ObservedObject var workspace: Workspace
    @State private var search = ""
    @State private var destinations: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading) {
            Text("Pulled Out").font(.title)
            Text("Original beats and production data remain available to restore.").foregroundStyle(.secondary)
            TextField("Search pulled-out beats", text: $search)
            ScrollView {
                ForEach(workspace.project.scenes.filter { scene in workspace.project.pulledOutBeats.contains { $0.sceneID == scene.id } }) { scene in
                    GroupBox(scene.title) {
                        VStack(alignment: .leading, spacing: 12) {
                            Button("Restore Scene") { workspace.edit("Restore Scene") { try $0.restorePulledOutBeats(Set($0.pulledOutBeats.filter { $0.sceneID == scene.id }.map(\.id))) } }
                            ForEach(workspace.project.pulledOutBeats.filter { $0.sceneID == scene.id && (search.isEmpty || ($0.title + $0.html).localizedCaseInsensitiveContains(search)) }) { beat in
                                VStack(alignment: .leading) {
                                    Text(beat.title).bold(); Text(beat.wasOmitted ? "Previously omitted" : "Previously active").font(.caption)
                                    Text((try? ScreenplayTextCodec.decode(beat.html).string) ?? beat.html).textSelection(.enabled)
                                    Picker("Restore destination", selection: Binding(get: { destinations[beat.id] ?? "" }, set: { destinations[beat.id] = $0 })) {
                                        Text("Original container").tag("")
                                        ForEach(workspace.whiteboard.blocks.filter { !workspace.whiteboard.isBlockLocked($0.id) }) { Text($0.name).tag($0.id) }
                                    }
                                    Button("Restore Beat") { workspace.edit("Restore Beat") { try $0.restorePulledOutBeats([beat.id], into: destinations[beat.id].flatMap { $0.isEmpty ? nil : $0 }) } }
                                }.padding(8)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.padding(16).frame(minWidth: 450, minHeight: 400)
    }
}
#endif
