import Foundation
import XCTest
@testable import FrontstageCore

final class DualDialogueTests: XCTestCase {
    private struct Cases: Decodable {
        struct Example: Decodable {
            let name: String, html: String
            let first: Int, second: Int
            var pairIndex: Int?, left: String?, right: String?
        }
        let valid: [Example], invalid: [Example]
    }
    private func fixtures() throws -> Cases {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/dual-dialogue.json")
        return try JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }
    func testSharedFixturesPairAndUnpairLosslessly() throws {
        for example in try fixtures().valid {
            let html = try DualDialogue.pair(in: example.html, firstCue: example.first, secondCue: example.second)
            let pairs = try DualDialogue.pairs(in: html)
            XCTAssertEqual(pairs.count, 1, example.name)
            XCTAssertEqual(pairs[0].left, example.left, example.name)
            XCTAssertEqual(pairs[0].right, example.right, example.name)
            XCTAssertTrue(html.contains(pairs[0].html), example.name)
            XCTAssertEqual(try DualDialogue.remove(in: html, at: example.pairIndex!), example.html, example.name)
            // A saved pair cannot be nested or treated as an ordinary speech.
            XCTAssertThrowsError(try DualDialogue.pair(in: html, firstCue: example.pairIndex!, secondCue: example.pairIndex! + 1), example.name)
        }
    }
    func testInvalidSelectionsNeverProduceAReplacement() throws {
        for example in try fixtures().invalid {
            XCTAssertThrowsError(try DualDialogue.pair(in: example.html, firstCue: example.first, secondCue: example.second), example.name)
        }
        XCTAssertThrowsError(try DualDialogue.remove(in: "<p>Normal text</p>", at: 0))
        XCTAssertThrowsError(try DualDialogue.pairs(in: "<div class='sc-dual'><div class='sc-dual-column sc-dual-left'>Missing right column</div></div>"))
    }
    func testProjectSaveReopenAndMetadataPreservation() throws {
        let originalHTML = try fixtures().valid[1].html
        var project = Project(name: "Overlapping speech", oneBeatPerScene: true)
        let id = try project.addBoardBeat(title: "Two speakers")
        try project.updateBoardBeat(id) { $0.html = originalHTML; $0.synopsis = "Keep this summary"; $0.color = "#a34eae" }
        try project.editBeat(project.scenes[0].id) { fields in
            fields["notes"] = .array([.object(["id": .string("note"), "content": .string("Keep **this**"), "future": .number(42)])])
            fields["breakdown"] = .object(["PROPS": .array([.object(["name": .string("Phone")])])])
            fields["future"] = .string("preserved")
        }
        let before = project, oldBoard = try project.whiteboard()
        try project.pairDialogue(in: id, firstCue: 1, secondCue: 4)
        let saved = try project.encoded()
        project = try Project(data: saved)
        let board = try project.whiteboard()
        XCTAssertEqual(board.beats[0].id, id)
        XCTAssertEqual(board.beats[0].sceneID, oldBoard.beats[0].sceneID)
        XCTAssertEqual(board.blocks, oldBoard.blocks)
        XCTAssertEqual(board.layers, oldBoard.layers)
        XCTAssertEqual(board.dependencies, oldBoard.dependencies)
        XCTAssertEqual(board.beats[0].synopsis, "Keep this summary")
        XCTAssertEqual(board.beats[0].color, "#a34eae")
        XCTAssertEqual(project.scenes[0].html, board.beats[0].html)
        XCTAssertEqual(try DualDialogue.pairs(in: board.beats[0].html).count, 1)
        try project.removeDualDialogue(in: id, at: 1)
        XCTAssertEqual(project, before)
    }
    func testRevisionRoundTripRetainsDialogueAndNotes() throws {
        var project = Project(oneBeatPerScene: true)
        let id = try project.addBoardBeat(), scene = project.scenes[0].id
        try project.updateBoardBeat(id) { $0.html = try fixtures().valid[0].html }
        try project.editBeat(scene) { $0["notes"] = .array([.object(["id": .string("note"), "content": .string("Still attached")])]) }
        try project.pairDialogue(in: id, firstCue: 0, secondCue: 2)
        let paired = project.scenes[0].html
        let revision = try project.saveRevision(sceneID: scene, label: "Two simultaneous speakers")
        try project.removeDualDialogue(in: id, at: 0)
        try project.restoreRevision(sceneID: scene, revisionID: revision)
        XCTAssertEqual(project.scenes[0].html, paired)
        XCTAssertEqual(try DualDialogue.pairs(in: project.scenes[0].html).count, 1)
        XCTAssertEqual(project.preservedState["beats"]?.array?.first?.object?["notes"]?.array?.first?.object?["content"], .string("Still attached"))
    }
    func testHistoryAndIndependentPairs() throws {
        let html = try fixtures().valid[0].html
        var project = Project(oneBeatPerScene: true)
        let id = try project.addBoardBeat()
        try project.updateBoardBeat(id) { $0.html = html + html }
        let original = project
        var history = ProjectHistory()
        history.record(project, label: "Dual dialogue")
        try project.pairDialogue(in: id, firstCue: 0, secondCue: 2)
        try project.pairDialogue(in: id, firstCue: 1, secondCue: 3)
        let paired = project
        XCTAssertEqual(try DualDialogue.pairs(in: project.scenes[0].html).count, 2)
        project = try XCTUnwrap(history.undo(current: project))
        XCTAssertEqual(project, original)
        project = try XCTUnwrap(history.redo(current: project))
        XCTAssertEqual(project, paired)
        try project.removeDualDialogue(in: id, at: 1)
        try project.removeDualDialogue(in: id, at: 0)
        XCTAssertEqual(project, original)
    }
    func testImportedInterColumnCommentsAreNotLost() throws {
        let example = try fixtures().valid[0]
        let paired = try DualDialogue.pair(in: example.html, firstCue: 0, secondCue: 2)
        let annotated = paired.replacingOccurrences(of: "</div><div class=\"sc-dual-column sc-dual-right\">", with: "</div>\n<!-- imported reference -->\n<div class=\"sc-dual-column sc-dual-right\">")
        XCTAssertEqual(try DualDialogue.remove(in: annotated, at: 0), example.left! + "\n<!-- imported reference -->\n" + example.right!)
    }
    func testProtectedOrInactiveTextRejectsAtomically() throws {
        let html = try fixtures().valid[0].html
        for protection in ["beat", "block", "layer", "scene", "omitted", "unused"] {
            var project = Project(oneBeatPerScene: true)
            let id = try project.addBoardBeat()
            try project.updateBoardBeat(id) { $0.html = html }
            if protection == "scene" { try project.setSceneTextLocked(project.scenes[0].id, locked: true) }
            else {
                try project.editWhiteboard { board in
                    switch protection {
                    case "beat": board.beats[0].locked = true
                    case "block": board.blocks[0].locked = true
                    case "layer": board.layers[0].locked = true
                    case "omitted": board.beats[0].omitted = true
                    case "unused": board.layers[0].unused = true
                    default: break
                    }
                }
            }
            let before = project
            XCTAssertThrowsError(try project.pairDialogue(in: id, firstCue: 0, secondCue: 2), protection)
            XCTAssertEqual(project, before, protection)
        }
    }
}
