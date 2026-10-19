import XCTest
import Foundation
@testable import FrontstageCore

final class SceneRevisionTests: XCTestCase {
    func testNamedRevisionRestoreKeepsProductionDataAndBacksUpCurrentText() throws {
        var project = Project()
        let id = project.addScene()
        try project.updateScene(id: id, title: "First", html: "<p>Original தமிழ்</p>", heading: SceneHeading(location: "STATION"))
        let revisionID = try project.saveRevision(sceneID: id, label: "Draft One", now: Date(timeIntervalSince1970: 100))
        try project.updateScene(id: id, title: "Second", html: "<p>New</p>", heading: SceneHeading(location: "TRAIN"))
        try project.restoreRevision(sceneID: id, revisionID: revisionID)
        XCTAssertEqual(project.scenes.first?.title, "First")
        XCTAssertEqual(project.scenes.first?.html, "<p>Original தமிழ்</p>")
        XCTAssertEqual(project.scenes.first?.heading.location, "STATION")
        XCTAssertEqual(project.revisions(for: id).count, 2)
        XCTAssertEqual(project.revisions(for: id).first?.html, "<p>New</p>")
        XCTAssertEqual(try Project(data: project.encoded()), project)
    }

    func testLegacyRevisionCanRestoreWithoutDiscardingUnknownBeatFields() throws {
        var project = try Project(data: Data(#"{"beats":[{"id":1,"title":"Now","content":"new","future":{"keep":true},"versions":[{"id":"old","title":"Before","content":"old","timestamp":1000}]}]}"#.utf8))
        try project.restoreRevision(sceneID: 1, revisionID: "old")
        XCTAssertEqual(project.scenes.first?.html, "old")
        XCTAssertEqual(project.preservedState["beats"]?.array?.first?.object?["future"], .object(["keep": .bool(true)]))
        XCTAssertThrowsError(try project.restoreRevision(sceneID: 1, revisionID: "missing"))
    }

    func testEmptyRevisionLabelIsRejectedWithoutMutation() throws {
        var project = Project()
        let id = project.addScene()
        let before = project
        XCTAssertThrowsError(try project.saveRevision(sceneID: id, label: "   "))
        XCTAssertEqual(project, before)
    }

    func testLineDiffReconstructsBothVersionsIncludingRepeatedLines() {
        let old = "A\nrepeat\nB\nrepeat\nதமிழ்"
        let new = "A\nrepeat\nC\nrepeat\nதமிழ்\nEnd"
        let rows = RevisionDiffLine.compare(before: old, after: new)
        XCTAssertEqual(rows.filter { $0.kind != .added }.map(\.text).joined(separator: "\n"), old)
        XCTAssertEqual(rows.filter { $0.kind != .removed }.map(\.text).joined(separator: "\n"), new)
        XCTAssertTrue(rows.contains { $0.kind == .removed && $0.text == "B" })
    }
}
