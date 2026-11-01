import Foundation

/// Fractions of the actual paginated content area, independent of display zoom.
public struct TimelinePageSpan: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) { self.start = start; self.end = end }
}
public enum TimelinePageMeasurement {
    /// Incomplete/ambiguous layout falls back as a whole, never mixing measured and estimated beats.
    public static func weights(beatIDs: [String], spans: [String: TimelinePageSpan]) -> [String: Double]? {
        guard !beatIDs.isEmpty, Set(beatIDs).count == beatIDs.count else { return nil }
        var previous = -1.0
        for id in beatIDs {
            guard let span = spans[id], span.start.isFinite, span.end.isFinite, span.start >= 0, span.end > span.start, span.start > previous else { return nil }
            previous = span.start
        }
        var result: [String: Double] = [:]
        for (index, id) in beatIDs.enumerated() {
            let start = index == 0 ? 0 : spans[id]!.start
            let end = index + 1 < beatIDs.count ? spans[beatIDs[index + 1]]!.start : spans[id]!.end
            guard end > start else { return nil }
            result[id] = end - start
        }
        return result
    }
}
