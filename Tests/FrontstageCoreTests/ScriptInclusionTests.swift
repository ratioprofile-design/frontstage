import XCTest
import Foundation
@testable import FrontstageCore
final class ScriptInclusionTests: XCTestCase {
    func fixture() throws -> Project { try Project(data: Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage"))) }
    func testArchiveRoundTripKeepsProductionAndUnknownFields() throws {
        var p = try fixture(); let before = p
        try p.pullOutBeats(["beat-1"])
        XCTAssertFalse(try p.whiteboard().beats.contains { $0.id == "beat-1" }); XCTAssertEqual(p.pulledOutBeats.count, 1)
        XCTAssertEqual(p.writingNotes(sceneID: 1), before.writingNotes(sceneID: 1)); XCTAssertEqual(p.breakdownItems(for: 1), before.breakdownItems(for: 1))
        XCTAssertTrue(try p.orderedScript().allSatisfy { $0.scene.id != 1 })
        p = try Project(data: p.encoded()); try p.restorePulledOutBeats(["beat-1"])
        XCTAssertTrue(p.pulledOutBeats.isEmpty); XCTAssertEqual(try p.whiteboard().beats.first { $0.id == "beat-1" }?.html, try before.whiteboard().beats.first { $0.id == "beat-1" }?.html)
        XCTAssertEqual(p.writingNotes(sceneID: 1), before.writingNotes(sceneID: 1))
    }
    func testOmissionAndMissingContainerRestoreAreAtomic() throws {
        var p = try fixture(); try p.setBeatOmitted("beat-1", omitted: true); try p.pullOutBeats(["beat-1"])
        XCTAssertTrue(p.pulledOutBeats[0].wasOmitted)
        try p.restorePulledOutBeats(["beat-1"]); XCTAssertTrue(try p.whiteboard().beats.first { $0.id == "beat-1" }!.omitted)
        try p.pullOutBeats(["beat-1"]); try p.editWhiteboard { $0.blocks.removeAll { $0.id == "block-1" } }
        let before = p; XCTAssertThrowsError(try p.restorePulledOutBeats(["beat-1"])); XCTAssertEqual(p, before)
        try p.restorePulledOutBeats(["beat-1"], into: "block-2"); XCTAssertTrue(p.pulledOutBeats.isEmpty)
    }
    func testRestoreLeadingSequenceKeepsOrder() throws {
        var p = try fixture()
        try p.editWhiteboard { board in
            var third = board.beats[1]; third.id = "beat-3"; third.order = 10; board.beats.append(third)
        }
        try p.pullOutBeats(["beat-1", "beat-2"])
        try p.restorePulledOutBeats(["beat-1", "beat-2"])
        XCTAssertEqual(try p.whiteboard().orderedBeats.map(\.id), ["beat-1", "beat-2", "beat-3"])
    }
    func testPermanentDeletionKeepsSurvivorRestoreNeighbors() throws {
        var p = try fixture()
        try p.editWhiteboard { board in var third = board.beats[1]; third.id = "beat-3"; third.order = 10; board.beats.append(third) }
        try p.pullOutBeats(["beat-1", "beat-2"])
        try p.deletePulledOutBeats(["beat-2"])
        try p.restorePulledOutBeats(["beat-1"])
        XCTAssertEqual(try p.whiteboard().orderedBeats.map(\.id), ["beat-1", "beat-3"])
    }
    func testRevisionCannotDuplicatePulledOutBeat() throws {
        var p = try fixture()
        try p.saveRevision(sceneID: 1, label: "Before pull out")
        let revision = try XCTUnwrap(p.revisions(for: 1).first)
        try p.pullOutBeats(["beat-1"])
        let before = p
        XCTAssertThrowsError(try p.restoreRevision(sceneID: 1, revisionID: revision.id))
        XCTAssertEqual(p, before)
        try p.restorePulledOutBeats(["beat-1"])
        try p.restoreRevision(sceneID: 1, revisionID: revision.id)
        XCTAssertEqual(try p.whiteboard().beats.filter { $0.id == "beat-1" }.count, 1)
    }
    func testContinuousTextAndHeadingEdits() throws {
        var p = try fixture(); let notes = p.writingNotes(sceneID: 1)
        try p.applyScriptDocument(beatHTML: ["beat-1": "<p>தமிழ்</p>"], headings: [.init(sceneID: 1, text: "ext. river - night")])
        XCTAssertEqual(p.scenes.first?.heading.location, "RIVER"); XCTAssertEqual(p.writingNotes(sceneID: 1), notes)
        let id = try p.insertScriptScene(afterSplitting: "beat-1", beforeHTML: "<p>Before</p>", afterHTML: "<p>After</p>", heading: "INT. HOME - DAY")
        XCTAssertNotEqual(try p.whiteboard().beats.first { $0.id == id }?.sceneID, 1); XCTAssertEqual(p.writingNotes(sceneID: 1), notes)
        XCTAssertEqual(try Project(data: p.encoded()), p)
    }
    func testTransitionScenePreservesIdentityAndRejectsInactiveSources() throws {
        var project = Project(oneBeatPerScene: true)
        let source = try project.addBoardBeat(title: "Source"), other = try project.addBoardBeat(title: "Other")
        try project.groupBoardBeats([source, other])
        let before = try project.whiteboard(), original = try XCTUnwrap(before.beats.first { $0.id == source })
        let id = try project.insertScriptScene(afterSplitting: source, beforeHTML: "<p class='sc-transition'>CUT TO:</p>", afterHTML: "<p>தமிழ் after</p>", heading: "")
        let board = try project.whiteboard(), next = try XCTUnwrap(board.beats.first { $0.id == id })
        XCTAssertNotEqual(next.sceneID, original.sceneID); XCTAssertEqual(next.blockID, original.blockID)
        XCTAssertEqual(board.blocks, before.blocks)
        XCTAssertTrue(try XCTUnwrap(board.beats.first { $0.id == source }).html.contains("CUT TO:"))
        XCTAssertEqual(next.html, "<p>தமிழ் after</p>")
        try project.validateSceneModel()
        XCTAssertEqual(try Project(data: project.encoded()), project)
        try project.editWhiteboard { board in board.layers[0].unused = true }
        let inactive = project
        XCTAssertThrowsError(try project.insertScriptScene(afterSplitting: source, beforeHTML: "", afterHTML: "", heading: ""))
        XCTAssertEqual(project, inactive)
    }

}
