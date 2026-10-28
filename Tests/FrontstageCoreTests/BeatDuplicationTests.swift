import XCTest
@testable import FrontstageCore

final class BeatDuplicationTests: XCTestCase {
    func testIndependentSceneCopyPreservesSourceAndUnknownData() throws {
        var project = Project(oneBeatPerScene: true)
        let source = try project.addBoardBeat(title: "கமல் enters")
        try project.updateBoardBeat(source) { $0.html = "<p>Original screenplay.</p>"; $0.synopsis = "Summary" }
        var raw = project.state["frontstageWhiteboard"]!.object!
        var beats = raw["beats"]!.array!
        var original = beats[0].object!
        original["importedExtension"] = .string("keep")
        beats[0] = .object(original); raw["beats"] = .array(beats)
        project.state["frontstageWhiteboard"] = .object(raw)
        let before = try project.whiteboard().beats.first { $0.id == source }!
        let copyID = try project.duplicateBoardBeat(source)
        let board = try project.whiteboard(), copy = try XCTUnwrap(board.beats.first { $0.id == copyID })
        XCTAssertNotEqual(copy.sceneID, before.sceneID)
        XCTAssertEqual(copy.html, before.html)
        XCTAssertEqual(copy.synopsis, before.synopsis)
        XCTAssertEqual(copy.title, before.title + " copy")
        XCTAssertEqual(board.beats.first { $0.id == source }, before)
        XCTAssertEqual(project.state["frontstageWhiteboard"]?.object?["beats"]?.array?.first { $0.object?["id"]?.string == copyID }?.object?["importedExtension"], .string("keep"))
        try project.updateBoardBeat(copyID) { $0.html = "<p>Changed copy.</p>" }
        XCTAssertEqual(try project.whiteboard().beats.first { $0.id == source }?.html, before.html)
        XCTAssertEqual(try Project(data: project.encoded()), project)
    }

    func testLockedSourceRejectsAtomicallyAndGroupIsRetained() throws {
        var project = Project()
        let a = try project.addBoardBeat(title: "A"), b = try project.addBoardBeat(title: "B")
        try project.groupBoardBeats([a, b])
        let copy = try project.duplicateBoardBeat(a), board = try project.whiteboard()
        XCTAssertEqual(board.beats.first { $0.id == a }?.blockID, board.beats.first { $0.id == copy }?.blockID)
        try project.updateBoardBeat(a) { $0.locked = true }
        let before = project
        XCTAssertThrowsError(try project.duplicateBoardBeat(a))
        XCTAssertEqual(project, before)
    }

    func testParentheticalPairsAndCaretAwareSuggestions() {
        XCTAssertEqual(ScreenplayParenthetical.wrapped(""), "()")
        XCTAssertEqual(ScreenplayParenthetical.wrapped("(quietly"), "(quietly)")
        XCTAssertEqual(ScreenplayParenthetical.wrapped("quietly)"), "(quietly)")
        XCTAssertTrue(ScreenplayParenthetical.isEmpty("()"))
        XCTAssertFalse(ScreenplayParenthetical.isEmpty("(தமிழ்)"))
        XCTAssertTrue(ScreenplayCompletionRules.parenthetical("(over)", caret: 5).values.contains("(over the phone)"))
    }
}
