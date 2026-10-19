import Foundation

public enum ProjectError: Error, LocalizedError, Equatable {
    case invalidProject(String)
    case unsupportedVersion(Int)
    case sceneNotFound
    case legacyDestination

    public var errorDescription: String? {
        switch self {
        case .invalidProject(let reason): return "Invalid project: \(reason)"
        case .unsupportedVersion(let version): return "Frontstage format \(version) requires a newer app."
        case .sceneNotFound: return "The selected scene no longer exists."
        case .legacyDestination: return "Save a new .frontstage file; legacy .backstage files are import-only."
        }
    }
}

public struct Scene: Identifiable, Equatable, Sendable {
    public let id: Decimal
    public var title: String
    public var html: String
    public var summary: String
    public var heading: SceneHeading
    public var sceneNumber: String
    public var isDisabled: Bool
}

/// An explicit, versioned envelope isolates native saves from the original application.
public struct Project: Equatable, Sendable {
    public var name: String
    var state: [String: JSONValue]

    public init(name: String = "Untitled Screenplay") {
        self.name = name
        state = ["beats": .array([]), "nextId": .number(1)]
    }

    public init(data: Data, fallbackName: String = "Imported Screenplay") throws {
        guard let root = try JSONDecoder().decode(JSONValue.self, from: data).object else {
            throw ProjectError.invalidProject("the root must be an object")
        }
        if root["format"] == .string("frontstage") {
            guard case .number(let version) = root["version"] else {
                throw ProjectError.invalidProject("missing format version")
            }
            guard version == 1 else { throw ProjectError.unsupportedVersion(NSDecimalNumber(decimal: version).intValue) }
            guard let payload = root["project"]?.object else {
                throw ProjectError.invalidProject("missing project payload")
            }
            name = root["name"]?.string ?? fallbackName
            state = payload
        } else {
            name = fallbackName
            state = root
        }
        try validate()
        state = JSONValue.object(state).removingLegacyCredentials().object ?? [:]
    }

    private func validate() throws {
        guard let beats = state["beats"]?.array else {
            throw ProjectError.invalidProject("beats must be an array")
        }
        var ids = Set<Decimal>()
        for beat in beats {
            guard let fields = beat.object, case .number(let id) = fields["id"],
                  fields["title"]?.string != nil, fields["content"]?.string != nil else {
                throw ProjectError.invalidProject("each beat needs a numeric id, title and content")
            }
            guard id >= 0, id == id.roundedInteger else {
                throw ProjectError.invalidProject("beat ids must be non-negative integers")
            }
            guard ids.insert(id).inserted else {
                throw ProjectError.invalidProject("duplicate beat id")
            }
        }
    }

    public var scenes: [Scene] {
        (state["beats"]?.array ?? []).compactMap { value in
            guard let fields = value.object, case .number(let id) = fields["id"] else { return nil }
            let slug = fields["slug"]?.object ?? [:]
            return Scene(id: id, title: fields["title"]?.string ?? "", html: fields["content"]?.string ?? "",
                         summary: fields["summary"]?.string ?? "",
                         heading: SceneHeading(prefix: slug["prefix"]?.string ?? "INT.",
                             location: slug["location"]?.string ?? "", time: slug["time"]?.string ?? "DAY"),
                         sceneNumber: fields["sceneNumber"]?.string ?? "",
                         isDisabled: fields["isDisabled"] == .bool(true))
        }
    }

    public var preservedState: [String: JSONValue] { state }

    public mutating func addScene() -> Decimal {
        let maximum = scenes.map(\.id).max() ?? 0
        let next: Decimal
        if case .number(let stored) = state["nextId"], stored > maximum,
           stored == stored.roundedInteger { next = stored } else { next = maximum + 1 }
        var beats = state["beats"]?.array ?? []
        beats.append(.object([
            "id": .number(next), "title": .string("Untitled Scene"), "content": .string(""),
            "x": .number(0), "y": .number(0), "boardId": .number(0),
            "slug": .object(["prefix": .string("INT."), "location": .string(""), "time": .string("DAY")])
        ]))
        state["beats"] = .array(beats)
        state["nextId"] = .number(next + 1)
        return next
    }

    public mutating func updateScene(id: Decimal, title: String? = nil, html: String? = nil,
                                     summary: String? = nil, heading: SceneHeading? = nil,
                                     sceneNumber: String? = nil) throws {
        var beats = state["beats"]?.array ?? []
        guard let index = beats.firstIndex(where: { $0.object?["id"] == .number(id) }),
              var fields = beats[index].object else { throw ProjectError.sceneNotFound }
        if let title { fields["title"] = .string(title) }
        if let html { fields["content"] = .string(html) }
        if let summary { fields["summary"] = .string(summary) }
        if let heading {
            var slug = fields["slug"]?.object ?? [:]
            slug["prefix"] = .string(heading.prefix)
            slug["location"] = .string(heading.location)
            slug["time"] = .string(heading.time)
            // Legacy raw text is a derived cache. Keep it in sync when the structured heading changes.
            if slug["raw"] != nil { slug["raw"] = .string(heading.text) }
            fields["slug"] = .object(slug)
        }
        if let sceneNumber { fields["sceneNumber"] = .string(sceneNumber) }
        beats[index] = .object(fields)
        state["beats"] = .array(beats)
    }

    public func encoded() throws -> Data {
        let envelope = JSONValue.object([
            "format": .string("frontstage"), "version": .number(1),
            "name": .string(name), "project": .object(state)
        ]).removingLegacyCredentials()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    public static func load(from url: URL) throws -> Project {
        try Project(data: Data(contentsOf: url), fallbackName: url.deletingPathExtension().lastPathComponent)
    }

    public func save(to url: URL) throws {
        guard url.pathExtension.lowercased() == "frontstage" else { throw ProjectError.legacyDestination }
        // Resolve symlinks too: a .frontstage alias must not overwrite a .backstage source.
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.pathExtension.lowercased() == "frontstage" else { throw ProjectError.legacyDestination }
        try encoded().write(to: resolved, options: .atomic)
    }
}

private extension Decimal {
    var roundedInteger: Decimal {
        var source = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return rounded
    }
}
