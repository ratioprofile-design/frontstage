import Foundation
import XCTest
@testable import FrontstageCore

final class StoryBoardTests: XCTestCase {
    func testConnectionsRejectCyclesDuplicatesSelfAndMissingScenesAtomically() throws {
        var project = Project()
        let a = project.addScene(), b = project.addScene(), c = project.addScene()
        try project.connectScenes(from: a, to: b, label: "Because")
        try project.connectScenes(from: b, to: c)
        let before = project
        XCTAssertThrowsError(try project.connectScenes(from: c, to: a))
        XCTAssertThrowsError(try project.connectScenes(from: a, to: a))
        XCTAssertThrowsError(try project.connectScenes(from: a, to: b))
        XCTAssertThrowsError(try project.connectScenes(from: 99, to: a))
        XCTAssertEqual(project, before)
        XCTAssertFalse(project.storyGraph.hasCycle)
        project.disconnectScenes(from: b, to: c)
        XCTAssertEqual(project.storyGraph.links.count, 1)
    }

    func testImportedCycleAndDanglingLinksAreDiagnosedWithoutDiscardingData() throws {
        var project = try Project(data: Data(#"{"beats":[{"id":1,"title":"A","content":""},{"id":2,"title":"B","content":""}],"connections":[{"from":1,"to":2,"future":"keep"},{"from":2,"to":1},{"from":2,"to":99}]}"#.utf8))
        XCTAssertTrue(project.storyGraph.hasCycle)
        XCTAssertEqual(project.storyGraph.danglingConnections, 1)
        let before = try project.encoded()
        _ = project.storyGraph
        XCTAssertEqual(try project.encoded(), before)
        project.disconnectScenes(from: 2, to: 1)
        XCTAssertFalse(project.storyGraph.hasCycle)
        XCTAssertEqual(project.preservedState["connections"]?.array?.first?.object?["future"], .string("keep"))
    }

    func testMovementAndReorderingRoundTripWithoutChangingIdentifiersOrLinks() throws {
        var project = Project()
        let a = project.addScene(), b = project.addScene()
        try project.connectScenes(from: a, to: b)
        let links = project.storyGraph.links
        try project.moveStoryNode(a, x: -120.5, y: 240)
        try project.moveSceneInScript(b, offset: -1)
        XCTAssertEqual(project.scenes.first?.id, b)
        XCTAssertEqual(project.storyGraph.links, links)
        let restored = try Project(data: project.encoded())
        XCTAssertEqual(restored.storyGraph.nodes.first { $0.id == a }?.x, -120.5)
        let before = project
        XCTAssertThrowsError(try project.moveStoryNode(a, x: .infinity, y: 0))
        XCTAssertEqual(project, before)
        try project.setSceneOmitted(b, omitted: true)
        XCTAssertTrue(project.scenes.first!.isDisabled)
    }

    func testCrossBoardLinksAreRejectedAndArrangeOnlyMovesSelectedBoard() throws {
        var project = try Project(data: Data(#"{"beats":[{"id":1,"title":"A","content":"","boardId":0,"x":-100},{"id":2,"title":"B","content":"","boardId":1,"x":900,"future":true}]}"#.utf8))
        XCTAssertThrowsError(try project.connectScenes(from: 1, to: 2))
        try project.arrangeStoryBoard(0)
        XCTAssertEqual(project.storyGraph.nodes.first?.x, 0)
        XCTAssertEqual(project.storyGraph.nodes.last?.x, 900)
        XCTAssertEqual(project.preservedState["beats"]?.array?.last?.object?["future"], .bool(true))
    }
}
