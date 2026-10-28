import XCTest
@testable import FrontstageCore

final class AntigravityAdoptionTests: XCTestCase {
    private func fixture() throws -> [String: JSONValue] {
        try XCTUnwrap(JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/antigravity-contract.json"))).object)
    }
    func testTypographyImportAndUnknownFieldsSurviveEditsAndReopen() throws {
        let contract = try fixture()
        var p = Project(); p.state["frontstageScriptLayout"] = contract["typography"]
        var layout = p.scriptLayout
        XCTAssertEqual(layout.effectiveFontName(for: .character), "Missing DOT Test Font")
        XCTAssertEqual(layout.effectiveFontSize(for: .character), 18)
        XCTAssertTrue(layout.isTamil(for: .character))
        XCTAssertFalse(layout.isBold(for: .character))
        layout.fontSize = 13; try p.setScriptLayout(layout)
        let raw = try XCTUnwrap(p.state["frontstageScriptLayout"]?.object)
        XCTAssertEqual(raw["futureSetting"], contract["typography"]?.object?["futureSetting"])
        XCTAssertEqual(raw["elements"]?.object?["character"]?.object?["futureTrait"], .string("retained"))
        XCTAssertEqual(try Project(data: p.encoded()).scriptLayout, layout)
        layout.elements["character"]?.fontSize = .infinity
        let before = p; XCTAssertThrowsError(try p.setScriptLayout(layout)); XCTAssertEqual(before, p)
    }
    func testRevisionBaselineHistoryAndIdentity() throws {
        let contract = try fixture(); var p = Project()
        p.state["productionRevision"] = contract["revision"]
        let original = try XCTUnwrap(p.currentRevision)
        p.updateRevisionLabel("Edited label"); p.setRevisionColor(.pink)
        XCTAssertEqual(p.currentRevision?.id, original.id)
        XCTAssertEqual(p.currentRevision?.date, original.date)
        XCTAssertEqual(p.state["productionRevision"]?.object?["futureRevisionField"], contract["revision"]?.object?["futureRevisionField"])
        let edited = p.state["productionRevision"]
        p.startNextRevision()
        XCTAssertEqual(p.state["productionRevisionHistory"]?.array?.first, edited)
        XCTAssertNotEqual(p.currentRevision?.id, original.id)
        p.clearProductionRevision()
        XCTAssertNil(p.currentRevision)
        XCTAssertEqual(p.state["productionRevisionHistory"]?.array?.count, 2)
        XCTAssertEqual(try Project(data: p.encoded()), p)
    }
    func testShelfDeletionRemovesOrphanAndReferencesWithoutPruningAssets() throws {
        var p = Project(oneBeatPerScene: true)
        let id = try p.addBoardBeat(title: "Delete"), other = try p.addBoardBeat(title: "Keep")
        let sid = try XCTUnwrap(p.whiteboard().beats.first { $0.id == id }?.sceneID)
        let record = try p.addStudioRecord(kind: .research, title: "Retain", sceneID: sid, beatID: id)
        let day = try p.addProductionDay(date: "2026-10-28")
        try p.assignScene(sid, toProductionDay: day)
        try p.pullOutBeats([id]); let before = p
        var history = ProjectHistory(); history.record(before, label: "Delete Archived Beat")
        try p.deletePulledOutBeats([id]); try p.validateSceneModel()
        XCTAssertFalse(p.scenes.contains { $0.id == sid })
        XCTAssertTrue(try p.whiteboard().beats.contains { $0.id == other })
        XCTAssertTrue(p.pulledOutBeats.isEmpty)
        XCTAssertEqual(p.state["frontstageStudio"]?.object?["records"]?.array?.first?.object?["id"], .string(record))
        XCTAssertNil(p.state["frontstageStudio"]?.object?["records"]?.array?.first?.object?["sceneID"])
        XCTAssertEqual(history.undo(current: p), before)
        XCTAssertEqual(try Project(data: p.encoded()), p)
    }
    func testShelfDeletionChecksLocksAndSharedSceneOwners() throws {
        var p = Project(); let a = try p.addBoardBeat(title: "A")
        let sid = try XCTUnwrap(p.whiteboard().beats.first { $0.id == a }?.sceneID)
        try p.editWhiteboard { board in var b = board.beats[0]; b.id = "second-owner"; board.beats.append(b) }
        try p.pullOutBeats([a]); try p.setSceneTextLocked(sid, locked: true)
        let before = p; XCTAssertThrowsError(try p.deletePulledOutBeats([a])); XCTAssertEqual(p, before)
        try p.setSceneTextLocked(sid, locked: false); try p.deletePulledOutBeats([a])
        XCTAssertTrue(p.scenes.contains { $0.id == sid })
    }
    func testPreferenceReviewExcludesOverridesAndDefaultsConflictsToCurrent() throws {
        let incoming: [String: JSONValue] = ["write-left-visible": .bool(false), "frontstage_restore_last_project": .bool(true), "NSConvolutionOverride1": .number(5), "apikey": .string("excluded"), "default_paper_size": .string("invalid")]
        let review = PreferenceImportReview(current: ["write-left-visible": .bool(true)], incoming: incoming)
        XCTAssertEqual(review.conflicts, ["write-left-visible"])
        XCTAssertNil(review.accepted()["write-left-visible"])
        XCTAssertEqual(review.accepted()["frontstage_restore_last_project"], .bool(true))
        XCTAssertEqual(review.accepted(replaceConflicts: ["write-left-visible"])["write-left-visible"], .bool(false))
        XCTAssertNil(review.incoming["apikey"]); XCTAssertNil(review.incoming["NSConvolutionOverride1"])
        XCTAssertNil(review.incoming["default_paper_size"])
    }
    func testOldSharedWritersCannotStripAdoptedFeatures() throws {
        var prior = Project(); prior.state["frontstageScriptLayout"] = try fixture()["typography"]
        let stripped = Project()
        XCTAssertThrowsError(try stripped.validateWriterCompatibility(previous: prior, supported: []))
        XCTAssertNoThrow(try prior.validateWriterCompatibility(previous: prior, supported: Project.supportedWriteFeatures))
    }
    func testDualPairOnlyAdjacentCompleteSpeechWithinOneScene() throws {
        let lines: [DualDialogueLine] = [.init(element: .character, text: "KAMAL", scene: "1"), .init(element: .dialogue, text: "தமிழ்", scene: "1"), .init(element: .character, text: "ABI", scene: "1"), .init(element: .parenthetical, text: "(quietly)", scene: "1"), .init(element: .dialogue, text: "Yes", scene: "1")]
        let plan = try DualDialogueRules.pair(in: lines, at: 4)
        XCTAssertEqual(plan.left, 0..<2); XCTAssertEqual(plan.right, 2..<5)
        var nextScene = lines; nextScene[2].scene = "2"
        XCTAssertThrowsError(try DualDialogueRules.pair(in: nextScene, at: 4))
        var action = lines; action.insert(.init(element: .action, text: "Barrier", scene: "1"), at: 2)
        XCTAssertThrowsError(try DualDialogueRules.pair(in: action, at: 5))
        var empty = lines; empty[4].text = ""
        XCTAssertThrowsError(try DualDialogueRules.pair(in: empty, at: 2))
    }

    func testInterchangeAndDrawingContracts() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/interchange-contract.json")
        let paragraphs = try JSONDecoder().decode([ScreenplayExportParagraph].self, from: Data(contentsOf: url))
        let fdx = try ScreenplayInterchange.fdx(paragraphs), fountain = try ScreenplayInterchange.fountain(paragraphs)
        XCTAssertTrue(fdx.contains("<DualDialogue>")); XCTAssertTrue(fdx.contains("Number=\"12\""))
        XCTAssertTrue(fdx.contains("தமிழ் &amp; &lt;light&gt;")); XCTAssertTrue(fdx.contains("Style=\"Bold+Underline\""))
        XCTAssertTrue(fountain.contains("@ABI ^")); XCTAssertTrue(fountain.contains("#12#"))
        XCTAssertThrowsError(try ScreenplayInterchange.fdx(paragraphs.filter { $0.element != .dialogue }))
        let stroke = BoardStroke(points: [.init(x: 0, y: 0), .init(x: 100, y: 100)])
        XCTAssertTrue(BoardDrawing.hits(stroke, path: [.init(x: 0, y: 100), .init(x: 100, y: 0)], radius: 1))
        XCTAssertFalse(BoardDrawing.hits(stroke, path: [.init(x: 200, y: 0)], radius: 1))
    }

}
