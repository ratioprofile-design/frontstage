import Foundation

public enum TamilTranscoder {
    /// Explicit conversion only: Bamini ASCII is indistinguishable from ordinary English.
    public static func baminiToUnicode(_ source: String) -> String {
        var result = source
        for (key, value) in BaminiMapping.pairs { result = result.replacingOccurrences(of: key, with: value) }
        return result.precomposedStringWithCanonicalMapping
    }
}

public struct ScriptLayoutSettings: Codable, Equatable, Sendable {
    public var fontName = "Courier"
    public var fontSize = 12.0
    public var lineHeight = 14.0
    public var paragraphSpacing = 10.0
    public init() {}
    public func validate() throws {
        guard !fontName.isEmpty, fontName.count <= 120, fontSize.isFinite, (8...24).contains(fontSize),
              lineHeight.isFinite, (fontSize...40).contains(lineHeight), paragraphSpacing.isFinite, (0...36).contains(paragraphSpacing) else { throw ProjectError.invalidProject("invalid screenplay typography") }
    }
}

public struct ParallelScriptRow: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var left: String
    public var right: String
    public init(left: String = "", right: String = "") { id = UUID().uuidString; self.left = left; self.right = right }
}

extension Project {
    public var scriptLayout: ScriptLayoutSettings {
        guard let value = state["frontstageScriptLayout"], let data = try? JSONEncoder().encode(value),
              let result = try? JSONDecoder().decode(ScriptLayoutSettings.self, from: data), (try? result.validate()) != nil else { return ScriptLayoutSettings() }
        return result
    }
    public mutating func setScriptLayout(_ layout: ScriptLayoutSettings) throws {
        try layout.validate()
        state["frontstageScriptLayout"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(layout))
    }
    public func parallelScript(sceneID: Decimal) -> [ParallelScriptRow] {
        guard let value = state["beats"]?.array?.first(where: { $0.object?["id"]?.decimal == sceneID })?.object?["frontstageParallel"],
              let data = try? JSONEncoder().encode(value) else { return [] }
        return (try? JSONDecoder().decode([ParallelScriptRow].self, from: data)) ?? []
    }
    public mutating func setParallelScript(sceneID: Decimal, rows: [ParallelScriptRow]) throws {
        guard Set(rows.map(\.id)).count == rows.count, rows.allSatisfy({ !$0.id.isEmpty }) else { throw ProjectError.invalidProject("duplicate parallel script rows") }
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(rows))
        try editBeat(sceneID) { $0["frontstageParallel"] = value }
    }
}
