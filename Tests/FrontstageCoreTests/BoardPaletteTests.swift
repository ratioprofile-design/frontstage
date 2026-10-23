import XCTest
@testable import FrontstageCore

final class BoardPaletteTests: XCTestCase {
    func testExistingGroupNestsAcrossLayersAndMovesWithBlock() throws {
        var project = Project()
        let flat = try project.createBoardItem(.lane, layerID: "main", position: .init())
        let group = try project.createBoardItem(.group, layerID: flat, position: .init(x: 50, y: 50))
        let beat = try project.createBoardItem(.beat, layerID: flat, position: .init(x: 70, y: 80), parentID: group)
        let lane = try project.createBoardItem(.lane, layerID: flat, position: .init())
        try project.setLayerUsesBlocks(lane, enabled: true)
        let block = try project.createBoardItem(.block, layerID: lane, position: .init(x: 300, y: 60))
        try project.nestBoardGroups([group], inBlock: block, delta: .init(x: 300, y: 60))
        var board = try project.whiteboard()
        XCTAssertEqual(board.blocks.first { $0.id == group }?.parentID, block)
        XCTAssertEqual(board.blocks.first { $0.id == group }?.layerID, lane)
        XCTAssertEqual(board.beats.first { $0.id == beat }?.blockID, group)
        let x = try XCTUnwrap(board.blocks.first { $0.id == group }?.position.x)
        try project.moveBoardBlocks([block], delta: .init(x: 40, y: 0), ripple: false)
        board = try project.whiteboard()
        XCTAssertEqual(board.blocks.first { $0.id == group }?.position.x, x + 40)
        XCTAssertEqual(try Project(data: project.encoded()), project)
        try project.editWhiteboard { board in board.blocks[board.blocks.firstIndex { $0.id == block }!].locked = true }
        let locked = project
        XCTAssertThrowsError(try project.nestBoardGroups([group], inBlock: block, delta: .init()))
        XCTAssertEqual(project, locked)
    }

    func testBlockLayerRejectsLooseCreationAndMovesAtomically() throws {
        var project = Project()
        let lane = try project.createBoardItem(.lane, layerID: "main", position: .init())
        let original = project
        XCTAssertThrowsError(try project.createBoardItem(.block, layerID: lane, position: .init(x: 50, y: 50)))
        XCTAssertEqual(project, original)
        try project.setLayerUsesBlocks(lane, enabled: true)
        let block = try project.createBoardItem(.block, layerID: lane, position: .init(x: 50, y: 50))
        XCTAssertTrue(try project.whiteboard().beats.isEmpty)
        let before = project
        XCTAssertThrowsError(try project.createBoardItem(.beat, layerID: lane, position: .init(x: 500, y: 50)))
        XCTAssertThrowsError(try project.createBoardItem(.group, layerID: lane, position: .init(x: 500, y: 50)))
        XCTAssertEqual(project, before)
        let group = try project.createBoardItem(.group, layerID: lane, position: .init(x: 80, y: 80), parentID: block)
        let beat = try project.createBoardItem(.beat, layerID: lane, position: .init(x: 100, y: 110), parentID: group)
        let populated = project
        XCTAssertThrowsError(try project.moveBoardBeatsToLayer([beat], layerID: lane, position: .init(x: 800, y: 50)))
        XCTAssertEqual(project, populated)
        XCTAssertThrowsError(try project.setLayerUsesBlocks(lane, enabled: false))
        XCTAssertEqual(try Project(data: project.encoded()), project)
    }
    func testFlatLayerAllowsLooseBeatsAndGroupsAndPolicyChangesPreserveContent() throws {
        var project = Project()
        let lane = try project.createBoardItem(.lane, layerID: "main", position: .init())
        let beat = try project.createBoardItem(.beat, layerID: lane, position: .init(x: 100, y: 70))
        let before = project
        XCTAssertThrowsError(try project.setLayerUsesBlocks(lane, enabled: true))
        XCTAssertEqual(project, before)
        let board = try project.whiteboard()
        XCTAssertTrue(board.blocks.first { $0.id == board.beats.first { $0.id == beat }?.blockID }?.standalone == true)
    }
}
