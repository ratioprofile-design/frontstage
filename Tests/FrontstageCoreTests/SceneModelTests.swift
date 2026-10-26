import XCTest
@testable import FrontstageCore
final class SceneModelTests: XCTestCase {
    func testReviewedCopyPreservesOriginalAndAssignsNotes() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
        var original = try Project(data: Data(contentsOf: url))
        try original.editWhiteboard { board in var extra = board.beats[0]; extra.id = "extra"; extra.order = 0.5; extra.title = "Second scene"; board.beats.append(extra) }
        let before = original
        var copy = try original.convertedSceneCopy(choices: [1: ["notes": ["extra"]]])
        XCTAssertEqual(original, before); XCTAssertTrue(copy.usesOneBeatPerScene); try copy.validateSceneModel()
        let sceneID = try XCTUnwrap(copy.whiteboard().beats.first { $0.id == "extra" }?.sceneID)
        XCTAssertFalse(copy.writingNotes(sceneID: sceneID).isEmpty); XCTAssertTrue(copy.writingNotes(sceneID: 1).isEmpty)
        try copy.updateBeatCard("extra", title: "தமிழ்", synopsis: "Summary")
        XCTAssertEqual(copy.scenes.first { $0.id == sceneID }?.title, "தமிழ்")
        let newID = try copy.splitBoardBeat("extra", firstHTML: "<p>Before</p>", secondHTML: "<p>After</p>")
        try copy.validateSceneModel(); XCTAssertNotEqual(try copy.whiteboard().beats.first { $0.id == newID }?.sceneID, sceneID)
        try copy.pullOutBeats([newID]); try copy.validateSceneModel(); try copy.restorePulledOutBeats([newID]); try copy.validateSceneModel()
        XCTAssertEqual(try Project(data: copy.encoded()), copy)
    }
    func testNewSceneInSameContainerGetsIndependentIdentity() throws {
        var project = Project(oneBeatPerScene: true)
        let first = try project.addBoardBeat(), block = try XCTUnwrap(project.whiteboard().beats.first { $0.id == first }?.blockID)
        let second = try project.addBoardBeat(blockID: block)
        XCTAssertNotEqual(try project.whiteboard().beats.first { $0.id == first }?.sceneID, try project.whiteboard().beats.first { $0.id == second }?.sceneID)
        try project.validateSceneModel(); XCTAssertThrowsError(try project.mergeBoardBeats([first, second]))
        try project.reorderTimelineBeats([first], before: nil); XCTAssertEqual(try project.whiteboard().orderedBeats.last?.id, first)
    }
}
