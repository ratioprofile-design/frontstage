import Foundation

public struct SceneRevision: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let date: Date
    public let title: String
    public let html: String
    public let summary: String
    public let hasBeatBoundaries: Bool
}

extension Project {
    mutating func editBeat(_ id: Decimal, _ operation: (inout [String: JSONValue]) throws -> Void) throws {
        var beats = state["beats"]?.array ?? []
        guard let index = beats.firstIndex(where: { $0.object?["id"] == .number(id) }),
              var beat = beats[index].object else { throw ProjectError.sceneNotFound }
        try operation(&beat)
        beats[index] = .object(beat)
        state["beats"] = .array(beats)
    }

    public func revisions(for sceneID: Decimal) -> [SceneRevision] {
        let beat = state["beats"]?.array?.first { $0.object?["id"] == .number(sceneID) }?.object
        return (beat?["versions"]?.array ?? []).compactMap { value in
            guard let item = value.object, let id = item["id"]?.string, let html = item["content"]?.string else { return nil }
            let milliseconds: Double
            if case .number(let number) = item["timestamp"] { milliseconds = NSDecimalNumber(decimal: number).doubleValue }
            else { milliseconds = 0 }
            return SceneRevision(id: id, label: item["frontstageLabel"]?.string ?? item["title"]?.string ?? "Revision",
                date: Date(timeIntervalSince1970: milliseconds / 1000), title: item["title"]?.string ?? "", html: html, summary: item["summary"]?.string ?? "", hasBeatBoundaries: item["frontstageSnippets"]?.array != nil)
        }.sorted { $0.date > $1.date }
    }

    @discardableResult
    public mutating func saveRevision(sceneID: Decimal, label: String, now: Date = Date()) throws -> String {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ProjectError.invalidProject("a revision needs a name") }
        let id = UUID().uuidString
        let snippets = state["frontstageWhiteboard"]?.object?["beats"]?.array?.filter { $0.object?["sceneID"]?.decimal == sceneID }
        try editBeat(sceneID) { beat in
            var snapshot: [String: JSONValue] = [
                "id": .string(id), "frontstageLabel": .string(clean),
                "timestamp": .number(Decimal(now.timeIntervalSince1970 * 1000)),
                "title": beat["title"] ?? .string(""), "content": beat["content"] ?? .string(""),
                "summary": beat["summary"] ?? .string("")
            ]
            snapshot["frontstageEditorial"] = .object([
                "slug": beat["slug"] ?? .null, "sceneNumber": beat["sceneNumber"] ?? .null
            ])
            if let snippets { snapshot["frontstageSnippets"] = .array(snippets) }
            var versions = beat["versions"]?.array ?? []
            versions.append(.object(snapshot))
            beat["versions"] = .array(versions)
        }
        return id
    }

    public mutating func restoreRevision(sceneID: Decimal, revisionID: String) throws {
        guard scenes.first(where: { $0.id == sceneID })?.isTextLocked == false else { throw ProjectError.invalidProject("Unlock the scene before restoring") }
        let beat = state["beats"]?.array?.first { $0.object?["id"] == .number(sceneID) }?.object
        guard let version = beat?["versions"]?.array?.first(where: { $0.object?["id"] == .string(revisionID) })?.object,
              version["content"]?.string != nil else { throw ProjectError.invalidProject("revision not found") }
        var candidate = self
        let native = state["frontstageWhiteboard"] != nil
        let savedSnippets: [BoardBeat]?
        if let raw = version["frontstageSnippets"] { savedSnippets = try JSONDecoder().decode([BoardBeat].self, from: JSONEncoder().encode(raw)) }
        else { savedSnippets = nil }
        let archivedIDs = Set(pulledOutBeats.map(\.id))
        if savedSnippets?.contains(where: { archivedIDs.contains($0.id) }) == true {
            throw ProjectError.invalidProject("Restore the pulled-out beats from Research before restoring this snapshot")
        }
        let currentSnippets = native ? try whiteboard().beats.filter { $0.sceneID == sceneID } : []
        if native {
            let board = try whiteboard()
            guard !currentSnippets.contains(where: { board.isLocked($0) }) else { throw ProjectError.invalidProject("Unlock the scene's beats before restoring") }
            if let savedSnippets, savedSnippets.contains(where: { beat in beat.sceneID != sceneID || !board.blocks.contains(where: { $0.id == beat.blockID }) }) { throw ProjectError.invalidProject("A saved beat container is missing; restore it before restoring this snapshot") }
        }
        if native && savedSnippets == nil && currentSnippets.count > 1 {
            throw ProjectError.invalidProject("this older revision has no snippet boundaries; use a revision captured after whiteboard migration")
        }
        try candidate.saveRevision(sceneID: sceneID, label: "Before restoring \(version["frontstageLabel"]?.string ?? "revision")")
        try candidate.editBeat(sceneID) { fields in
            for key in ["title", "summary", "content"] where key != "content" || !native || savedSnippets?.isEmpty == true || (savedSnippets == nil && currentSnippets.isEmpty) { if let value = version[key] { fields[key] = value } }
            if let editorial = version["frontstageEditorial"]?.object {
                for key in ["slug", "sceneNumber"] {
                    if editorial[key] == .null { fields.removeValue(forKey: key) }
                    else if let value = editorial[key] { fields[key] = value }
                }
            }
        }
        if native {
            try candidate.editWhiteboard { board in
                if let savedSnippets {
                    let oldIDs = Set(board.beats.filter { $0.sceneID == sceneID }.map(\.id))
                    board.beats.removeAll { $0.sceneID == sceneID }; board.beats.append(contentsOf: savedSnippets)
                    let ids = Set(board.beats.map(\.id))
                    board.dependencies.removeAll { (oldIDs.contains($0.cause) || oldIDs.contains($0.effect)) && (!ids.contains($0.cause) || !ids.contains($0.effect)) }
                } else if let i = board.beats.firstIndex(where: { $0.sceneID == sceneID }) {
                    board.beats[i].html = version["content"]?.string ?? ""
                    board.beats[i].title = version["title"]?.string ?? board.beats[i].title
                }
            }
        }
        self = candidate
    }
}

public struct RevisionDiffLine: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case unchanged, removed, added }
    public let id: Int
    public let kind: Kind
    public let text: String

    public static func compare(before: String, after: String) -> [Self] {
        let old = before.components(separatedBy: "\n"), new = after.components(separatedBy: "\n")
        let difference = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let index, _, _): removed.insert(index)
            case .insert(let index, _, _): inserted.insert(index)
            }
        }
        var i = 0, j = 0
        var rows: [Self] = []
        func append(_ kind: Kind, _ text: String) { rows.append(Self(id: rows.count, kind: kind, text: text)) }
        while i < old.count || j < new.count {
            if i < old.count && removed.contains(i) { append(.removed, old[i]); i += 1 }
            else if j < new.count && inserted.contains(j) { append(.added, new[j]); j += 1 }
            else if i < old.count && j < new.count { append(.unchanged, old[i]); i += 1; j += 1 }
            else if i < old.count { append(.removed, old[i]); i += 1 }
            else { append(.added, new[j]); j += 1 }
        }
        return rows
    }
}
