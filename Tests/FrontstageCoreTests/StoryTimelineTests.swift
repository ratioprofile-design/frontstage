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
        try p.updateBoardBeat(b) { $0.emotionChanges = nil; $0.emotionAbsoluteTags = nil }
        XCTAssertEqual(try StoryTimeline(project: p).tracks.first { $0.kind == "tags" }?.items.map(\.value), [20, 20])
        try p.updateBoardBeat(a) { $0.timelineDuration = nil }
        XCTAssertNil(try p.whiteboard().beats.first { $0.id == a }?.timelineDuration)
        try p.reorderTimelineBeats([b], before: a)
        XCTAssertEqual(try p.whiteboard().orderedBeats.first?.id, b)
    }
    func testIndependentBreaksTimingAndDisplayPreferences() throws {
        var p = Project()
        let lane = try p.createBoardItem(.lane, layerID: "main", position: .init())
        var ids: [String] = []
        for index in 0..<4 { ids.append(try p.createBoardItem(.beat, layerID: lane, position: .init(x: Double(index * 300), y: 40))) }
        _ = try p.addStoryMilestone(title: "Episode One", page: 0, kind: .episode)
        _ = try p.addStoryMilestone(title: "Episode Two", page: 3, kind: .episode)
        let act = try p.addStoryMilestone(title: "Act One", page: 0, kind: .act)
        _ = try p.addStoryMilestone(title: "Act Two", page: 4.5, kind: .act)
        let model = try StoryTimeline(project: p)
        XCTAssertEqual(model.tracks.first { $0.kind == "episodes" }?.items.first?.duration, 2)
        XCTAssertEqual(model.tracks.first { $0.kind == "acts" }?.items.first?.duration, 3)
        try p.updateStoryMilestone(act, title: "Chapter One", page: 0, kind: .chapter)
        XCTAssertEqual(p.storyMilestones.first { $0.id == act }?.kind, .chapter)
        try p.updateBoardBeat(ids[0]) { $0.timelineDuration = 4 }
        try p.setTimelineMinutesPerPage(2)
        let timing = try XCTUnwrap(try StoryTimeline(project: p, timeBase: .time).tracks.first { $0.kind == "beats" })
        XCTAssertEqual(timing.items[0].duration, 4)
        XCTAssertEqual(timing.items[1].duration, 2.0 / 55, accuracy: 0.0001)
        let before = p
        XCTAssertThrowsError(try p.setTimelineMinutesPerPage(.infinity))
        XCTAssertEqual(p, before)
        XCTAssertEqual(try Project(data: p.encoded()), p)
        var full = TimelineDisplayPreferences(); full.lines = 3
        let compact = TimelineDisplayPreferences(compact: true)
        XCTAssertTrue(compact.hidden.contains("characters")); XCTAssertFalse(full.hidden.contains("characters"))
        XCTAssertEqual(try JSONDecoder().decode(TimelineDisplayPreferences.self, from: JSONEncoder().encode(full)), full)
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
