import Foundation
import XCTest
@testable import FrontstageCore

final class ScriptSequenceTests: XCTestCase {
    func testInterleavedSnippetsRetainEveryRangeSceneNumberAndPageStart() throws {
        var project = Project(); let a = try project.addBoardBeat(title: "A")
        let block = try project.whiteboard().beats[0].blockID, a2 = try project.addBoardBeat(blockID: block, title: "A2"), b = try project.addBoardBeat(title: "B")
        try project.updateBoardBeat(a) { $0.html = "<p>First A</p>"; $0.start = 0 }
        try project.updateBoardBeat(b) { $0.html = "<p>Only B</p>"; $0.start = 1 }
        try project.updateBoardBeat(a2) { $0.html = "<p>Last A</p>"; $0.start = 2 }
        let aScene = try project.whiteboard().beats.first { $0.id == a }!.sceneID
        try project.setScenePageStart(aScene, newPage: true); try project.updateScene(id: aScene, sceneNumber: "12A")
        try project.applyWhiteboardStoryOrder()
        let before = project, segments = try project.orderedScript()
        XCTAssertEqual(segments.map(\.scene.html), ["<p>First A</p>", "<p>Only B</p>", "<p>Last A</p>"])
        XCTAssertEqual(segments.map(\.number), ["12A", "2", "12A"])
        XCTAssertEqual(segments.map(\.isContinuation), [false, false, true])
        XCTAssertEqual(segments.map(\.scene.startsNewPage), [true, false, false])
        XCTAssertEqual(segments.flatMap(\.beatIDs), [a, b, a2]); XCTAssertEqual(project, before)
        XCTAssertEqual(project.scenes.count, 2)
    }
    func testUnusedAndOmittedSnippetsStayOutAndUnlinkedImportedTextIsRetained() throws {
        var project = Project(); let a = try project.addBoardBeat()
        let block = try project.whiteboard().beats[0].blockID, b = try project.addBoardBeat(blockID: block)
        try project.updateBoardBeat(a) { $0.html = "<p>Printed</p>" }
        try project.updateBoardBeat(b) { $0.html = "<p>Kept off script</p>"; $0.omitted = true }
        let imported = project.addScene(); try project.updateScene(id: imported, html: "<p>Unlinked import</p>")
        XCTAssertEqual(try project.orderedScript().map(\.scene.html), ["<p>Printed</p>", "<p>Unlinked import</p>"])
        try project.moveBoardBlocks([block], delta: .init(), layerID: "unused")
        XCTAssertEqual(try project.orderedScript().map(\.scene.html), ["<p>Unlinked import</p>"])
        XCTAssertTrue(try project.whiteboard().beats.contains { $0.html.contains("Kept off script") })
    }
    func testLegacySequenceDoesNotCreateNativeDataAndFutureBoardIsRejected() throws {
        var project = Project(); let id = project.addScene(); try project.updateScene(id: id, html: "<p>Legacy</p>")
        let before = project
        XCTAssertEqual(try project.orderedScript()[0].scene.html, "<p>Legacy</p>"); XCTAssertEqual(project, before)
        _ = try project.addBoardBeat()
        var native = project.state["frontstageWhiteboard"]!.object!; native["version"] = .number(900); project.state["frontstageWhiteboard"] = .object(native)
        XCTAssertThrowsError(try project.orderedScript())
    }
    func testUnprojectedImportedTextCannotBeOverwrittenByBoardEditsOrIgnoredByExport() throws {
        var project = Project(); let beat = try project.addBoardBeat()
        try project.updateBoardBeat(beat) { $0.html = "<p>Native text</p>" }
        try project.editBeat(project.scenes[0].id) { $0["content"] = .string("<p>Unprojected imported text</p>") }
        let before = project
        XCTAssertThrowsError(try project.editWhiteboard { $0.viewport.zoom = 1.5 })
        XCTAssertThrowsError(try project.addBoardBeat())
        XCTAssertThrowsError(try project.orderedScript())
        XCTAssertEqual(project, before)
        XCTAssertTrue(project.scenes[0].html.contains("Unprojected imported text"))
    }
}
