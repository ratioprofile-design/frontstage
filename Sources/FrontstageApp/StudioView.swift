#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FrontstageCore

struct StudioView: View {
    @ObservedObject var workspace: Workspace
    @State private var kind = StudioKind.research
    @State private var selected: String?
    @State private var search = ""
    private var studio: Studio { (try? workspace.project.studio()) ?? Studio() }
    private var record: StudioRecord? { studio.records.first { $0.id == selected } }
    private var records: [StudioRecord] { studio.records.filter { $0.kind == kind && (search.isEmpty || ($0.title + " " + $0.body).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Workspace", selection: $kind) { ForEach(StudioKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                TextField("Search records", text: $search)
                List(records, selection: $selected) { Text($0.title).tag($0.id) }
                HStack {
                    Button("Add") {
                        var id: String?
                        workspace.edit("Add \(kind.label)") { id = try $0.addStudioRecord(kind: kind, title: "Untitled \(kind.rawValue)", sceneID: workspace.selectedSceneID, beatID: workspace.selectedBoardBeatID) }
                        selected = id
                    }
                    Spacer()
                    Button("Export CSV") { do { workspace.exportCSV(try workspace.project.studioCSV(kind: kind), name: kind.label) } catch { workspace.errorMessage = error.localizedDescription } }
                }
            }.padding(14).frame(minWidth: 220, idealWidth: 260)
            if let record {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Title", text: field(\.title)).font(.title2).textFieldStyle(.plain)
                        Picker("Linked scene", selection: Binding(get: { record.sceneID }, set: { id in update { $0.sceneID = id } })) {
                            Text("No scene").tag(Optional<Decimal>.none)
                            ForEach(workspace.project.scenes) { Text($0.title).tag(Optional($0.id)) }
                        }
                        if let beat = record.beatID {
                            Button("Show linked beat") { workspace.selectBoardBeat(beat); workspace.mode = .board }
                        }
                        Text("Notes").font(.headline)
                        TextEditor(text: field(\.body)).frame(minHeight: 180)
                        ForEach(detailFields, id: \.self) { key in
                            TextField(key, text: Binding(get: { self.record?.fields[key] ?? "" }, set: { text in update { $0.fields[key] = text } }))
                        }
                        Divider(); Text("Attachments / Storyboard Frames").font(.headline)
                        ForEach(studio.assets.filter { record.assetIDs.contains($0.id) }) { asset in
                            VStack(alignment: .leading, spacing: 8) {
                                if let image = NSImage(data: asset.data) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 260) }
                                HStack {
                                    Text(asset.filename).font(.caption)
                                    Spacer()
                                    Button("Export…") { export(asset) }
                                    Button("Remove") { remove(asset, recordID: record.id) }
                                }
                            }
                        }
                        Button("Attach File…", action: attach)
                        Text("Attachments travel inside the project. Limit: 10 MB per file, 64 MB total.").font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Button("Delete Record", role: .destructive) {
                            let id = record.id
                            workspace.edit("Delete Record") { try $0.editStudio { studio in studio.records.removeAll { $0.id == id }; let used = Set(studio.records.flatMap(\.assetIDs)); studio.assets.removeAll { !used.contains($0.id) } } }
                            selected = nil
                        }
                    }.padding(24).textFieldStyle(.roundedBorder)
                }.frame(minWidth: 350)
            } else { ContentUnavailableView("Select or add a record", systemImage: "books.vertical") }
        }.onChange(of: kind) { _, _ in selected = records.first?.id }
            .onAppear { if let id = workspace.selectedResearchID { selected = id; kind = studio.records.first { $0.id == id }?.kind ?? .research; workspace.selectedResearchID = nil } }
    }
    private var detailFields: [String] {
        switch kind {
        case .research: return ["Source URL", "Category"]
        case .crew: return ["Role", "Email", "Phone", "Availability", "Department"]
        case .continuity: return ["Status", "Costume", "Props", "Makeup", "Take"]
        case .shot: return ["Shot Number", "Size", "Angle", "Lens", "Movement", "Equipment", "Status"]
        case .audition: return ["Character", "Actor", "Audition Date", "Rating", "Status", "Link"]
        }
    }
    private func field(_ path: WritableKeyPath<StudioRecord, String>) -> Binding<String> { Binding(get: { record?[keyPath: path] ?? "" }, set: { text in update { $0[keyPath: path] = text } }) }
    private func update(_ action: (inout StudioRecord) -> Void) {
        guard let id = selected else { return }; workspace.edit("Edit Studio Record", key: "studio-\(id)") { try $0.updateStudioRecord(id, action) }
    }
    private func attach() {
        guard let selected else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowedContentTypes = [.image, .pdf, .movie, .audio, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 10 * 1024 * 1024 else { throw ProjectError.invalidProject("file exceeds the 10 MB attachment limit") }
            let data = try Data(contentsOf: url)
            workspace.edit("Attach File") { _ = try $0.attachStudioAsset(to: selected, filename: url.lastPathComponent, data: data) }
        } catch { workspace.errorMessage = error.localizedDescription }
    }
    private func export(_ asset: StudioAsset) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = asset.filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try asset.save(to: url) } catch { workspace.errorMessage = error.localizedDescription }
    }
    private func remove(_ asset: StudioAsset, recordID: String) {
        workspace.edit("Remove Attachment") { try $0.editStudio { studio in
            if let i = studio.records.firstIndex(where: { $0.id == recordID }) { studio.records[i].assetIDs.removeAll { $0 == asset.id } }
            if !studio.records.contains(where: { $0.assetIDs.contains(asset.id) }) { studio.assets.removeAll { $0.id == asset.id } }
        } }
    }
}
#endif
