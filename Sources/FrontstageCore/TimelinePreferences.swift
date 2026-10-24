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
    public var lines = 2
    public var collapsed: Set<String> = []
    public var hidden: Set<String> = []
    public init(compact: Bool = false) {
        if compact { hidden = ["episodes", "chapters", "sections", "tags", "characters", "heat"] }
    }
    public var isValid: Bool { primary != secondary && scale.isFinite && (2...180).contains(scale) && (1...3).contains(lines) }
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
