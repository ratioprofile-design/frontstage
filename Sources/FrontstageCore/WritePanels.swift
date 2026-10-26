import Foundation

public struct WritingNote: Identifiable, Equatable, Sendable {
    public let id: String
    public let content: String
    public let color: String
    public let timestamp: Double
    public let editable: Bool
}
public struct SceneCard: Identifiable, Equatable, Sendable {
    public let scene: Scene
    public let number: String
    public let beats: [BoardBeat]
    public let versionCount: Int
    public var id: Decimal { scene.id }
}
extension Project {
    public func sceneReadiness(_ sceneID: Decimal) -> String {
        let status = state["beats"]?.array?.first { $0.object?["id"]?.decimal == sceneID }?.object?["status"]?.string
        return status == "ready" ? "Ready" : "Work in progress"
    }
    public func sceneCards() throws -> [SceneCard] {
        let segments = try orderedScript(includeInactive: true)
        let ordered = try whiteboard().orderedBeats
        var ids = [Decimal]()
        for id in segments.map({ $0.scene.id }) + scenes.map(\.id) where !ids.contains(id) { ids.append(id) }
        return ids.compactMap { id in
            guard let scene = scenes.first(where: { $0.id == id }) else { return nil }
            return SceneCard(scene: scene, number: segments.first(where: { $0.scene.id == id })?.number ?? scene.sceneNumber,
                beats: ordered.filter { $0.sceneID == id }, versionCount: revisions(for: id).count)
        }
    }
    public mutating func updateSceneSummary(_ sceneID: Decimal, summary: String) throws {
        guard let scene = scenes.first(where: { $0.id == sceneID }) else { throw ProjectError.sceneNotFound }
        guard !scene.isTextLocked else { throw ProjectError.invalidProject("Unlock the scene before editing its summary") }
        try editBeat(sceneID) { $0["summary"] = .string(summary) }
    }
    private func noteOwner(_ sceneID: Decimal?) -> [String: JSONValue] {
        if let sceneID { return state["beats"]?.array?.first { $0.object?["id"]?.decimal == sceneID }?.object ?? [:] }
        return state
    }
    public func writingNotes(sceneID: Decimal?) -> [WritingNote] {
        let values = noteOwner(sceneID)[sceneID == nil ? "globalNotes" : "notes"]?.array ?? []
        return values.enumerated().map { index, value in
            let item = value.object ?? [:]
            let media = (item["content"]?.string ?? "").range(of: "<(audio|video|iframe|object)\\b", options: .regularExpression) != nil
            let supported = !media && item["id"]?.string != nil && item["content"]?.string != nil && item["audio"] == nil && item["audioUrl"] == nil && (item["type"] == nil || item["type"]?.string == "text")
            return WritingNote(id: item["id"]?.string ?? "legacy-\(index)", content: item["content"]?.string ?? "Unsupported imported note (preserved)",
                color: item["color"]?.string ?? "#fff4bc", timestamp: NSDecimalNumber(decimal: item["timestamp"]?.decimal ?? 0).doubleValue, editable: supported)
        }
    }
    public func legacyScratchpad(sceneID: Decimal?) -> String? { noteOwner(sceneID)["scratchpad"]?.string }
    private mutating func editNotes(sceneID: Decimal?, _ operation: (inout [JSONValue]) throws -> Void) throws {
        let key = sceneID == nil ? "globalNotes" : "notes"
        if let sceneID {
            guard scenes.first(where: { $0.id == sceneID })?.isTextLocked == false else { throw ProjectError.invalidProject("The scene is missing or locked") }
            try editBeat(sceneID) { owner in
                guard owner[key] == nil || owner[key]?.array != nil else { throw ProjectError.invalidProject("Unsupported imported notes are preserved") }
                var notes = owner[key]?.array ?? []; try operation(&notes); owner[key] = .array(notes)
            }
        } else {
            guard state[key] == nil || state[key]?.array != nil else { throw ProjectError.invalidProject("Unsupported imported notes are preserved") }
            var notes = state[key]?.array ?? []; try operation(&notes); state[key] = .array(notes)
        }
    }
    @discardableResult public mutating func addWritingNote(sceneID: Decimal?, content: String = "", color: String = "#fff4bc", now: Date = Date()) throws -> String {
        let id = UUID().uuidString
        try editNotes(sceneID: sceneID) { $0.append(.object(["id": .string(id), "content": .string(content), "color": .string(color), "timestamp": .number(Decimal(now.timeIntervalSince1970 * 1000))])) }
        return id
    }
    public mutating func updateWritingNote(sceneID: Decimal?, id: String, content: String? = nil, color: String? = nil) throws {
        guard writingNotes(sceneID: sceneID).contains(where: { $0.id == id && $0.editable }) else { throw ProjectError.invalidProject("This imported note is read-only or no longer exists") }
        try editNotes(sceneID: sceneID) { notes in
            guard let i = notes.firstIndex(where: { $0.object?["id"]?.string == id }), var item = notes[i].object else { throw ProjectError.invalidProject("Note not found") }
            if let content { item["content"] = .string(content); item["frontstageMarkdown"] = .string(NoteMarkdown.source(fromHTML: content)) }; if let color { item["color"] = .string(color) }; notes[i] = .object(item)
        }
    }
    public mutating func removeWritingNote(sceneID: Decimal?, id: String) throws {
        try editNotes(sceneID: sceneID) { notes in
            guard let i = notes.firstIndex(where: { $0.object?["id"]?.string == id }) else { throw ProjectError.invalidProject("Note not found") }; notes.remove(at: i)
        }
    }
    public mutating func moveWritingNote(sceneID: Decimal?, id: String, offset: Int) throws {
        try editNotes(sceneID: sceneID) { notes in
            guard let i = notes.firstIndex(where: { $0.object?["id"]?.string == id }), notes.indices.contains(i + offset) else { return }; let value = notes.remove(at: i); notes.insert(value, at: i + offset)
        }
    }
    public mutating func reorderSceneCard(_ sceneID: Decimal, before target: Decimal) throws {
        guard scenes.first(where: { $0.id == sceneID })?.isTextLocked == false, scenes.first(where: { $0.id == target })?.isTextLocked == false else { throw ProjectError.invalidProject("Unlock the scene before reordering") }
        let ordered = try whiteboard().orderedBeats, ids = ordered.filter { $0.sceneID == sceneID }.map(\.id)
        let indices = ordered.indices.filter { ordered[$0].sceneID == sceneID }
        guard let first = indices.first, let last = indices.last, last - first + 1 == indices.count else { throw ProjectError.invalidProject("Interleaved scenes cannot move as a single card") }
        guard let destination = ordered.first(where: { $0.sceneID == target }) else { throw ProjectError.invalidProject("The destination has no beats") }
        try reorderTimelineBeats(Set(ids), before: destination.id)
    }
}
