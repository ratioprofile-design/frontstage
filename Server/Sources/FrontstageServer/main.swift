import Vapor
import FrontstageCore
import Foundation

struct Login: Content { var username: String; var password: String }
struct Token: Content { var token: String; var username: String }
struct Create: Content { var document: JSONValue }
struct Update: Content { var expectedRevision: Int; var changeID: UUID; var document: JSONValue }
struct Share: Content { var username: String; var access: Access? }
struct Health: Content { var status: String; var protocolVersion: Int }

struct BrowserHeaders: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        response.headers.replaceOrAdd(name: "Content-Security-Policy", value: "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; frame-ancestors 'none'")
        response.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
        return response
    }
}

var environment = try Environment.detect()
try LoggingSystem.bootstrap(from: &environment)
let app = try await Application.make(environment)
do {
    app.http.server.configuration.hostname = "127.0.0.1"
    app.routes.defaultMaxBodySize = "96mb"
    let directory = URL(fileURLWithPath: Environment.get("FRONTSTAGE_DATA_DIR") ?? app.directory.workingDirectory + "var")
    let store = try ProjectStore(directory: directory)
    if let value = Environment.get("FRONTSTAGE_WEB_ORIGIN"), !value.isEmpty {
        guard let url = URLComponents(string: value), let host = url.host, !host.isEmpty,
              url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "[::1]"].contains(host)),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, ["", "/"].contains(url.path) else {
            throw Abort(.internalServerError, reason: "FRONTSTAGE_WEB_ORIGIN must be an HTTPS origin or loopback HTTP origin")
        }
        let origin = url.scheme! + "://" + host + (url.port.map { ":\($0)" } ?? "")
        app.middleware.use(CORSMiddleware(configuration: .init(allowedOrigin: .custom(origin),
            allowedMethods: [.GET, .POST, .PUT, .OPTIONS], allowedHeaders: [.authorization, .contentType, .accept])), at: .beginning)
    }
    app.middleware.use(BrowserHeaders())
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.get("health") { _ in Health(status: "ok", protocolVersion: 1) }
    app.get { req async throws -> Response in try await req.fileio.asyncStreamFile(at: app.directory.publicDirectory + "index.html") }
    let user: @Sendable (Request) async throws -> String = { req in
        guard let token = req.headers.bearerAuthorization?.token else { throw Abort(.unauthorized) }
        return try await store.authenticate(token)
    }
    app.post("api", "signup") { req async throws -> Token in
        let input = try req.content.decode(Login.self)
        guard input.password.count >= 12 && input.password.utf8.count <= 72 else { throw Abort(.badRequest, reason: "Password must have at least 12 characters and at most 72 UTF-8 bytes") }
        let allow = Environment.get("FRONTSTAGE_ALLOW_SIGNUP") == "1"
        guard allow else { throw Abort(.forbidden, reason: "Account registration is disabled") }
        let hash = try await req.application.threadPool.runIfActive(eventLoop: req.eventLoop) { try Bcrypt.hash(input.password, cost: 12) }.get()
        try await store.register(username: input.username, hash: hash, allow: allow)
        let name = input.username.lowercased()
        return Token(token: try await store.login(name), username: name)
    }
    app.post("api", "login") { req async throws -> Token in
        let input = try req.content.decode(Login.self), name = input.username.lowercased()
        guard input.password.utf8.count <= 72, let account = await store.account(name) else { throw Abort(.unauthorized) }
        let valid = try await req.application.threadPool.runIfActive(eventLoop: req.eventLoop) { try Bcrypt.verify(input.password, created: account.passwordHash) }.get()
        guard valid else { throw Abort(.unauthorized) }
        return Token(token: try await store.login(name), username: name)
    }
    app.post("api", "logout") { req async throws -> HTTPStatus in
        _ = try await user(req)
        try await store.logout(req.headers.bearerAuthorization!.token)
        return .noContent
    }
    app.get("api", "projects") { req async throws -> [ProjectSummary] in try await store.list(user: user(req)) }
    app.post("api", "projects") { req async throws -> ProjectSnapshot in
        let name = try await user(req), input = try req.content.decode(Create.self)
        return try await store.create(document: input.document, user: name)
    }
    app.get("api", "projects", ":id") { req async throws -> ProjectSnapshot in
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        return try await store.get(id, user: user(req))
    }
    app.put("api", "projects", ":id") { req async throws -> Response in
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        let name = try await user(req), input = try req.content.decode(Update.self)
        let result = try await store.update(id, user: name, expected: input.expectedRevision, changeID: input.changeID, document: input.document)
        return try await result.encodeResponse(status: result.conflict ? .conflict : .ok, for: req)
    }
    app.post("api", "projects", ":id", "members") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        let name = try await user(req), input = try req.content.decode(Share.self)
        try await store.share(id, owner: name, member: input.username.lowercased(), access: input.access)
        return .noContent
    }
    try await app.execute()
    try await app.asyncShutdown()
} catch {
    try? await app.asyncShutdown()
    throw error
}
