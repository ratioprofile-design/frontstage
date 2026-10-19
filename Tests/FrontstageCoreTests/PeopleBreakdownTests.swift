import Foundation
import XCTest
@testable import FrontstageCore

final class PeopleBreakdownTests: XCTestCase {
    func testCharacterEditingPreservesRelationshipsImagesAndUnknownFields() throws {
        var project = try Project(data: Data(#"{"beats":[],"characterData":{"RANGA":{"id":"role-1","name":"RANGA","future":true,"images":["photo"],"relationships":[{"target":"OTHER"}]}}}"#.utf8))
        try project.updateCharacter("RANGA", field: .backstory, value: "A station master")
        XCTAssertEqual(project.characters.first?.fields["backstory"], "A station master")
        let record = project.preservedState["characterData"]?.object?["RANGA"]?.object
        XCTAssertEqual(record?["future"], .bool(true))
        XCTAssertEqual(record?["images"]?.array, [.string("photo")])
        XCTAssertEqual(record?["relationships"]?.array?.count, 1)
        XCTAssertThrowsError(try project.createCharacter(name: " ranga "))
        XCTAssertThrowsError(try project.createCharacter(name: "  "))
        XCTAssertEqual(try Project(data: project.encoded()), project)
    }

    func testCastingConfirmationContactPatchesAndPassingConfirmedActor() throws {
        var project = try Project(data: Data(#"{"beats":[],"characterData":{"RANGA":{"name":"RANGA","artists":[{"id":"actor","name":"Actor One","status":"idea","contact":{"agentName":"Agent","email":"old@example.test"},"photoUrl":"keep"}]}}}"#.utf8))
        try project.updateCastingOption(character: "RANGA", artistID: "actor", status: .callback, email: "new@example.test")
        try project.confirmCastingOption(character: "RANGA", artistID: "actor")
        XCTAssertEqual(project.characters.first?.confirmedArtistID, "actor")
        let stored = project.preservedState["characterData"]?.object?["RANGA"]?.object?["artists"]?.array?.first?.object
        XCTAssertEqual(stored?["photoUrl"], .string("keep"))
        XCTAssertEqual(stored?["contact"]?.object?["agentName"], .string("Agent"))
        XCTAssertEqual(project.characters.first?.artists.first?.email, "new@example.test")
        try project.updateCastingOption(character: "RANGA", artistID: "actor", status: .passed)
        XCTAssertNil(project.characters.first?.confirmedArtistID)
        XCTAssertThrowsError(try project.confirmCastingOption(character: "RANGA", artistID: "actor"))
        XCTAssertThrowsError(try project.confirmCastingOption(character: "RANGA", artistID: "missing"))
    }

    func testCharacterAssignmentIsIdempotentAndKeepsOtherImportedNames() throws {
        var project = try Project(data: Data(#"{"beats":[{"id":1,"title":"A","content":"","characters":["UNPROFILED"]}]}"#.utf8))
        let key = try project.createCharacter(name: "Ranga")
        let actor = try project.addCastingOption(character: key, name: "Actor One")
        XCTAssertEqual(project.characters.first?.artists.first?.id, actor)
        try project.assignCharacter(key, to: 1, assigned: true)
        try project.assignCharacter(key, to: 1, assigned: true)
        XCTAssertEqual(project.sceneCharacters(1), ["UNPROFILED", "RANGA"])
        try project.assignCharacter(key, to: 1, assigned: false)
        XCTAssertEqual(project.sceneCharacters(1), ["UNPROFILED"])
        XCTAssertThrowsError(try project.assignCharacter("missing", to: 1, assigned: true))
    }

    func testLegacyAndStructuredBreakdownsCanBeEditedWithoutLosingMetadata() throws {
        var project = try Project(data: Data(#"{"beats":[{"id":1,"title":"A","content":"","breakdown":{"props":["Lantern"],"items":[{"id":"special","category":"SAFETY","name":"Medic","future":true}],"futureMetadata":{"keep":1}}}]}"#.utf8))
        let lantern = try XCTUnwrap(project.breakdownItems(for: 1).first { $0.name == "Lantern" })
        try project.updateBreakdownItem(sceneID: 1, itemID: lantern.id, count: 3, notes: "Battery powered")
        XCTAssertEqual(project.breakdownItems(for: 1).first { $0.name == "Lantern" }?.count, 3)
        try project.addBreakdownItem(sceneID: 1, category: .vehicles, name: "Train", count: 1)
        let medic = try XCTUnwrap(project.breakdownItems(for: 1).first { $0.name == "Medic" })
        try project.updateBreakdownItem(sceneID: 1, itemID: medic.id, notes: "On standby")
        let storage = project.preservedState["beats"]?.array?.first?.object?["breakdown"]?.object
        XCTAssertEqual(storage?["items"]?.array?.first?.object?["future"], .bool(true))
        XCTAssertEqual(storage?["futureMetadata"], .object(["keep": .number(1)]))
        try project.removeBreakdownItem(sceneID: 1, itemID: lantern.id)
        XCTAssertFalse(project.breakdownItems(for: 1).contains { $0.name == "Lantern" })
        XCTAssertEqual(try Project(data: project.encoded()), project)
    }

    func testInvalidBreakdownQuantityDoesNotMutateAndAliasStorageRemainsIntact() throws {
        var project = try Project(data: Data(#"{"beats":[{"id":1,"title":"A","content":"","breakdownData":{"PROPS":["Primary"]},"breakdown":{"props":["Legacy copy"]}}]}"#.utf8))
        let before = project
        XCTAssertThrowsError(try project.addBreakdownItem(sceneID: 1, category: .props, name: "Bad", count: 0))
        XCTAssertEqual(project, before)
        try project.addBreakdownItem(sceneID: 1, category: .props, name: "New")
        XCTAssertEqual(project.breakdownItems(for: 1).count, 2)
        XCTAssertEqual(project.preservedState["beats"]?.array?.first?.object?["breakdown"]?.object?["props"], .array([.string("Legacy copy")]))
    }
}
