import XCTest
@testable import FrontstageCore

final class ScriptFilterTests: XCTestCase {
    func testReaderIncludesUnusedAndOmittedWithoutChangingExport() throws {
        var project = Project()
        let a = try project.addBoardBeat(title: "Visible")
        let b = try project.addBoardBeat(title: "Unused")
        try project.updateBoardBeat(a) { $0.html = "<p class='sc-character'>KAMAL</p>"; $0.tags = ["A", "B"] }
        try project.updateBoardBeat(b) { $0.omitted = true }
        let board = try project.whiteboard()
        XCTAssertTrue(try project.orderedScript(includeInactive: true).flatMap(\.beatIDs).contains(b))
        XCTAssertFalse(try project.orderedScript().flatMap(\.beatIDs).contains(b))
        var filter = ScriptFilters()
        let first = try XCTUnwrap(board.beats.first { $0.id == a }), second = try XCTUnwrap(board.beats.first { $0.id == b })
        filter.facets["Tags"] = .init(); filter.facets["Tags"]?.values = ["A", "B"]; filter.facets["Tags"]?.all = true
        XCTAssertTrue(filter.matches(first, board: board, scenes: project.scenes)); XCTAssertFalse(filter.matches(second, board: board, scenes: project.scenes))
        filter = .init(); filter.facets["Characters"] = .init(); filter.facets["Characters"]?.values = ["kamal"]
        XCTAssertTrue(filter.matches(first, board: board, scenes: project.scenes))
        filter.facets["Characters"]?.hide = true
        XCTAssertFalse(filter.matches(first, board: board, scenes: project.scenes))
        filter = .init(); filter.hideDisabled = true
        XCTAssertFalse(filter.matches(second, board: board, scenes: project.scenes))
    }
}
