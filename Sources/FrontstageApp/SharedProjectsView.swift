#if os(macOS)
import SwiftUI
import Foundation
import Security
import FrontstageCore

struct RemoteProject: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var revision: Int
    var access: String
    var document: JSONValue?
    var modifiedBy: String?
}
private struct LoginResponse: Decodable { var token: String; var username: String }
private struct RemoteUpdate: Decodable { var conflict: Bool; var snapshot: RemoteProject }

@MainActor
final class SharedProjectClient: ObservableObject {
    @Published var server = UserDefaults.standard.string(forKey: "Frontstage.Sync.Server") ?? "http://127.0.0.1:8080"
    @Published var username = UserDefaults.standard.string(forKey: "Frontstage.Sync.Username") ?? ""
    @Published var password = ""
    @Published private(set) var signedIn = false
    @Published private(set) var busy = false
    @Published private(set) var projects: [RemoteProject] = []
    @Published private(set) var linked: RemoteProject?
    @Published private(set) var conflict: RemoteProject?
    @Published private(set) var conflicts: [String] = []
    @Published var status = "Connect to your DOT server. Local editing works without a connection."
    private var token = ""
    private var base: JSONValue?

    func detach() { linked = nil; base = nil; conflict = nil; conflicts = [] }

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: server), let host = url.host, url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host)) else { throw ProjectError.invalidProject("use HTTPS for a shared server, or HTTP on localhost for development") }
        return url.appendingPathComponent(path)
    }
    private func send(_ path: String, method: String = "GET", body: JSONValue? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: try endpoint(path)); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) || code == 409 else {
            if code == 401 { signedIn = false; throw ProjectError.invalidProject("sign in again; your local changes remain intact") }
            let reason = (try? JSONDecoder().decode(JSONValue.self, from: data).object?["reason"]?.string) ?? "Server request failed (\(code))"
            throw ProjectError.invalidProject(reason)
        }
        return (data, code)
    }
    private func request<T: Decodable>(_ path: String, method: String = "GET", body: JSONValue? = nil, as type: T.Type) async throws -> (T, Int) {
        let (data, code) = try await send(path, method: method, body: body)
        return (try JSONDecoder().decode(type, from: data), code)
    }
    func login(signup: Bool = false) async {
        busy = true; defer { busy = false }
        do {
            let (result, _) = try await request("api/" + (signup ? "signup" : "login"), method: "POST", body: .object(["username": .string(username), "password": .string(password)]), as: LoginResponse.self)
            token = result.token; username = result.username; password = ""; signedIn = true
            try saveToken()
            UserDefaults.standard.set(server, forKey: "Frontstage.Sync.Server"); UserDefaults.standard.set(username, forKey: "Frontstage.Sync.Username")
            try await refresh(); status = "Signed in as \(username)."
        } catch { status = error.localizedDescription }
    }
    func restoreSession() async {
        busy = true; defer { busy = false }
        do {
            token = try loadToken(); try await refresh(); signedIn = true; status = "Session restored."
        } catch { status = error.localizedDescription }
    }
    func refresh() async throws { projects = try await request("api/projects", as: [RemoteProject].self).0 }
    func create(from workspace: Workspace) async {
        busy = true; defer { busy = false }
        let session = workspace.documentSessionID
        do {
            let value = try JSONDecoder().decode(JSONValue.self, from: workspace.project.encoded())
            let (snapshot, _) = try await request("api/projects", method: "POST", body: .object(["document": value]), as: RemoteProject.self)
            guard workspace.documentSessionID == session else { try await refresh(); status = "Shared copy created; the newly opened local project remains separate."; return }
            linked = snapshot; base = snapshot.document; try cacheBase(); try await refresh(); status = "Shared project created."
        } catch { status = error.localizedDescription }
    }
    func open(_ id: UUID, workspace: Workspace) async {
        guard workspace.confirmDiscardOrSave() else { return }
        busy = true; defer { busy = false }
        let session = workspace.documentSessionID, original = workspace.project
        do {
            let (snapshot, _) = try await request("api/projects/\(id.uuidString)", as: RemoteProject.self)
            guard let document = snapshot.document else { throw ProjectError.invalidProject("missing shared document") }
            guard workspace.documentSessionID == session, workspace.project == original else { throw ProjectError.invalidProject("the local project changed while opening; open the shared project again when ready") }
            workspace.loadCopy(try Project(data: JSONEncoder().encode(document)))
            linked = snapshot; base = document; try cacheBase(); status = "Opened revision \(snapshot.revision)."
        } catch { status = error.localizedDescription }
    }
    func synchronize(_ workspace: Workspace) async {
        guard let link = linked, link.access != "reader", !busy else { status = "Select an editable shared project first."; return }
        busy = true; defer { busy = false }
        let session = workspace.documentSessionID
        do {
            let sent = workspace.project, value = try JSONDecoder().decode(JSONValue.self, from: sent.encoded())
            let (result, code) = try await request("api/projects/\(link.id.uuidString)", method: "PUT", body: .object([
                "expectedRevision": .number(Decimal(link.revision)), "changeID": .string(UUID().uuidString), "document": value, "supportedFeatures": .array(Project.supportedWriteFeatures.sorted().map { .string($0) })
            ]), as: RemoteUpdate.self)
            guard workspace.documentSessionID == session, linked?.id == link.id else { status = "The previous project's upload finished. Your current project remains separate."; return }
            if code == 409, let remote = result.snapshot.document, let base {
                let local = try JSONDecoder().decode(JSONValue.self, from: workspace.project.encoded())
                let merge = ProjectMerge.mergeDocuments(base: base, local: local, remote: remote)
                if !merge.conflicts.isEmpty {
                    conflict = result.snapshot; conflicts = merge.conflicts; status = "Concurrent edits need a choice. Your local project is retained."
                } else {
                    let merged = try Project(data: JSONEncoder().encode(merge.value))
                    workspace.edit("Merge Shared Changes") { $0 = merged }
                    linked = result.snapshot; self.base = remote; try cacheBase()
                    status = "Nonconflicting edits merged. Sync again to upload the merged copy."
                }
            } else {
                linked = result.snapshot; base = result.snapshot.document; conflict = nil; conflicts = []; try cacheBase()
                status = workspace.project == sent ? "Synced revision \(result.snapshot.revision)." : "Revision \(result.snapshot.revision) uploaded; newer local edits still need sync."
            }
        } catch { status = "Sync failed; local changes retained. \(error.localizedDescription)" }
    }
    func pull(_ workspace: Workspace) async {
        guard let link = linked, let base, !busy else { return }
        busy = true; defer { busy = false }
        let session = workspace.documentSessionID
        do {
            let (remote, _) = try await request("api/projects/\(link.id.uuidString)", as: RemoteProject.self)
            guard workspace.documentSessionID == session, linked?.id == link.id, let document = remote.document else { return }
            let local = try JSONDecoder().decode(JSONValue.self, from: workspace.project.encoded())
            let merge = ProjectMerge.mergeDocuments(base: base, local: local, remote: document)
            if merge.conflicts.isEmpty {
                let merged = try Project(data: JSONEncoder().encode(merge.value))
                workspace.edit("Pull Shared Changes") { $0 = merged }
                linked = remote; self.base = document; conflict = nil; conflicts = []; try cacheBase()
                status = "Received revision \(remote.revision). Local changes are retained."
            } else {
                conflict = remote; conflicts = merge.conflicts; status = "Concurrent changes need a choice. Your local project is retained."
            }
        } catch { status = error.localizedDescription }
    }
    func share(username: String, access: String?) async {
        guard let link = linked, link.access == "owner", !busy else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await send("api/projects/\(link.id.uuidString)/members", method: "POST", body: .object([
                "username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)), "access": access.map(JSONValue.string) ?? .null
            ]))
            status = access == nil ? "Project access removed." : "Project access updated."
        } catch { status = error.localizedDescription }
    }
    func keepLocal(_ workspace: Workspace) async {
        guard let remote = conflict else { return }; linked = remote; base = remote.document; conflict = nil; conflicts = []
        await synchronize(workspace)
    }
    func takeRemote(_ workspace: Workspace) {
        guard let remote = conflict, let document = remote.document else { return }
        do {
            let directory = try cacheDirectory().appendingPathComponent("Conflict Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try workspace.project.save(to: directory.appendingPathComponent(UUID().uuidString + ".frontstage"))
            workspace.loadCopy(try Project(data: JSONEncoder().encode(document)))
            linked = remote; base = document; conflict = nil; conflicts = []; try cacheBase(); status = "Server copy loaded. Your previous local copy was kept in Sync/Conflict Backups."
        } catch { status = error.localizedDescription }
    }
    func signOut() async {
        if let url = try? endpoint("api/logout"), !token.isEmpty {
            var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 10
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "design.ratioprofile.frontstage.sync." + server, kSecAttrAccount as String: username]
        SecItemDelete(query as CFDictionary); token = ""; signedIn = false; status = "Signed out. Local project edits are retained."
    }
    private func saveToken() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "design.ratioprofile.frontstage.sync." + server, kSecAttrAccount as String: username]
        SecItemDelete(query as CFDictionary)
        var attributes = query; attributes[kSecValueData as String] = Data(token.utf8); attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw ProjectError.invalidProject("session could not be stored in Keychain") }
    }
    private func loadToken() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "design.ratioprofile.frontstage.sync." + server, kSecAttrAccount as String: username, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw ProjectError.invalidProject("no saved session; sign in first") }
        return token
    }
    private func cacheDirectory() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Frontstage/Sync", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory
    }
    private func cacheBase() throws {
        guard let linked else { return }; try JSONEncoder().encode(linked).write(to: cacheDirectory().appendingPathComponent(linked.id.uuidString + ".json"), options: .atomic)
    }
}

struct SharedProjectsView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var client: SharedProjectClient
    @State private var member = ""
    @State private var access = "editor"
    var body: some View {
        Form {
            Text("Shared Projects").font(.title2)
            TextField("Server URL", text: $client.server).disabled(client.signedIn)
            if !client.signedIn {
                TextField("Username", text: $client.username)
                SecureField("Password", text: $client.password)
                HStack {
                    Button("Sign In") { Task { await client.login() } }
                    Button("Create Account") { Task { await client.login(signup: true) } }
                    Button("Restore Keychain Session") { Task { await client.restoreSession() } }
                }.disabled(client.busy)
            } else {
                HStack {
                    Text("Signed in as \(client.username)")
                    Button("Refresh Projects") { Task { do { try await client.refresh() } catch { client.status = error.localizedDescription } } }
                    Button("Sign Out") { Task { await client.signOut() } }
                }
                ForEach(client.projects) { project in
                    HStack {
                        Text("\(project.name) · \(project.access) · revision \(project.revision)")
                        Spacer()
                        Button("Open") { Task { await client.open(project.id, workspace: workspace) } }.disabled(client.busy)
                    }
                }
                Button("Create Shared Copy of Current Project") { Task { await client.create(from: workspace) } }.disabled(client.busy)
                if let linked = client.linked {
                    Divider()
                    Text("Linked: \(linked.name) · revision \(linked.revision)").font(.headline)
                    Button("Get Latest Changes") { Task { await client.pull(workspace) } }.disabled(client.busy)
                    Button("Synchronize Local Changes") { Task { await client.synchronize(workspace) } }.disabled(client.busy || linked.access == "reader")
                    if linked.access == "owner" {
                        TextField("Registered username", text: $member)
                        Picker("Project access", selection: $access) {
                            Text("Editor").tag("editor"); Text("Reader").tag("reader"); Text("Remove access").tag("remove")
                        }
                        Button("Update Access") { Task { await client.share(username: member, access: access == "remove" ? nil : access) } }
                            .disabled(client.busy || member.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            if client.conflict != nil {
                Text("Conflicting fields").font(.headline)
                ForEach(client.conflicts, id: \.self) { Text($0).font(.caption.monospaced()) }
                HStack {
                    Button("Keep Local Copy") { Task { await client.keepLocal(workspace) } }
                    Button("Use Server Copy (Back Up Local)") { client.takeRemote(workspace) }
                }.disabled(client.busy)
            }
            Text(client.status).font(.callout).textSelection(.enabled)
            Text("Your Mac project stays available offline. Synchronization is explicit; keep saving locally or use recovery while disconnected.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: 900)
    }
}
#endif
