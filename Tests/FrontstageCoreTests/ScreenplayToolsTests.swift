import Foundation
import XCTest
@testable import FrontstageCore

final class ScreenplayToolsTests: XCTestCase {
    func testBaminiConvertsCompoundsAndKeepsExistingUnicode() {
        XCTAssertEqual(TamilTranscoder.baminiToUnicode("jkpo;"), "தமிழ்")
        XCTAssertEqual(TamilTranscoder.baminiToUnicode("tzf;fk;"), "வணக்கம்")
        XCTAssertEqual(TamilTranscoder.baminiToUnicode("ghh;j;J"), "பார்த்து")
        XCTAssertEqual(TamilTranscoder.baminiToUnicode("தமிழ் 123\n"), "தமிழ் 123\n")
    }
    func testTypographyAndParallelRowsSurviveProjectSaveAndRejectInvalidSettings() throws {
        var project = Project(); let id = project.addScene()
        var layout = ScriptLayoutSettings(); layout.fontName = "Tamil Sangam MN"; layout.fontSize = 13; layout.lineHeight = 16
        try project.setScriptLayout(layout)
        let rows = [ParallelScriptRow(left: "தமிழ்", right: "Translation"), ParallelScriptRow(left: "Action", right: "Notes")]
        try project.setParallelScript(sceneID: id, rows: rows)
        let restored = try Project(data: project.encoded())
        XCTAssertEqual(restored.scriptLayout, layout); XCTAssertEqual(restored.parallelScript(sceneID: id), rows)
        let before = project; layout.lineHeight = .nan
        XCTAssertThrowsError(try project.setScriptLayout(layout)); XCTAssertEqual(project, before)
    }
    func testSceneEditingCannotSilentlyOverwriteMultipleSnippets() throws {
        var project = Project()
        let id = try project.addBoardBeat(), block = try project.whiteboard().beats[0].blockID
        let scene = project.scenes[0].id
        try project.updateScene(id: scene, html: "<p>Synced</p>")
        XCTAssertEqual(try project.whiteboard().beats.first { $0.id == id }?.html, "<p>Synced</p>")
        _ = try project.addBoardBeat(blockID: block)
        let before = project
        XCTAssertThrowsError(try project.updateScene(id: scene, html: "Lost ranges"))
        XCTAssertEqual(project, before)
    }
    func testSceneTextLockPreventsSnippetChangesAndPersistsPageStarts() throws {
        var project = Project(); let beat = try project.addBoardBeat(), scene = project.scenes[0].id
        try project.updateBoardBeat(beat) { $0.html = "<p>Locked</p>" }
        try project.setSceneTextLocked(scene, locked: true)
        try project.setScenePageStart(scene, newPage: true)
        let before = project
        XCTAssertThrowsError(try project.updateBoardBeat(beat) { $0.html = "<p>Overwrite</p>" })
        XCTAssertThrowsError(try project.updateScene(id: scene, html: "Overwrite"))
        XCTAssertEqual(project, before)
        let restored = try Project(data: project.encoded())
        XCTAssertTrue(restored.scenes[0].isTextLocked); XCTAssertTrue(restored.scenes[0].startsNewPage)
    }
}
