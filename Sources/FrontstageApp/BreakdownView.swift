#if os(macOS)
import SwiftUI
import FrontstageCore

struct BreakdownView: View {
    @ObservedObject var workspace: Workspace
    @State private var category = BreakdownCategory.props
    @State private var name = ""
    @State private var quantity = 1
    @State private var notes = ""

    var body: some View {
        if let scene = workspace.selectedScene {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Breakdown · \(scene.title)").font(.title2)
                    Text(scene.heading.text).font(.system(.body, design: .monospaced))
                    Text("Characters in this scene").font(.headline)
                    if workspace.project.characters.isEmpty {
                        Text("Add or discover characters in People, then assign them here.").foregroundStyle(.secondary)
                    }
                    ForEach(workspace.project.characters) { character in
                        Toggle(character.name, isOn: Binding(
                            get: { workspace.project.sceneCharacters(scene.id).contains(character.id) },
                            set: { value in workspace.edit("Assign Scene Character") { try $0.assignCharacter(character.id, to: scene.id, assigned: value) } }))
                    }
                    let unprofiled = workspace.project.sceneCharacters(scene.id).filter { key in !workspace.project.characters.contains { $0.id == key } }
                    if !unprofiled.isEmpty { Text("Imported names without profiles: \(unprofiled.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    Text("Production Requirements").font(.headline)
                    HStack {
                        Picker("Category", selection: $category) {
                            ForEach(BreakdownCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.frame(width: 190)
                        TextField("Item name", text: $name).textFieldStyle(.roundedBorder)
                        Stepper("Qty \(quantity)", value: $quantity, in: 1...100_000).frame(width: 110)
                    }
                    HStack {
                        TextField("Requirement notes", text: $notes).textFieldStyle(.roundedBorder)
                        Button("Add Requirement") {
                            workspace.edit("Add Breakdown Item") { try $0.addBreakdownItem(sceneID: scene.id, category: category, name: name, count: quantity, notes: notes) }
                            if workspace.errorMessage == nil { name = ""; notes = ""; quantity = 1 }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ForEach(workspace.project.breakdownItems(for: scene.id)) { item in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(item.category.replacingOccurrences(of: "_", with: " ")).font(.caption).frame(width: 110, alignment: .leading)
                                TextField("Name", text: itemBinding(scene.id, item: item, notes: false)).textFieldStyle(.roundedBorder)
                                Stepper("\(item.count)", value: Binding(get: {
                                    workspace.project.breakdownItems(for: scene.id).first { $0.id == item.id }?.count ?? item.count
                                }, set: { value in workspace.edit("Change Requirement Quantity") { try $0.updateBreakdownItem(sceneID: scene.id, itemID: item.id, count: value) } }), in: 1...100_000).frame(width: 100)
                                Button { workspace.edit("Remove Requirement") { try $0.removeBreakdownItem(sceneID: scene.id, itemID: item.id) } }
                                    label: { Image(systemName: "minus.circle") }.help("Remove requirement (project undo available)")
                            }
                            TextField("Notes", text: itemBinding(scene.id, item: item, notes: true)).textFieldStyle(.roundedBorder)
                        }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(24)
            }
        } else { ContentUnavailableView("Select a scene", systemImage: "list.clipboard") }
    }

    private func itemBinding(_ sceneID: Decimal, item: BreakdownEntry, notes: Bool) -> Binding<String> {
        Binding(get: {
            let current = workspace.project.breakdownItems(for: sceneID).first { $0.id == item.id } ?? item
            return notes ? current.notes : current.name
        }, set: { value in
            workspace.edit("Edit Requirement", key: "breakdown-\(sceneID)-\(item.id)-\(notes)") {
                try $0.updateBreakdownItem(sceneID: sceneID, itemID: item.id, name: notes ? nil : value, notes: notes ? value : nil)
            }
        })
    }
}
#endif
