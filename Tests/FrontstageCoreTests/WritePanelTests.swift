import Foundation
import XCTest
@testable import FrontstageCore
final class WritePanelTests: XCTestCase {
    func fixture() throws -> Project {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
        return try Project(data: Data(contentsOf: url))
    }
    func testSummaryAndNotesStayIndependentAndPreserveImports() throws {
        var p = try fixture()
        let before = try p.whiteboard().beats
        try p.updateSceneSummary(1, summary: "தமிழ் summary")
        XCTAssertEqual(try p.whiteboard().beats, before)
        XCTAssertEqual(try p.sceneCards().count, 2)
        let id = try p.addWritingNote(sceneID: 1, content: "<b>New</b>")
        try p.updateWritingNote(sceneID: 1, id: id, content: "<i>Edited</i>")
        try p.moveWritingNote(sceneID: 1, id: id, offset: -1)
        XCTAssertThrowsError(try p.updateWritingNote(sceneID: 2, id: id, content: "Wrong target"))
        XCTAssertThrowsError(try p.updateWritingNote(sceneID: 1, id: "audio-import", content: "Unsupported"))
        XCTAssertEqual(p.writingNotes(sceneID: 1).first?.id, "note-import")
        XCTAssertEqual(p.legacyScratchpad(sceneID: 1), "Legacy scratchpad")
        try p.removeWritingNote(sceneID: 1, id: id)
        XCTAssertEqual(p.preservedState["beats"]?.array?.first?.object?["notes"]?.array?.first?.object?["future"], .object(["keep": .bool(true)]))
        XCTAssertEqual(try Project(data: p.encoded()), p)
    }
    func testCategoriesHistoryAndLocks() throws {
        var p = try fixture()
        for category in BreakdownCategory.allCases { try p.addBreakdownItem(sceneID: 1, category: category, name: category.rawValue, count: 2, sourceQuote: "தமிழ்") }
        let entry = try XCTUnwrap(p.breakdownItems(for: 1).first { $0.name == "Legacy lamp" })
        try p.moveBreakdownItem(sceneID: 1, itemID: entry.id, category: .safety)
        XCTAssertTrue(p.breakdownItems(for: 1).contains { $0.name == "Legacy lamp" && $0.category == "SAFETY" })
        XCTAssertTrue(p.breakdownItems(for: 1).contains { $0.category == "VFX" })
        let items = p.breakdownItems(for: 1), notes = p.writingNotes(sceneID: 1)
        let revision = try p.saveRevision(sceneID: 1, label: "Before")
        try p.updateSceneSummary(1, summary: "Changed")
        try p.restoreRevision(sceneID: 1, revisionID: revision)
        XCTAssertEqual(p.breakdownItems(for: 1), items); XCTAssertEqual(p.writingNotes(sceneID: 1), notes)
        XCTAssertEqual(p.revisions(for: 1).count, try fixture().revisions(for: 1).count + 2)
        try p.setSceneTextLocked(1, locked: true)
        XCTAssertThrowsError(try p.updateSceneSummary(1, summary: "Locked"))
        XCTAssertThrowsError(try p.addWritingNote(sceneID: 1))
        XCTAssertThrowsError(try p.restoreRevision(sceneID: 1, revisionID: revision))
    }
}

extension WritePanelTests {
    func testRepeatedSceneCardsAndUnsafeRestoreAreAtomic() throws {
        var p = try fixture()
        try p.editWhiteboard { board in
            var repeated = board.beats[0]; repeated.id = "repeat-beat"; repeated.order = 100; board.beats.append(repeated)
        }
        XCTAssertEqual(try p.sceneCards().count, 2)
        XCTAssertEqual(try p.sceneCards().first?.beats.count, 2)
        let before = p
        XCTAssertThrowsError(try p.reorderSceneCard(1, before: 2)); XCTAssertEqual(p, before)
        let legacy = try XCTUnwrap(p.revisions(for: 1).first?.id)
        try p.editBeat(1) { fields in
            var versions = fields["versions"]!.array!, version = fields["versions"]!.array![0].object!
            version.removeValue(forKey: "frontstageSnippets"); versions[0] = .object(version); fields["versions"] = .array(versions)
        }
        let legacyBefore = p
        XCTAssertThrowsError(try p.restoreRevision(sceneID: 1, revisionID: legacy)); XCTAssertEqual(p, legacyBefore)
        let snapshot = try p.saveRevision(sceneID: 1, label: "With boundaries")
        try p.editBeat(1) { fields in
            var versions = fields["versions"]!.array!
            let index = versions.firstIndex { $0.object?["id"]?.string == snapshot }!
            var version = versions[index].object!, snippets = version["frontstageSnippets"]!.array!
            var snippet = snippets[0].object!; snippet["blockID"] = .string("missing-container"); snippets[0] = .object(snippet)
            version["frontstageSnippets"] = .array(snippets); versions[index] = .object(version); fields["versions"] = .array(versions)
        }
        let missing = p
        XCTAssertThrowsError(try p.restoreRevision(sceneID: 1, revisionID: snapshot)); XCTAssertEqual(p, missing)
    }
    func testNotesAndSummariesMergeAcrossDevices() throws {
        let base = try fixture(); var local = base, remote = base
        try local.updateWritingNote(sceneID: 1, id: "note-import", content: "<p>Local note</p>")
        try remote.updateSceneSummary(1, summary: "Remote summary")
        let decode: (Project) throws -> JSONValue = { try JSONDecoder().decode(JSONValue.self, from: $0.encoded()) }
        let merged = try ProjectMerge.mergeDocuments(base: decode(base), local: decode(local), remote: decode(remote))
        XCTAssertTrue(merged.conflicts.isEmpty)
        let result = try Project(data: JSONEncoder().encode(merged.value))
        XCTAssertEqual(result.scenes.first?.summary, "Remote summary")
        XCTAssertEqual(result.writingNotes(sceneID: 1).first?.content, "<p>Local note</p>")
    }
}
