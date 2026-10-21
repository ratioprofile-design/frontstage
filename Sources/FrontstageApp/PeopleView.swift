#if os(macOS)
import SwiftUI
import FrontstageCore

extension Workspace {
    func discoverCharacters() {
        edit("Discover Script Characters") { project in
            for scene in project.scenes {
                let text = try ScreenplayTextCodec.decode(scene.html)
                var offset = 0
                while offset < text.length {
                    let range = (text.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
                    if ScreenplayTextCodec.element(in: text, at: offset) == .character {
                        let raw = (text.string as NSString).substring(with: range)
                        let name = raw.replacingOccurrences(of: #"\s*\((?:CONT'D|V\.O\.|O\.S\.)\)"#, with: "", options: [.regularExpression, .caseInsensitive])
                            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        if !name.isEmpty {
                            let key = try project.characters.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.id
                                ?? project.createCharacter(name: name)
                            try project.assignCharacter(key, to: scene.id, assigned: true)
                        }
                    }
                    offset = NSMaxRange(range)
                }
            }
        }
    }
}

struct PeopleView: View {
    @ObservedObject var workspace: Workspace
    @State private var selectedRole: String?
    @State private var selectedArtist: String?
    @State private var newName = ""
    @State private var actorName = ""

    private var role: CharacterRecord? { workspace.project.characters.first { $0.id == selectedRole } }
    private var artist: CastingOption? { role?.artists.first { $0.id == selectedArtist } }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("Characters & Casting").font(.headline)
                HStack {
                    TextField("New character", text: $newName).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        var key: String?
                        workspace.edit("Add Character") { key = try $0.createCharacter(name: newName) }
                        if let key { selectedRole = key; newName = "" }
                    }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button("Discover From Script") {
                    workspace.discoverCharacters()
                    if selectedRole == nil { selectedRole = workspace.project.characters.first?.id }
                }
                List(workspace.project.characters, selection: $selectedRole) { character in
                    VStack(alignment: .leading) {
                        Text(character.name)
                        if let id = character.confirmedArtistID,
                           let actor = character.artists.first(where: { $0.id == id }) {
                            Text(actor.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }.tag(character.id)
                }
            }.padding(16).frame(minWidth: 210, idealWidth: WorkspaceDesign.sidebar)
            if let role {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(role.name).font(.title2)
                        Text("Role keys remain stable so scene assignments and imported references stay connected.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(CharacterField.allCases, id: \.self) { field in
                            TextField(field.label, text: characterBinding(field), axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(1...6)
                        }
                        Divider()
                        Text("Casting Options").font(.headline)
                        HStack {
                            TextField("Actor name", text: $actorName).textFieldStyle(.roundedBorder)
                            Button("Add Option") {
                                var id: String?
                                workspace.edit("Add Casting Option") { id = try $0.addCastingOption(character: role.id, name: actorName) }
                                if let id { selectedArtist = id; actorName = "" }
                            }.disabled(actorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        ForEach(role.artists) { option in
                            Button { selectedArtist = option.id } label: {
                                HStack {
                                    Image(systemName: role.confirmedArtistID == option.id ? "checkmark.seal.fill" : "person")
                                    Text(option.name)
                                    Spacer()
                                    Text(option.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption)
                                }.padding(8)
                            }.buttonStyle(.bordered).tint(selectedArtist == option.id ? .accentColor : .secondary)
                        }
                        if let artist {
                            Text(artist.name).font(.headline)
                            Picker("Status", selection: Binding(get: { self.artist?.status ?? artist.status }, set: { value in
                                if let status = CastingStatus(rawValue: value) {
                                    workspace.edit("Change Casting Status") { try $0.updateCastingOption(character: role.id, artistID: artist.id, status: status) }
                                }
                            })) {
                                if CastingStatus(rawValue: artist.status) == nil { Text(artist.status).tag(artist.status) }
                                ForEach(CastingStatus.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                            }
                            TextField("Email", text: artistBinding("email")).textFieldStyle(.roundedBorder)
                            TextField("Phone", text: artistBinding("phone")).textFieldStyle(.roundedBorder)
                            TextField("Notes", text: artistBinding("notes"), axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...8)
                            HStack {
                                Button("Confirm for Role") {
                                    workspace.edit("Confirm Casting") { try $0.confirmCastingOption(character: role.id, artistID: artist.id) }
                                }.disabled(artist.status == CastingStatus.passed.rawValue)
                                if role.confirmedArtistID != nil {
                                    Button("Clear Confirmation") { workspace.edit("Clear Casting Confirmation") { try $0.confirmCastingOption(character: role.id, artistID: nil) } }
                                }
                            }
                        }
                    }.padding(WorkspaceDesign.padding)
                }.frame(minWidth: 300)
            } else {
                ContentUnavailableView("Add or select a character", systemImage: "person.2",
                    description: Text("Discover character cues from the screenplay or add a role manually."))
            }
        }.onAppear { if selectedRole == nil { selectedRole = workspace.project.characters.first?.id } }
            .onChange(of: selectedRole) { _, _ in selectedArtist = nil }
    }

    private func characterBinding(_ field: CharacterField) -> Binding<String> {
        Binding(get: { role?.fields[field.rawValue] ?? "" }, set: { value in
            guard let role else { return }
            workspace.edit("Edit Character", key: "character-\(role.id)-\(field.rawValue)") {
                try $0.updateCharacter(role.id, field: field, value: value)
            }
        })
    }

    private func artistBinding(_ field: String) -> Binding<String> {
        Binding(get: {
            guard let artist else { return "" }
            return field == "email" ? artist.email : field == "phone" ? artist.phone : artist.notes
        }, set: { value in
            guard let role, let artist else { return }
            workspace.edit("Edit Casting Option", key: "actor-\(artist.id)-\(field)") {
                try $0.updateCastingOption(character: role.id, artistID: artist.id,
                    notes: field == "notes" ? value : nil, email: field == "email" ? value : nil, phone: field == "phone" ? value : nil)
            }
        })
    }
}
#endif
