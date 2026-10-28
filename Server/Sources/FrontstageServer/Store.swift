import Foundation
import Vapor
import Crypto
import FrontstageCore

struct Account: Codable, Sendable {
    var username: String
    var passwordHash: String
}
struct Session: Codable, Sendable { var username: String; var expires: Date }
enum Access: String, Codable, Sendable { case owner, editor, reader }
struct SharedProject: Codable, Sendable {
    var id: UUID
    var name: String
    var owner: String
    var members: [String: Access]
    var revision: Int
    var document: JSONValue
    var modifiedBy: String
    var changes: [String]
}
struct State: Codable, Sendable {
    var version = 1
    var accounts: [String: Account] = [:]
    var sessions: [String: Session] = [:]
    var projects: [String: SharedProject] = [:]
}
struct ProjectSnapshot: Content, Sendable {
    var id: UUID
    var name: String
    var revision: Int
    var document: JSONValue
    var access: Access
    var modifiedBy: String
}
struct ProjectSummary: Content, Sendable { var id: UUID; var name: String; var revision: Int; var access: Access }
struct UpdateResult: Content, Sendable { var conflict: Bool; var snapshot: ProjectSnapshot }

actor ProjectStore {
    private var state: State
    private let file: URL
    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        file = directory.appendingPathComponent("frontstage-server.json")
        state = FileManager.default.fileExists(atPath: file.path) ? try JSONDecoder().decode(State.self, from: Data(contentsOf: file)) : State()
        guard state.version == 1 else { throw Abort(.internalServerError, reason: "Unsupported server data version") }
    }
    private func commit(_ candidate: State) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(candidate).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        state = candidate
    }
    func account(_ name: String) -> Account? { state.accounts[name.lowercased()] }
    func register(username: String, hash: String, allow: Bool) throws {
        guard allow else { throw Abort(.forbidden, reason: "Account registration is disabled") }
        let name = username.lowercased()
        guard name.range(of: "^[a-z0-9_]{3,40}$", options: .regularExpression) != nil else { throw Abort(.badRequest, reason: "Use 3–40 letters, numbers or underscores") }
        guard state.accounts[name] == nil else { throw Abort(.conflict, reason: "Username already exists") }
        var next = state; next.accounts[name] = Account(username: name, passwordHash: hash); try commit(next)
    }
    func login(_ name: String) throws -> String {
        let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        var next = state; next.sessions = next.sessions.filter { $0.value.expires > Date() }
        next.sessions[Self.hash(token)] = Session(username: name, expires: Date().addingTimeInterval(7 * 24 * 60 * 60)); try commit(next)
        return token
    }
    func authenticate(_ token: String) throws -> String {
        guard let session = state.sessions[Self.hash(token)], session.expires > Date() else { throw Abort(.unauthorized) }
        return session.username
    }
    func logout(_ token: String) throws { var next = state; next.sessions.removeValue(forKey: Self.hash(token)); try commit(next) }
    static func hash(_ token: String) -> String { SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func access(_ project: SharedProject, user: String) -> Access? { project.owner == user ? .owner : project.members[user] }
    private func snapshot(_ project: SharedProject, user: String) throws -> ProjectSnapshot {
        guard let access = access(project, user: user) else { throw Abort(.notFound) }
        return ProjectSnapshot(id: project.id, name: project.name, revision: project.revision, document: project.document, access: access, modifiedBy: project.modifiedBy)
    }
    func list(user: String) -> [ProjectSummary] {
        state.projects.values.compactMap { project in
            guard let access = access(project, user: user) else { return nil }
            return ProjectSummary(id: project.id, name: project.name, revision: project.revision, access: access)
        }.sorted { $0.name < $1.name }
    }
    func get(_ id: UUID, user: String) throws -> ProjectSnapshot {
        guard let project = state.projects[id.uuidString] else { throw Abort(.notFound) }; return try snapshot(project, user: user)
    }
    private func validated(_ document: JSONValue) throws -> Project {
        do {
            let project = try Project(data: JSONEncoder().encode(document))
            _ = try project.whiteboard(); _ = try project.studio(); return project
        } catch { throw Abort(.badRequest, reason: error.localizedDescription) }
    }
    func create(document: JSONValue, user: String) throws -> ProjectSnapshot {
        let project = try validated(document)
        let clean = try JSONDecoder().decode(JSONValue.self, from: project.encoded())
        let id = UUID(), record = SharedProject(id: id, name: project.name, owner: user, members: [:], revision: 1, document: clean, modifiedBy: user, changes: [])
        var next = state; next.projects[id.uuidString] = record; try commit(next); return try snapshot(record, user: user)
    }
    func update(_ id: UUID, user: String, expected: Int, changeID: UUID, document: JSONValue, supportedFeatures: Set<String> = []) throws -> UpdateResult {
        guard var current = state.projects[id.uuidString], let role = access(current, user: user) else { throw Abort(.notFound) }
        guard role != .reader else { throw Abort(.forbidden) }
        if current.changes.contains(changeID.uuidString) { return UpdateResult(conflict: false, snapshot: try snapshot(current, user: user)) }
        guard current.revision == expected else { return UpdateResult(conflict: true, snapshot: try snapshot(current, user: user)) }
        let project = try validated(document)
        let prior = try validated(current.document)
        guard !prior.usesOneBeatPerScene || project.usesOneBeatPerScene else { throw Abort(.badRequest, reason: "Update Frontstage: the scene model cannot be downgraded") }
        do { try project.validateWriterCompatibility(previous: prior, supported: supportedFeatures) }
        catch { throw Abort(.badRequest, reason: error.localizedDescription) }
        current.document = try JSONDecoder().decode(JSONValue.self, from: project.encoded())
        current.name = project.name; current.revision += 1; current.modifiedBy = user
        current.changes = Array((current.changes + [changeID.uuidString]).suffix(100))
        var next = state; next.projects[id.uuidString] = current; try commit(next)
        return UpdateResult(conflict: false, snapshot: try snapshot(current, user: user))
    }
    func share(_ id: UUID, owner: String, member: String, access role: Access?) throws {
        guard var project = state.projects[id.uuidString], project.owner == owner else { throw Abort(.forbidden) }
        guard state.accounts[member] != nil, member != owner, role != .owner else { throw Abort(.badRequest, reason: "Choose an existing account and reader/editor access") }
        project.members[member] = role
        var next = state; next.projects[id.uuidString] = project; try commit(next)
    }
}
