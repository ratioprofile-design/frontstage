import Foundation
import XCTest
@testable import FrontstageCore

final class StudioTests: XCTestCase {
    func testResearchAttachmentsRoundTripAndCSVIncludesActualDetails() throws {
        var project = Project(); let scene = project.addScene()
        let record = try project.addStudioRecord(kind: .shot, title: "Opening", sceneID: scene)
        try project.updateStudioRecord(record) { $0.fields["Lens"] = "35 mm"; $0.body = "தமிழ் notes" }
        let id = try project.attachStudioAsset(to: record, filename: "frame.png", data: Data([1, 2, 3]))
        let restored = try Project(data: project.encoded()), studio = try restored.studio()
        XCTAssertEqual(studio.assets.first?.id, id); XCTAssertEqual(studio.assets.first?.data, Data([1, 2, 3]))
        XCTAssertTrue(try restored.studioCSV(kind: .shot).contains("Lens: 35 mm"))
        XCTAssertTrue(try restored.studioCSV(kind: .shot).contains("தமிழ் notes"))
    }
    func testInvalidAttachmentAndFutureSchemaLeaveDocumentUnchanged() throws {
        var project = Project(); let id = try project.addStudioRecord(kind: .research, title: "Reference")
        let before = project
        XCTAssertThrowsError(try project.attachStudioAsset(to: id, filename: "large.png", data: Data(count: 10 * 1024 * 1024 + 1)))
        XCTAssertEqual(project, before)
        var root = project.state["frontstageStudio"]!.object!; root["version"] = .number(2); project.state["frontstageStudio"] = .object(root)
        let future = project
        XCTAssertThrowsError(try project.updateStudioRecord(id) { $0.title = "Overwrite" }); XCTAssertEqual(project, future)
    }
    func testNativeRevisionsRestoreAllSnippetTextWithoutLaterViewportOverwrite() throws {
        var project = Project(); let a = try project.addBoardBeat()
        let block = try project.whiteboard().beats[0].blockID, scene = project.scenes[0].id
        let b = try project.addBoardBeat(blockID: block)
        try project.updateBoardBeat(a) { $0.html = "<p>A</p>" }; try project.updateBoardBeat(b) { $0.html = "<p>B</p>" }
        let revision = try project.saveRevision(sceneID: scene, label: "Original")
        try project.updateBoardBeat(a) { $0.html = "<p>Changed</p>" }
        try project.restoreRevision(sceneID: scene, revisionID: revision)
        try project.editWhiteboard { $0.viewport.zoom = 0.8 }
        XCTAssertEqual(project.scenes[0].html, "<p>A</p><p>B</p>")
        XCTAssertEqual(project.revisions(for: scene).count, 2)
    }
    func testRoleAssignmentsPersistAcrossWhiteboardUpdates() throws {
        var project = Project(); _ = try project.addBoardBeat(); let scene = project.scenes[0].id
        let role = try project.createCharacter(name: "MARA")
        try project.assignCharacter(role, to: scene, assigned: true)
        try project.editWhiteboard { $0.viewport.zoom = 0.7 }
        XCTAssertEqual(project.sceneCharacters(scene), [role])
        try project.assignCharacter(role, to: scene, assigned: false)
        XCTAssertTrue(project.sceneCharacters(scene).isEmpty)
    }
    func testAssetExportCannotOverwriteImportedProjectViaSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.backstage"), alias = directory.appendingPathComponent("frame.png")
        try Data("original".utf8).write(to: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        XCTAssertThrowsError(try StudioAsset(filename: "frame.png", data: Data([1])).save(to: alias))
        XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
    }
}
