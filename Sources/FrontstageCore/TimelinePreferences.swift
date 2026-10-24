import Foundation

public enum StructuralBreakKind: String, CaseIterable, Codable, Sendable {
    case episode, act, chapter, section, custom
    public var trackID: String {
        switch self { case .episode: return "episodes"; case .act, .custom: return "acts"; case .chapter: return "chapters"; case .section: return "sections" }
    }
    public var title: String { rawValue.capitalized }
}

public struct TimelineDisplayPreferences: Codable, Equatable, Sendable {
    public var primary: TimelineTimeBase = .beats
    public var secondary: TimelineTimeBase = .time
    public var scale = 60.0
    public var colorStrength: Double? = nil
    public var lines = 2
    public var collapsed: Set<String> = []
    public var hidden: Set<String> = []
    public init(compact: Bool = false) {
        if compact { hidden = ["episodes", "chapters", "sections", "tags", "characters", "heat"] }
    }
    public var isValid: Bool { primary != secondary && scale.isFinite && (2...180).contains(scale) && (1...3).contains(lines) && (0...1).contains(colorStrength ?? 0.85) }
}

extension Project {
    public var timelineMinutesPerPage: Double {
        let value = state["frontstageTimelineOptions"]?.object?["minutesPerPage"]?.double ?? 1
        return value.isFinite && (0.1...10).contains(value) ? value : 1
    }
    public mutating func setTimelineMinutesPerPage(_ value: Double) throws {
        guard value.isFinite, (0.1...10).contains(value) else { throw ProjectError.invalidProject("Minutes per page must be between 0.1 and 10") }
        var options = state["frontstageTimelineOptions"]?.object ?? [:]
        options["minutesPerPage"] = .number(Decimal(value))
        state["frontstageTimelineOptions"] = .object(options)
    }
}

extension Project {
    public func timelineTrackGroup(kind: String, name: String) -> String {
        state["frontstageTimelineOptions"]?.object?["trackGroups"]?.object?[kind]?.object?[name]?.string ?? (kind == "tags" ? "General" : "Main Characters")
    }
    public mutating func setTimelineTrackGroup(kind: String, name: String, group: String) throws {
        let group = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["tags", "characters"].contains(kind), !name.isEmpty, !group.isEmpty, group.count <= 120 else {
            throw ProjectError.invalidProject("Choose a category or character group name (1–120 characters)")
        }
        var options = state["frontstageTimelineOptions"]?.object ?? [:]
        var groups = options["trackGroups"]?.object ?? [:]
        var members = groups[kind]?.object ?? [:]
        members[name] = .string(group); groups[kind] = .object(members)
        options["trackGroups"] = .object(groups); state["frontstageTimelineOptions"] = .object(options)
    }
}
