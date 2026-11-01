import Foundation
import XCTest
@testable import FrontstageCore
final class TimelinePageMeasurementTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Entry: Decodable { var name: String; var ids: [String]; var spans: [String: TimelinePageSpan]; var expected: [String: Double]? }
        var cases: [Entry]
    }
    func testSharedTypesetSpanFixturesAndAtomicFallback() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("timeline-page-measurement.json")))
        for entry in fixture.cases {
            let result = TimelinePageMeasurement.weights(beatIDs: entry.ids, spans: entry.spans)
            if let expected = entry.expected { for (id, value) in expected { XCTAssertEqual(result?[id] ?? -1, value, accuracy: 0.0001, entry.name) } }
            else { XCTAssertNil(result, entry.name) }
        }
        var project = try Project(data: Data(contentsOf: root.appendingPathComponent("write-panels.frontstage")))
        let before = project
        let counts = ["beat-1": 0.5, "beat-2": 1.25]
        let pages = try StoryTimeline(project: project, timeBase: .pages, measuredPages: counts)
        XCTAssertTrue(pages.typesetPages); XCTAssertEqual(pages.beatPages["beat-2"], 0.5)
        XCTAssertEqual(pages.beatPageCounts, counts); XCTAssertEqual(project, before)
        let oldItems = [StoryTimeline.Item(id: "beat-1", title: "", start: 0, duration: 1, color: "", beatID: "beat-1"), StoryTimeline.Item(id: "beat-2", title: "", start: 1, duration: 1, color: "", beatID: "beat-2")]
        XCTAssertEqual(StoryTimeline.remappedPosition(1.4, from: oldItems, to: pages.tracks.first { $0.kind == "beats" }!.items) ?? -1, 1, accuracy: 0.0001)
        let incomplete = try StoryTimeline(project: project, timeBase: .pages, measuredPages: ["beat-1": 10])
        XCTAssertFalse(incomplete.typesetPages); XCTAssertNotEqual(incomplete.beatPages["beat-2"], 10)
        try project.updateBoardBeat("beat-1") { $0.timelineDuration = 3 }
        let time = try StoryTimeline(project: project, timeBase: .time, measuredPages: counts)
        XCTAssertEqual(time.beatTimes["beat-2"], 3); XCTAssertEqual(time.beatPages["beat-2"], 0.5)
    }
}
