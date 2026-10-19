import Foundation
import XCTest
@testable import FrontstageCore

final class ProjectTests: XCTestCase {
    private let legacy = Data(#"""
    {
      "beats": [{"id": 7, "title": "Arrival", "content": "<p>வணக்கம் <b>world</b></p>",
                 "slug": {"prefix": "EXT.", "location": "STATION", "time": "NIGHT"},
                 "shots": [{"id": "shot-1", "custom": true}], "futureBeatField": [1, null, "x"]}],
      "nextId": 2,
      "documents": [{"id": "doc-1", "content": "preserve me"}],
      "futureProjectField": {"number": 9007199254740993, "flag": false},
      "geminiApiKey": "synthetic-test-value",
      "settings": {"openrouterKey": "synthetic-test-value", "font": "Vijaya"}
    }
    """#.utf8)

    func testLegacyRoundTripPreservesUnportedFieldsAndTamilHTML() throws {
        let imported = try Project(data: legacy, fallbackName: "Pilot")
        let reopened = try Project(data: imported.encoded())
        XCTAssertEqual(imported, reopened)
        XCTAssertEqual(reopened.scenes.first?.html, "<p>வணக்கம் <b>world</b></p>")
        XCTAssertEqual(reopened.preservedState["documents"]?.array?.count, 1)
        XCTAssertEqual(reopened.preservedState["futureProjectField"]?.object?["number"],
                       .number(Decimal(string: "9007199254740993")!))
    }

    func testEditsPreserveUnknownSceneFields() throws {
        var project = try Project(data: legacy)
        let old = project.preservedState["beats"]?.array?.first?.object
        try project.updateScene(id: 7, title: "Departure", html: "<p>Edited</p>")
        let new = project.preservedState["beats"]?.array?.first?.object
        XCTAssertEqual(project.scenes.first?.title, "Departure")
        XCTAssertEqual(new?["futureBeatField"], old?["futureBeatField"])
        XCTAssertEqual(new?["shots"], old?["shots"])
        XCTAssertEqual(new?["slug"], old?["slug"])
    }

    func testKnownLegacyCredentialsAreRemovedRecursively() throws {
        let project = try Project(data: legacy)
        XCTAssertNil(project.preservedState["geminiApiKey"])
        XCTAssertNil(project.preservedState["settings"]?.object?["openrouterKey"])
        XCTAssertEqual(project.preservedState["settings"]?.object?["font"], .string("Vijaya"))
        XCTAssertFalse(String(decoding: try project.encoded(), as: UTF8.self).contains("synthetic-test-value"))
    }

    func testAddSceneRepairsStaleNextIDWithoutCollisions() throws {
        var project = try Project(data: legacy)
        XCTAssertEqual(project.addScene(), 8)
        XCTAssertEqual(project.addScene(), 9)
        XCTAssertEqual(Set(project.scenes.map(\.id)).count, 3)
    }

    func testAddSceneRespectsHigherNextID() throws {
        var project = try Project(data: Data(#"{"beats":[],"nextId":42}"#.utf8))
        XCTAssertEqual(project.addScene(), 42)
    }

    func testMalformedProjectsAreRejected() {
        for source in ["[]", "{}", #"{"beats":{}}"#,
                       #"{"beats":[{"id":1,"title":"A"}]}"#,
                       #"{"beats":[{"id":1.5,"title":"A","content":""}]}"#,
                       #"{"beats":[{"id":1,"title":"A","content":""},{"id":1,"title":"B","content":""}]}"#] {
            XCTAssertThrowsError(try Project(data: Data(source.utf8)), source)
        }
    }

    func testFutureVersionIsRejectedInsteadOfSilentlyRewritten() {
        XCTAssertThrowsError(try Project(data: Data(
            #"{"format":"frontstage","version":2,"project":{"beats":[]}}"#.utf8))) { error in
            XCTAssertEqual(error as? ProjectError, .unsupportedVersion(2))
        }
    }

    func testMissingSceneEditFails() {
        var project = Project()
        XCTAssertThrowsError(try project.updateScene(id: 99, title: "Missing"))
    }

    func testAtomicSaveReopensAndDoesNotChangeLegacySource() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("pilot.backstage")
        let destination = directory.appendingPathComponent("pilot.frontstage")
        try legacy.write(to: source)
        var project = try Project.load(from: source)
        try project.save(to: destination)
        try project.updateScene(id: 7, title: "Revised")
        try project.save(to: destination)
        XCTAssertEqual(try Project.load(from: destination), project)
        XCTAssertEqual(try Data(contentsOf: source), legacy)
        XCTAssertThrowsError(try project.save(to: source))
        XCTAssertEqual(try Data(contentsOf: source), legacy)
    }

    func testSymlinkCannotBypassImportOnlyRestriction() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.backstage")
        let alias = directory.appendingPathComponent("alias.frontstage")
        try legacy.write(to: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        XCTAssertThrowsError(try Project().save(to: alias))
        XCTAssertEqual(try Data(contentsOf: source), legacy)
    }

    func testJSONValuesRoundTripDistinctTypes() throws {
        let data = Data(#"{"a":true,"b":1,"c":null,"d":["தமிழ்",false,0.125]}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: encoded), value)
        XCTAssertEqual(value.object?["a"], .bool(true))
        XCTAssertEqual(value.object?["b"], .number(1))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
