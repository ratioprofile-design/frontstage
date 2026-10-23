import XCTest
@testable import FrontstageCore

final class BoardPaletteTests: XCTestCase {
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
