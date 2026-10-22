import XCTest
@testable import FrontstageCore

final class BeatHierarchyTests: XCTestCase {
    func testBeatGroupInsideBlockPreservesScriptAndDependencies() throws {
        var project = Project()
        let a = try project.addBoardBeat(title: "Go")
        let scene = try XCTUnwrap(project.whiteboard().beats.first?.sceneID)
        let b = try project.addBoardBeat(title: "A much longer decision that needs several lines to fit on the whiteboard", sceneID: scene)
        try project.updateBoardBeat(a) { $0.html = "<p>First.</p>" }
        try project.updateBoardBeat(b) { $0.html = "<p>Second.</p>" }
        try project.connectBoardBeats(cause: a, effect: b)
        try project.editWhiteboard { board in
            for i in board.blocks.indices { board.blocks[i].standalone = true }
        }
        let script = try project.orderedScript()
        try project.groupBoardBeats([a, b])
        let group = try XCTUnwrap(project.whiteboard().blocks.first { $0.containerKind == "beatGroup" })
        try project.groupBoardBlocks([group.id], name: "Act One")
        let board = try project.whiteboard()
        XCTAssertEqual(board.blocks.count, 2)
        XCTAssertNotNil(board.blocks.first { $0.id == group.id }?.parentID)
        XCTAssertTrue(board.beats.allSatisfy { $0.blockID == group.id })
        XCTAssertEqual(board.dependencies.first?.cause, a)
        XCTAssertEqual(try project.orderedScript(), script)
        XCTAssertEqual(try Project(data: project.encoded()), project)
        let layout = WhiteboardLayout(board)
        let short = try XCTUnwrap(layout.beatRects[a]), long = try XCTUnwrap(layout.beatRects[b])
        XCTAssertLessThan(short.width, long.width)
        XCTAssertLessThan(short.height, long.height)
        XCTAssertGreaterThanOrEqual(long.y, short.maxY + 4)
        XCTAssertEqual(layout.hitBeat(long.center), b)
        var ungrouped = project
        try ungrouped.ungroupBoardBlocks([group.id])
        XCTAssertEqual(try ungrouped.orderedScript(), script)
        XCTAssertEqual(try ungrouped.whiteboard().blocks.filter { $0.standalone == true }.count, 2)
        XCTAssertEqual(try ungrouped.whiteboard().dependencies, board.dependencies)
        let before = project
        try project.editWhiteboard { board in board.layers[0].locked = true }
        let locked = project
        XCTAssertThrowsError(try project.groupBoardBeats([a]))
        XCTAssertEqual(project, locked)
        XCTAssertNotEqual(project, before)
    }
}
