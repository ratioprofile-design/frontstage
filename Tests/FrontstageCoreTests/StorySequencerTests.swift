import Foundation
import XCTest
@testable import FrontstageCore

final class StorySequencerTests: XCTestCase {
    private func project(_ positions: [(Double, Int)]) throws -> Project {
        var project = Project()
        for (x, lane) in positions {
            let id = project.addScene()
            try project.editBeat(id) {
                $0["x"] = .number(Decimal(x)); $0["w"] = .number(120)
                $0["trackIndex"] = .number(Decimal(lane)); $0["future"] = .string("keep")
            }
        }
        return project
    }

    private func positions(_ project: Project) -> [Double] { project.storySequencer().beats.map(\.x) }

    func testRipplePushesLaneNeighborsAndTheirCrossLaneEffects() throws {
        var project = try project([(0, 0), (144, 0), (288, 1), (432, 1), (576, 2)])
        try project.connectScenes(from: 2, to: 3)
        try project.connectScenes(from: 4, to: 5)
        try project.moveStoryBeats([1], by: 100, snap: false)
        XCTAssertEqual(positions(project), [100, 244, 388, 532, 676])
        XCTAssertTrue(project.storySequencer().issues.isEmpty)
        XCTAssertEqual(project.scenes.map(\.id), [1, 2, 3, 4, 5])
    }

    func testConvergingCausesUseLatestParentAndPropagateAgainToDescendants() throws {
        var project = try project([(0, 0), (144, 1), (288, 2), (432, 3)])
        try project.connectScenes(from: 1, to: 2)
        try project.connectScenes(from: 1, to: 3)
        try project.connectScenes(from: 2, to: 3)
        try project.connectScenes(from: 3, to: 4)
        try project.moveStoryBeats([1], by: 350, snap: false)
        XCTAssertEqual(positions(project), [350, 494, 638, 782])
        XCTAssertTrue(project.storySequencer().issues.isEmpty)
    }

    func testDraggingLeftCannotPassThePrecedingLaneBeatWithRippleOn() throws {
        var project = try project([(0, 0), (500, 0), (700, 0)])
        try project.moveStoryBeats([2], by: -490, snap: false)
        XCTAssertEqual(positions(project), [0, 144, 700])
    }

    func testRippleOffLeavesOtherBeatsAndEditorialOrderUntouchedAndReportsViolations() throws {
        var project = try project([(0, 0), (144, 0)])
        try project.connectScenes(from: 1, to: 2)
        try project.moveStoryBeats([1], by: 200, ripple: false, snap: false)
        XCTAssertEqual(positions(project), [200, 144])
        XCTAssertEqual(project.scenes.map(\.id), [1, 2])
        XCTAssertFalse(project.storySequencer().issues.isEmpty)
        try project.applyStoryOrder()
        XCTAssertEqual(project.scenes.map(\.id), [2, 1])
    }

    func testLockedDownstreamBeatBlocksWholeGestureWithoutPartialWrites() throws {
        var project = try project([(0, 0), (144, 0), (288, 1)])
        try project.connectScenes(from: 2, to: 3)
        try project.setStoryBeatLocked(3, locked: true)
        let before = project
        XCTAssertThrowsError(try project.moveStoryBeats([1], by: 100, snap: false))
        XCTAssertEqual(project, before)
        try project.setStoryBeatLocked(3, locked: false)
        try project.updateStoryLane(1, locked: true)
        let lockedLane = project
        XCTAssertThrowsError(try project.moveStoryBeats([1], by: 100, snap: false))
        XCTAssertEqual(project, lockedLane)
    }

    func testImportedCyclesAndOpposingLaneOrderFailAtomicallyAndCanBeRepaired() throws {
        var project = try project([(0, 0), (144, 0)])
        try project.connectScenes(from: 2, to: 1)
        let before = project
        XCTAssertThrowsError(try project.resolveStory())
        XCTAssertEqual(project, before)
        try project.moveStoryBeats([1], by: 300, ripple: false, snap: false)
        try project.resolveStory()
        XCTAssertTrue(project.storySequencer().issues.isEmpty)
        project.state["connections"] = .array([.object(["from": .number(1), "to": .number(2)]), .object(["from": .number(2), "to": .number(1)])])
        let cyclic = project
        XCTAssertThrowsError(try project.moveStoryBeats([1], by: 10, snap: false))
        XCTAssertEqual(project, cyclic)
    }

    func testResizeUsesDurationAndPushesCrossLaneDependencies() throws {
        var project = try project([(0, 0), (144, 1), (288, 1)])
        try project.connectScenes(from: 1, to: 2)
        try project.resizeStoryBeat(1, pages: 3)
        XCTAssertEqual(positions(project), [0, 384, 528])
        XCTAssertEqual(project.storySequencer().beats.first?.pages, 3)
        let before = project
        XCTAssertThrowsError(try project.resizeStoryBeat(1, pages: .nan))
        XCTAssertThrowsError(try project.resizeStoryBeat(1, pages: 0))
        XCTAssertEqual(project, before)
    }

    func testSnapUsesGridNeighborEdgesAndMilestonesButExcludesDraggedSelection() throws {
        var project = try project([(14, 0), (200, 0)])
        _ = try project.addStoryMilestone(title: "Turning Point", page: 4.25)
        let model = project.storySequencer()
        XCTAssertEqual(model.snappedX(17, lane: 0, excluding: [1], threshold: 8), 17)
        XCTAssertEqual(model.snappedX(29, lane: 0, excluding: [1]), 30)
        XCTAssertEqual(model.snappedX(343, lane: 0, excluding: [1]), 344)
        XCTAssertEqual(model.snappedX(512, lane: 0, excluding: [1], threshold: 8), 510)
    }

    func testReferenceLinksDoNotPushOrIntroduceCausalLoops() throws {
        var project = try project([(0, 0), (144, 1)])
        try project.connectScenes(from: 1, to: 2)
        try project.connectScenes(from: 2, to: 1, kind: .reference)
        XCTAssertFalse(project.storyGraph.hasCycle)
        try project.moveStoryBeats([1], by: 100, snap: false)
        XCTAssertEqual(positions(project), [100, 244])
        XCTAssertTrue(project.storySequencer().issues.isEmpty)
    }

    func testGroupMultiMoveAndRoundTripPreserveTextAndUnknownFields() throws {
        var project = try project([(0, 0), (144, 0), (600, 1)])
        try project.updateScene(id: 1, html: "<div class=\"sc-action\">தமிழ்</div>")
        let id = try project.groupStoryBeats([1, 2], title: "The discovery")
        try project.moveStoryBeats([1, 2], by: 120, snap: false)
        XCTAssertEqual(positions(project), [120, 264, 600])
        let restored = try Project(data: project.encoded())
        XCTAssertEqual(restored.storySequencer().groups.first?.id, id)
        XCTAssertEqual(restored.storySequencer().beats.prefix(2).map(\.groupID), [id, id])
        XCTAssertEqual(restored.scenes.first?.html, "<div class=\"sc-action\">தமிழ்</div>")
        XCTAssertEqual(restored.preservedState["beats"]?.array?.first?.object?["future"], .string("keep"))
        try project.ungroupStoryBeats([1, 2])
        XCTAssertNil(project.storySequencer().beats.first?.groupID)
    }

    func testLaneTransferAndBoardOrderingPreserveOtherBoardSlotsAndFields() throws {
        var project = try project([(300, 0), (0, 0), (100, 0)])
        try project.setStoryBoard(2, boardID: 1)
        try project.moveStoryBeats([3], by: 0, toLane: 2, ripple: false, snap: false)
        XCTAssertEqual(project.storySequencer().beats.last?.lane, 2)
        try project.applyStoryOrder()
        XCTAssertEqual(project.scenes.map(\.id), [3, 2, 1])
        XCTAssertEqual(project.storySequencer(boardID: 1).beats.first?.x, 0)
    }

    func testLaneMilestoneEditsPreserveImportedMetadataAndRejectUnsupportedContainers() throws {
        var project = try project([(0, 0)])
        project.state["causalityLanes"] = .array([.object(["id": .string("original"), "label": .string("Plot"), "future": .bool(true)])])
        try project.updateStoryLane(0, label: "Mystery", collapsed: true)
        XCTAssertEqual(project.preservedState["causalityLanes"]?.array?.first?.object?["future"], .bool(true))
        XCTAssertEqual(project.storySequencer().lanes.first?.id, "original")
        let nextLane = try project.addStoryLane(label: "Antagonist")
        XCTAssertEqual(project.storySequencer().lanes[nextLane].label, "Antagonist")
        let milestone = try project.addStoryMilestone(title: "Reversal", page: 10)
        XCTAssertEqual(project.storySequencer().milestones.first?.x, 1200)
        project.removeStoryMilestone(milestone)
        XCTAssertTrue(project.storySequencer().milestones.isEmpty)
        project.state["sectionBreaks"] = .object(["future": .bool(true)])
        let before = project
        XCTAssertThrowsError(try project.addStoryMilestone(title: "Invalid", page: 5))
        XCTAssertEqual(project, before)
    }

    func testLargeRippleIsIterativeAndPreservesEveryDependency() throws {
        var project = Project()
        project.state["beats"] = .array((0..<1000).map { index in .object([
            "id": .number(Decimal(index + 1)), "title": .string("Beat \(index)"), "content": .string(""),
            "x": .number(Decimal(index * 144)), "w": .number(120), "trackIndex": .number(Decimal(index % 5))]) })
        project.state["connections"] = .array((1..<1000).map { .object(["from": .number(Decimal($0)), "to": .number(Decimal($0 + 1))]) })
        try project.moveStoryBeats([1], by: 100, snap: false)
        XCTAssertEqual(project.storySequencer().beats.last?.x, 999 * 144 + 100)
        XCTAssertTrue(project.storySequencer().issues.isEmpty)
        XCTAssertFalse(project.storyGraph.hasCycle)
    }

    func testInvalidMovementAndMissingSelectionFailWithoutMutation() throws {
        var project = try project([(0, 0)])
        let before = project
        XCTAssertThrowsError(try project.moveStoryBeats([], by: 10))
        XCTAssertThrowsError(try project.moveStoryBeats([99], by: 10))
        XCTAssertThrowsError(try project.moveStoryBeats([1], by: .infinity))
        XCTAssertThrowsError(try project.moveStoryBeats([1], by: 1_000_000))
        XCTAssertThrowsError(try project.moveStoryBeats([1], by: 10, toLane: 128))
        XCTAssertEqual(project, before)
    }

    func testCompactingRespectsLockedAnchorAndRejectsOverlappingLockedBeats() throws {
        var project = try project([(100, 0), (600, 0), (1000, 0)])
        try project.setStoryBeatLocked(2, locked: true)
        try project.resolveStory(compactLane: 0)
        XCTAssertEqual(positions(project), [0, 600, 744])
        try project.moveStoryBeats([1], by: 520, ripple: false, snap: false)
        let before = project
        XCTAssertThrowsError(try project.resolveStory())
        XCTAssertEqual(project, before)
    }

    func testLanesAreSharedAcrossBoardsIncludingImportedHighLaneIndexes() throws {
        var project = try project([(0, 0), (144, 8)])
        try project.setStoryBoard(2, boardID: 2)
        XCTAssertEqual(project.storySequencer().lanes.count, 9)
        XCTAssertEqual(project.storySequencer(boardID: 2).lanes.count, 9)
        try project.updateStoryLane(8, label: "Secondary board story")
        XCTAssertEqual(project.storySequencer(boardID: 2).lanes[8].label, "Secondary board story")
    }

    func testGroupBoundsAndLinkReasonEditsKeepImportedUnknownFields() throws {
        var project = try project([(0, 0), (144, 0)])
        let id = try project.groupStoryBeats([1, 2], title: "Original")
        var groups = project.state["causalityGroups"]!.array!
        var group = groups[0].object!; group["future"] = .bool(true); groups[0] = .object(group)
        project.state["causalityGroups"] = .array(groups)
        try project.moveStoryBeats([1, 2], by: 120, snap: false)
        try project.renameStoryGroup(id, title: "The reveal")
        let saved = project.preservedState["causalityGroups"]!.array![0].object!
        XCTAssertEqual(saved["startUnit"], .number(1))
        XCTAssertEqual(saved["durationUnits"], .number(Decimal(2.2)))
        XCTAssertEqual(saved["future"], .bool(true))
        XCTAssertEqual(saved["title"], .string("The reveal"))
        try project.connectScenes(from: 1, to: 2)
        var links = project.state["connections"]!.array!
        var link = links[0].object!; link["future"] = .string("preserved"); links[0] = .object(link)
        project.state["connections"] = .array(links)
        try project.updateStoryLink(from: 1, to: 2, label: "She opens the letter")
        XCTAssertEqual(project.storyGraph.links[0].label, "She opens the letter")
        XCTAssertEqual(project.preservedState["connections"]!.array![0].object?["future"], .string("preserved"))
    }

    func testDeleteRemovesOnlySelectedBeatsAndTheirLinksAndCanBeUndone() throws {
        var project = try project([(0, 0), (144, 0), (288, 0)])
        try project.connectScenes(from: 1, to: 2)
        try project.connectScenes(from: 2, to: 3)
        try project.connectScenes(from: 1, to: 3)
        let before = project
        var history = ProjectHistory()
        history.record(before, label: "Delete Beat")
        try project.removeStoryBeats([2])
        XCTAssertEqual(project.scenes.map(\.id), [1, 3])
        XCTAssertEqual(project.storyGraph.links.count, 1)
        XCTAssertEqual(project.storyGraph.links.first?.to, 3)
        XCTAssertEqual(history.undo(current: project), before)
    }
}
