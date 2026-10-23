import XCTest
@testable import FrontstageCore
final class StoryTimelineTests: XCTestCase {
    func testTimeBasesEmotionCheckpointsAndPersistence() throws {
        var p = Project()
        let lane = try p.createBoardItem(.lane, layerID: "main", position: .init())
        let a = try p.createBoardItem(.beat, layerID: lane, position: .init(x: 40, y: 40))
        let b = try p.createBoardItem(.beat, layerID: lane, position: .init(x: 400, y: 40))
        try p.updateBoardBeat(a) { $0.tags = ["Danger"]; $0.characters = ["VENBA"]; $0.emotionChanges = ["Danger": 20]; $0.tensions = ["Danger": 3]; $0.timelineDuration = 4 }
        try p.updateBoardBeat(b) { $0.tags = ["Danger"]; $0.emotionChanges = ["Danger": 80]; $0.emotionAbsoluteTags = ["Danger"] }
        let timeline = try StoryTimeline(project: p)
        XCTAssertEqual(timeline.tracks.first { $0.kind == "beats" }?.items.map(\.start), [0, 1])
        XCTAssertEqual(timeline.tracks.first { $0.kind == "tags" }?.items.map(\.value), [20, 80])
        XCTAssertEqual(timeline.tracks.first { $0.kind == "heat" }?.items.count, 1)
        let time = try StoryTimeline(project: p, timeBase: .time)
        XCTAssertEqual(time.tracks.first { $0.kind == "beats" }?.items.last?.start, 4)
        XCTAssertEqual(StoryTimeline.clock(12.5), "00:12:30")
        XCTAssertEqual(try Project(data: p.encoded()), p)
        try p.reorderTimelineBeats([b], before: a)
        XCTAssertEqual(try p.whiteboard().orderedBeats.first?.id, b)
    }
    func testGroupSplitMergeAndLockedPushRollback() throws {
        var p = Project()
        let lane = try p.createBoardItem(.lane, layerID: "main", position: .init())
        let group = try p.createBoardItem(.group, layerID: lane, position: .init(x: 60, y: 40))
        _ = try p.createBoardItem(.beat, layerID: lane, position: .init(x: 70, y: 80), parentID: group)
        let b = try p.createBoardItem(.beat, layerID: lane, position: .init(x: 70, y: 120), parentID: group)
        try p.splitBoardGroup(at: b)
        var board = try p.whiteboard()
        XCTAssertEqual(board.blocks.filter { $0.containerKind == "beatGroup" }.count, 2)
        try p.mergeBoardContainers(Set(board.blocks.filter { $0.containerKind == "beatGroup" }.map(\.id)))
        board = try p.whiteboard()
        XCTAssertEqual(board.blocks.filter { $0.containerKind == "beatGroup" }.count, 1)
        try p.pushWhiteboard(from: 0, by: 100)
        try p.editWhiteboard { $0.blocks[0].locked = true }
        let before = p
        XCTAssertThrowsError(try p.pushWhiteboard(from: 0, by: 100))
        XCTAssertEqual(p, before)
    }
}
