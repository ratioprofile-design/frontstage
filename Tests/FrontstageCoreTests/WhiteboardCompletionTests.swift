import Foundation
import XCTest
@testable import FrontstageCore

final class WhiteboardCompletionTests: XCTestCase {
    func testGroupBoundaryMoveIsRigidAndUngroupPreservesTextLinksAndPositions() throws {
        var project = Project(); let a = try project.addBoardBeat(position: .init(x: 40, y: 50)), b = try project.addBoardBeat(position: .init(x: 280, y: 90))
        try project.updateBoardBeat(a) { $0.html = "<p>First</p>" }
        try project.updateBoardBeat(b) { $0.html = "<p>Second</p>" }
        try project.connectBoardBeats(cause: a, effect: b)
        try project.groupBoardBlocks(Set(try project.whiteboard().blocks.map(\.id)), name: "Act I")
        let before = try project.whiteboard(), group = before.blocks.last!.id
        try project.moveBoardBlocks([group], delta: .init(x: -1000, y: -1000), snap: false)
        let moved = try project.whiteboard(), first = moved.blocks[0], second = moved.blocks[1]
        XCTAssertEqual(second.position.x - first.position.x, 240)
        XCTAssertEqual(second.position.y - first.position.y, 40)
        let scenes = project.scenes, positions = moved.blocks.prefix(2).map(\.position)
        try project.ungroupBoardBlocks([group])
        let ungrouped = try project.whiteboard()
        XCTAssertEqual(ungrouped.blocks.count, 2); XCTAssertTrue(ungrouped.blocks.allSatisfy { $0.parentID == nil })
        XCTAssertEqual(ungrouped.blocks.map(\.position), positions)
        XCTAssertEqual(ungrouped.dependencies, moved.dependencies); XCTAssertEqual(project.scenes, scenes)
        XCTAssertEqual(try Project(data: project.encoded()), project)
    }
    func testDeleteAndUngroupRejectLockedDescendantsAndLockedLastSnippet() throws {
        var project = Project(); let a = try project.addBoardBeat(), b = try project.addBoardBeat()
        try project.groupBoardBlocks(Set(try project.whiteboard().blocks.map(\.id)), name: "Group")
        let group = try project.whiteboard().blocks.last!.id
        try project.editWhiteboard { $0.blocks[0].locked = true }
        let locked = project
        XCTAssertThrowsError(try project.ungroupBoardBlocks([group])); XCTAssertEqual(project, locked)
        XCTAssertThrowsError(try project.removeBoardBlocks([group])); XCTAssertEqual(project, locked)
        try project.editWhiteboard { $0.blocks[0].locked = false }
        let sceneID = try project.whiteboard().beats.first { $0.id == a }!.sceneID
        try project.setSceneTextLocked(sceneID, locked: true)
        let scriptLocked = project
        XCTAssertThrowsError(try project.removeBoardBeats([a])); XCTAssertEqual(project, scriptLocked)
        try project.setSceneTextLocked(sceneID, locked: false)
        try project.connectBoardBeats(cause: a, effect: b)
        try project.removeBoardBlocks([group])
        let empty = try project.whiteboard()
        XCTAssertTrue(empty.blocks.isEmpty); XCTAssertTrue(empty.beats.isEmpty); XCTAssertTrue(empty.dependencies.isEmpty)
        XCTAssertEqual(project.scenes.count, 2); XCTAssertTrue(project.scenes.allSatisfy(\.isDisabled))
    }
    func testNestedGroupingAndUngroupingRetainTheOuterParent() throws {
        var project = Project()
        for _ in 0..<3 { _ = try project.addBoardBeat() }
        let children = try project.whiteboard().blocks.map(\.id)
        try project.groupBoardBlocks(Set(children), name: "Outer")
        let outer = try project.whiteboard().blocks.last!.id
        try project.groupBoardBlocks(Set(children.prefix(2)), name: "Inner")
        let inner = try project.whiteboard().blocks.last!.id
        XCTAssertEqual(try project.whiteboard().blocks.last?.parentID, outer)
        try project.ungroupBoardBlocks([inner])
        XCTAssertTrue(try project.whiteboard().blocks.filter { children.contains($0.id) }.allSatisfy { $0.parentID == outer })
        let before = project
        XCTAssertThrowsError(try project.groupBoardBlocks([outer, children[0]], name: "Invalid")); XCTAssertEqual(project, before)
    }
    func testCompactionKeepsConvergingCausesReferencesInactiveBeatsAndLocksConsistent() throws {
        var project = Project(); let a = try project.addBoardBeat(), b = try project.addBoardBeat(), c = try project.addBoardBeat()
        try project.updateBoardBeat(a) { $0.start = 10; $0.duration = 2 }
        try project.updateBoardBeat(b) { $0.start = 15; $0.duration = 4; $0.locked = true }
        try project.updateBoardBeat(c) { $0.start = 50 }
        try project.connectBoardBeats(cause: a, effect: c); try project.connectBoardBeats(cause: b, effect: c)
        try project.connectBoardBeats(cause: c, effect: a, reference: true)
        let positions = try project.whiteboard().blocks.map(\.position), scenes = project.scenes
        try project.editWhiteboard { try $0.compactCauses() }
        let board = try project.whiteboard(), starts = Dictionary(uniqueKeysWithValues: board.beats.map { ($0.id, $0.start) })
        XCTAssertEqual(starts[a], 0); XCTAssertEqual(starts[b], 15); XCTAssertEqual(starts[c], 19)
        XCTAssertEqual(board.blocks.map(\.position), positions); XCTAssertEqual(project.scenes, scenes)
        try project.updateBoardBeat(c) { $0.start = 1; $0.locked = true }
        let blocked = project
        XCTAssertThrowsError(try project.editWhiteboard { try $0.compactCauses() }); XCTAssertEqual(project, blocked)
        try project.updateBoardBeat(b) { $0.omitted = true }
        try project.updateBoardBeat(c) { $0.locked = false }
        try project.editWhiteboard { try $0.compactCauses() }
        XCTAssertEqual(try project.whiteboard().beats.first { $0.id == c }?.start, 2)
    }
    func testMarkersPreserveUnknownFieldsAndRejectInvalidEditsAtomically() throws {
        var project = Project(); let marker = try project.addStoryMilestone(title: "Act II", page: 8)
        var records = project.state["sectionBreaks"]!.array!, fields = records[0].object!
        fields["future"] = .bool(true); records[0] = .object(fields); project.state["sectionBreaks"] = .array(records)
        try project.updateStoryMilestone(marker, title: "Act II: A choice", page: 9)
        XCTAssertEqual(project.storyMilestones[0].x, 1080)
        XCTAssertEqual(project.state["sectionBreaks"]?.array?[0].object?["future"], .bool(true))
        let before = project
        XCTAssertThrowsError(try project.updateStoryMilestone(marker, title: "Bad", page: .nan)); XCTAssertEqual(project, before)
        XCTAssertEqual(project.storySequencer().milestones, project.storyMilestones)
        project.removeStoryMilestone(marker); XCTAssertTrue(project.storyMilestones.isEmpty)
    }
    func testTenThousandBeatCausalCompactionRetainsAnInheritedLockedStart() throws {
        var board = Whiteboard()
        board.blocks = (0..<10000).map { BoardBlock(id: "block-\($0)", name: "Block", layerID: "main") }
        board.beats = (0..<10000).map { BoardBeat(id: "beat-\($0)", sceneID: Decimal($0 + 1), blockID: "block-\($0)", title: "Beat", order: Double($0), start: 100 + Double($0) * 2) }
        board.dependencies = (1..<10000).map { BoardDependency(id: "edge-\($0)", cause: "beat-\($0 - 1)", effect: "beat-\($0)") }
        var parent = BoardBlock(id: "parent", name: "Locked parent", layerID: "main"); parent.locked = true
        board.blocks[5000].parentID = parent.id; board.blocks.append(parent)
        XCTAssertEqual(board.lockedBlockIDs, [parent.id, "block-5000"])
        try board.compactCauses()
        XCTAssertEqual(board.beats[0].start, 0); XCTAssertEqual(board.beats[5000].start, 10100)
        XCTAssertEqual(board.beats[9999].start, 10100 + 4999 * 1.5)
    }
}
