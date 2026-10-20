import Foundation
import XCTest
@testable import FrontstageCore

final class WhiteboardTests: XCTestCase {
    func testLegacyProjectionIsReadOnlyAndKeepsUntouchedUnicodeHTML() throws {
        var project = Project()
        let a = project.addScene(), b = project.addScene()
        try project.updateScene(id: a, html: "<div>தமிழ் <b>நூல்</b></div>")
        try project.connectScenes(from: a, to: b)
        let before = try project.encoded(), board = try project.whiteboard()
        XCTAssertEqual(board.beats.count, 2); XCTAssertEqual(board.dependencies.count, 1)
        XCTAssertEqual(board.beats[0].html, "<div>தமிழ் <b>நூல்</b></div>")
        XCTAssertEqual(try project.encoded(), before)
    }

    func testNewBeatsHaveIndependentIDsAndShareSceneWhenAddedInsideBlock() throws {
        var project = Project()
        let a = try project.addBoardBeat(title: "A")
        let first = try XCTUnwrap(project.whiteboard().beats.first)
        let b = try project.addBoardBeat(blockID: first.blockID, title: "B")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(project.scenes.count, 1)
        XCTAssertEqual(try project.whiteboard().beats.map(\.sceneID), [first.sceneID, first.sceneID])
        try project.updateBoardBeat(a) { $0.html = "<div>First</div>" }
        try project.updateBoardBeat(b) { $0.html = "<div>Second</div>" }
        XCTAssertEqual(project.scenes[0].html, "<div>First</div><div>Second</div>")
        XCTAssertEqual(try Project(data: project.encoded()).whiteboard(), try project.whiteboard())
    }

    func testSplitRewiresOutgoingCauseAndRetainsTextExactlyOnce() throws {
        var project = Project()
        let a = try project.addBoardBeat(title: "A"), b = try project.addBoardBeat(title: "B")
        try project.updateBoardBeat(a) { $0.html = "<div>one</div><div>two</div>" }
        try project.connectBoardBeats(cause: a, effect: b)
        let next = try project.splitBoardBeat(a, firstHTML: "<div>one</div>", secondHTML: "<div>two</div>")
        let board = try project.whiteboard()
        XCTAssertEqual(board.beats.count, 3)
        XCTAssertTrue(board.dependencies.contains { $0.cause == next && $0.effect == b })
        XCTAssertTrue(board.dependencies.contains { $0.cause == a && $0.effect == next })
        XCTAssertEqual(project.scenes[0].html, "<div>one</div><div>two</div>")
        XCTAssertEqual(board.beats.filter { $0.sceneID == project.scenes[0].id }.count, 2)
    }

    func testCauseRequirementAndUnusedOmittedCausesAreDiagnosed() throws {
        var project = Project()
        let a = try project.addBoardBeat(title: "Cause"), b = try project.addBoardBeat(title: "Effect")
        try project.updateBoardBeat(b) { $0.mustBeCaused = true }
        XCTAssertTrue(try project.whiteboard().issues.contains { $0.id == "missing-\(b)" })
        try project.connectBoardBeats(cause: a, effect: b)
        XCTAssertFalse(try project.whiteboard().issues.contains { $0.id == "missing-\(b)" })
        try project.updateBoardBeat(a) { $0.omitted = true }
        XCTAssertTrue(try project.whiteboard().issues.contains { $0.id == "missing-\(b)" })
    }

    func testCausalRippleConvergesWithoutMovingTheFreeBoardPositions() throws {
        var project = Project()
        let a = try project.addBoardBeat(), b = try project.addBoardBeat(), c = try project.addBoardBeat()
        try project.connectBoardBeats(cause: a, effect: b)
        try project.connectBoardBeats(cause: a, effect: c)
        try project.connectBoardBeats(cause: b, effect: c)
        let oldPositions = try project.whiteboard().blocks.map(\.position)
        try project.editWhiteboard { board in board.beats[0].start = 10; try board.resolveCauses() }
        let board = try project.whiteboard()
        XCTAssertEqual(board.beats.map(\.start), [10, 11.5, 13])
        XCTAssertEqual(board.blocks.map(\.position), oldPositions)
        XCTAssertTrue(board.issues.isEmpty)
    }

    func testCausalCycleAndLockedBlockersRollBackAtomically() throws {
        var project = Project()
        let a = try project.addBoardBeat(), b = try project.addBoardBeat()
        try project.connectBoardBeats(cause: a, effect: b)
        let before = project
        XCTAssertThrowsError(try project.connectBoardBeats(cause: b, effect: a))
        XCTAssertEqual(project, before)
        try project.updateBoardBeat(b) { $0.locked = true }
        let locked = project
        XCTAssertThrowsError(try project.editWhiteboard { board in board.beats[0].start = 10; try board.resolveCauses() })
        XCTAssertEqual(project, locked)
    }

    func testGroupMoveIsRigidAndNestedCycleIsRejected() throws {
        var project = Project()
        _ = try project.addBoardBeat(position: .init(x: 100, y: 100))
        _ = try project.addBoardBeat(position: .init(x: 400, y: 150))
        let ids = Set(try project.whiteboard().blocks.map(\.id))
        try project.groupBoardBlocks(ids, name: "Sequence")
        let old = try project.whiteboard(), parent = try XCTUnwrap(old.blocks.first { !ids.contains($0.id) })
        try project.moveBoardBlocks([parent.id], delta: .init(x: 50, y: 30), snap: false)
        let moved = try project.whiteboard()
        for (a, b) in zip(old.blocks, moved.blocks) { XCTAssertEqual(b.position.x - a.position.x, 50); XCTAssertEqual(b.position.y - a.position.y, 30) }
        let before = project
        XCTAssertThrowsError(try project.editWhiteboard { board in board.blocks[board.blocks.count - 1].parentID = board.blocks[0].id })
        XCTAssertEqual(project, before)
    }

    func testReorderAcrossBlocksPreservesSnippetOwnershipAndScriptContent() throws {
        var project = Project()
        let a = try project.addBoardBeat(title: "A")
        let block = try project.whiteboard().beats[0].blockID
        let b = try project.addBoardBeat(blockID: block, title: "B")
        let c = try project.addBoardBeat(title: "C"), destination = try project.whiteboard().beats.first { $0.id == c }!.blockID
        try project.updateBoardBeat(a) { $0.html = "<p>A</p>" }; try project.updateBoardBeat(b) { $0.html = "<p>B</p>" }
        try project.moveBoardBeat(b, toBlock: destination, before: a)
        XCTAssertEqual(project.scenes[0].html, "<p>B</p><p>A</p>")
        XCTAssertEqual(try project.whiteboard().beats.first { $0.id == b }?.blockID, destination)
    }

    func testOmissionUnusedAndDeleteKeepOriginalSceneMetadata() throws {
        var project = Project()
        let a = try project.addBoardBeat()
        try project.updateBoardBeat(a) { $0.html = "<p>Keep source</p>" }
        let sceneID = project.scenes[0].id, block = try project.whiteboard().beats[0].blockID
        try project.editBeat(sceneID) { $0["unknown"] = .string("keep") }
        try project.moveBoardBlocks([block], delta: .init(), layerID: "unused")
        XCTAssertEqual(project.scenes[0].html, ""); XCTAssertTrue(project.scenes[0].isDisabled)
        XCTAssertEqual(try project.whiteboard().beats[0].html, "<p>Keep source</p>")
        try project.moveBoardBlocks([block], delta: .init(), layerID: "main")
        XCTAssertEqual(project.scenes[0].html, "<p>Keep source</p>")
        try project.removeBoardBeats([a])
        XCTAssertEqual(project.scenes[0].html, ""); XCTAssertTrue(project.scenes[0].isDisabled)
        XCTAssertEqual(project.preservedState["beats"]?.array?.first?.object?["unknown"], .string("keep"))
    }

    func testUnknownWhiteboardFieldsRoundTripAndFutureVersionCannotBeOverwritten() throws {
        var project = Project()
        let a = try project.addBoardBeat()
        var stored = project.state["frontstageWhiteboard"]!.object!, beats = stored["beats"]!.array!, first = beats[0].object!
        first["future"] = .string("keep"); beats[0] = .object(first); stored["beats"] = .array(beats); stored["unknown"] = .bool(true)
        project.state["frontstageWhiteboard"] = .object(stored)
        try project.updateBoardBeat(a) { $0.title = "Changed" }
        XCTAssertEqual(project.preservedState["frontstageWhiteboard"]?.object?["beats"]?.array?[0].object?["future"], .string("keep"))
        XCTAssertEqual(project.preservedState["frontstageWhiteboard"]?.object?["unknown"], .bool(true))
        stored["version"] = .number(2); project.state["frontstageWhiteboard"] = .object(stored)
        let before = project
        XCTAssertThrowsError(try project.updateBoardBeat(a) { $0.title = "Lost" })
        XCTAssertEqual(project, before)
    }

    func testLayoutHitTestingMarqueeAndCollapsedGroupUseSameGeometry() throws {
        var project = Project()
        let id = try project.addBoardBeat(position: .init(x: 100, y: 60))
        let board = try project.whiteboard(), layout = WhiteboardLayout(board), rect = try XCTUnwrap(layout.beatRects[id])
        XCTAssertEqual(layout.hitBeat(rect.center), id)
        XCTAssertEqual(layout.beats(in: rect), [id])
        XCTAssertTrue(layout.beats(in: BoardRect(x: 10000, y: 10000, width: 100, height: 100)).isEmpty)
        try project.editWhiteboard { $0.blocks[0].collapsed = true }
        XCTAssertNil(WhiteboardLayout(try project.whiteboard()).beatRects[id])
    }

    func testInvalidGeometryAndSplitRollback() throws {
        var project = Project(); let id = try project.addBoardBeat()
        let before = project
        XCTAssertThrowsError(try project.editWhiteboard { $0.blocks[0].position.x = .nan })
        XCTAssertThrowsError(try project.editWhiteboard { $0.beats[0].duration = -1 })
        XCTAssertEqual(project, before)
        try project.updateBoardBeat(id) { $0.locked = true }
        let locked = project
        XCTAssertThrowsError(try project.splitBoardBeat(id, firstHTML: "A", secondHTML: "B"))
        XCTAssertEqual(project, locked)
    }
}
