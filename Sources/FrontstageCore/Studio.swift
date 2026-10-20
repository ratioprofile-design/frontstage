import Foundation

public enum StudioKind: String, Codable, CaseIterable, Sendable {
    case research, crew, continuity, shot, audition
    public var label: String { self == .shot ? "Shots & Storyboards" : rawValue.capitalized }
}

public struct StudioRecord: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var kind: StudioKind
    public var title: String
    public var body = ""
    public var sceneID: Decimal?
    public var beatID: String?
    public var fields: [String: String] = [:]
    public var assetIDs: [String] = []
    public init(kind: StudioKind, title: String, sceneID: Decimal? = nil, beatID: String? = nil) {
        self.kind = kind; self.title = title; self.sceneID = sceneID; self.beatID = beatID
    }
}

public struct StudioAsset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var filename: String
    public var data: Data
    public init(filename: String, data: Data) { id = UUID().uuidString; self.filename = filename; self.data = data }
    public func save(to url: URL) throws {
        let resolved = url.resolvingSymlinksInPath()
        guard !["backstage", "frontstage"].contains(resolved.pathExtension.lowercased()),
              !["backstage", "frontstage"].contains(url.pathExtension.lowercased()) else { throw ProjectError.legacyDestination }
        try data.write(to: resolved, options: .atomic)
    }
}

public struct Studio: Codable, Equatable, Sendable {
    public var version = 1
    public var records: [StudioRecord] = []
    public var assets: [StudioAsset] = []
    public init() {}
    public func validate() throws {
        guard version == 1 else { throw ProjectError.invalidProject("unsupported research/media version") }
        let assetIDs = Set(assets.map(\.id))
        guard Set(records.map(\.id)).count == records.count, assetIDs.count == assets.count,
              records.allSatisfy({ !$0.id.isEmpty && $0.assetIDs.allSatisfy(assetIDs.contains) }),
              assets.allSatisfy({ !$0.id.isEmpty && !$0.filename.isEmpty && $0.data.count <= 10 * 1024 * 1024 }),
              assets.reduce(0, { $0 + $1.data.count }) <= 64 * 1024 * 1024 else { throw ProjectError.invalidProject("invalid media references or attachment limit exceeded (10 MB per file, 64 MB per project)") }
    }
}

extension Project {
    public func studio() throws -> Studio {
        guard let raw = state["frontstageStudio"] else { return Studio() }
        let value = try JSONDecoder().decode(Studio.self, from: JSONEncoder().encode(raw)); try value.validate(); return value
    }
    public mutating func editStudio(_ operation: (inout Studio) throws -> Void) throws {
        var value = try studio(); try operation(&value); try value.validate()
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        var fields = state["frontstageStudio"]?.object ?? [:]
        for (key, item) in encoded.object ?? [:] {
            if let list = item.array, let previous = fields[key]?.array {
                let old = previous.reduce(into: [String: [String: JSONValue]]()) { if let id = $1.object?["id"]?.string { $0[id] = $1.object } }
                fields[key] = .array(list.map { new in
                    guard let object = new.object, let id = object["id"]?.string else { return new }
                    var merged = old[id] ?? [:]
                    for optional in ["sceneID", "beatID"] where object[optional] == nil { merged.removeValue(forKey: optional) }
                    object.forEach { merged[$0.key] = $0.value }; return .object(merged)
                })
            } else { fields[key] = item }
        }
        state["frontstageStudio"] = .object(fields)
    }
    @discardableResult
    public mutating func addStudioRecord(kind: StudioKind, title: String, sceneID: Decimal? = nil, beatID: String? = nil) throws -> String {
        let record = StudioRecord(kind: kind, title: title, sceneID: sceneID, beatID: beatID)
        try editStudio { $0.records.append(record) }; return record.id
    }
    public mutating func updateStudioRecord(_ id: String, _ action: (inout StudioRecord) throws -> Void) throws {
        try editStudio { value in
            guard let i = value.records.firstIndex(where: { $0.id == id }) else { throw ProjectError.invalidProject("record no longer exists") }
            try action(&value.records[i])
        }
    }
    @discardableResult
    public mutating func attachStudioAsset(to recordID: String, filename: String, data: Data) throws -> String {
        let asset = StudioAsset(filename: URL(fileURLWithPath: filename).lastPathComponent, data: data)
        try editStudio { value in
            guard let i = value.records.firstIndex(where: { $0.id == recordID }) else { throw ProjectError.invalidProject("record no longer exists") }
            value.assets.append(asset); value.records[i].assetIDs.append(asset.id)
        }
        return asset.id
    }
    public func studioCSV(kind: StudioKind) throws -> String {
        let value = try studio()
        return ProductionCSV.encode([["ID", "Title", "Scene", "Beat", "Notes", "Details", "Attachments"]] + value.records.filter { $0.kind == kind }.map { record in
            [record.id, record.title, record.sceneID.map { "\($0)" } ?? "", record.beatID ?? "", record.body,
             record.fields.keys.sorted().map { "\($0): \(record.fields[$0] ?? "")" }.joined(separator: "; "),
             record.assetIDs.compactMap { id in value.assets.first { $0.id == id }?.filename }.joined(separator: "; ")]
        })
    }
    public func dayOutOfDaysCSV() -> String {
        let days = productionDays.sorted { $0.date == $1.date ? $0.number < $1.number : $0.date < $1.date }
        let roles = Set(days.flatMap { scheduledScenes(for: $0.id).flatMap { sceneCharacters($0.id) } }).sorted()
        var rows = [["Character"] + days.map { "Day \($0.number) \($0.date)" }]
        for role in roles {
            let work = days.map { day in scheduledScenes(for: day.id).contains { sceneCharacters($0.id).contains(role) } }
            let first = work.firstIndex(of: true), last = work.lastIndex(of: true)
            rows.append([role] + work.indices.map { i in
                if work[i] {
                    if i == first && i == last { return "SWF" }
                    if i == first { return "SW" }; if i == last { return "WF" }; return "W"
                }
                if let first, let last, i > first && i < last { return "H" }; return ""
            })
        }
        return ProductionCSV.encode(rows)
    }
}
