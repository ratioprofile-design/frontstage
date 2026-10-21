import Foundation
import XCTest
@testable import FrontstageCore

final class DocumentMergeTests: XCTestCase {
    private func json(_ project: Project) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: project.encoded()) }
    func testIndependentSnippetEditsInOneSceneMergeAndRebuildTextAndCharacters() throws {
        var base = Project(); let a = try base.addBoardBeat(), block = try base.whiteboard().beats[0].blockID
        let b = try base.addBoardBeat(blockID: block)
        try base.updateBoardBeat(a) { $0.html = "<p>A</p>" }; try base.updateBoardBeat(b) { $0.html = "<p>B</p>" }
        var local = base, remote = base
        try local.updateBoardBeat(a) { $0.html = "<p>தமிழ் local</p>"; $0.characters = ["Mara"] }
        try remote.updateBoardBeat(b) { $0.html = "<p>Remote</p>"; $0.characters = ["Jon"] }
        XCTAssertFalse(ProjectMerge.merge(base: try json(base), local: try json(local), remote: try json(remote)).conflicts.isEmpty)
        let merge = ProjectMerge.mergeDocuments(base: try json(base), local: try json(local), remote: try json(remote))
        XCTAssertTrue(merge.conflicts.isEmpty, "\(merge.conflicts)")
        let project = try Project(data: JSONEncoder().encode(merge.value))
        XCTAssertEqual(project.scenes[0].html, "<p>தமிழ் local</p><p>Remote</p>")
        XCTAssertEqual(project.preservedState["beats"]?.array?[0].object?["characters"], .array([.string("Jon"), .string("Mara")]))
        let checkpoint = project
        var edited = project; try edited.editWhiteboard { $0.viewport.zoom = 1.25 }
        XCTAssertEqual(edited.scenes, checkpoint.scenes)
    }
    func testSameSnippetAndConcurrentScriptLockStillRequireExplicitResolution() throws {
        var base = Project(); let a = try base.addBoardBeat()
        try base.updateBoardBeat(a) { $0.html = "<p>A</p>" }
        var local = base, remote = base
        try local.updateBoardBeat(a) { $0.html = "<p>Local</p>" }
        try remote.updateBoardBeat(a) { $0.html = "<p>Remote</p>" }
        let conflict = ProjectMerge.mergeDocuments(base: try json(base), local: try json(local), remote: try json(remote))
        XCTAssertTrue(conflict.conflicts.contains { $0.hasSuffix("/html") })
        remote = base; try remote.setSceneTextLocked(base.scenes[0].id, locked: true)
        let locked = ProjectMerge.mergeDocuments(base: try json(base), local: try json(local), remote: try json(remote))
        XCTAssertTrue(locked.conflicts.contains { $0.hasSuffix("/content") })
    }
    func testNoncanonicalImportedSceneContentIsNeverSilentlyDiscarded() throws {
        var base = Project(); let a = try base.addBoardBeat()
        try base.updateBoardBeat(a) { $0.html = "<p>Canonical</p>" }
        var local = base, remote = base
        try local.editBeat(base.scenes[0].id) { $0["content"] = .string("<p>Unprojected import</p>") }
        try remote.updateBoardBeat(a) { $0.html = "<p>Remote</p>" }
        let merge = ProjectMerge.mergeDocuments(base: try json(base), local: try json(local), remote: try json(remote))
        XCTAssertTrue(merge.conflicts.contains { $0.hasSuffix("/content") })
    }
    func testConcurrentBlockDeletionAndMovingIntoThatBlockRequiresAChoice() throws {
        var base = Project(); let a = try base.addBoardBeat(), b = try base.addBoardBeat()
        let destination = try base.whiteboard().beats.first { $0.id == b }!.blockID
        var local = base, remote = base
        try local.removeBoardBlocks([destination]); try remote.moveBoardBeat(a, toBlock: destination)
        let merge = ProjectMerge.mergeDocuments(base: try json(base), local: try json(local), remote: try json(remote))
        XCTAssertTrue(merge.conflicts.contains("/project/frontstageWhiteboard"))
        XCTAssertEqual(merge.value, try json(local))
    }
}
