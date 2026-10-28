import Foundation
import XCTest
@testable import FrontstageCore

final class DOTProjectTests: XCTestCase {
    func testDOTAndLegacyNativeFilesShareTheStableEnvelope() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
        let project = try Project.load(from: fixture)
        for name in ["Project.dot", "Project.DOT", "Project.frontstage"] {
            let url = root.appendingPathComponent(name)
            try project.save(to: url)
            XCTAssertEqual(try Project.load(from: url), project)
            try project.save(to: url)
            let raw = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
            XCTAssertEqual(raw.object?["format"], .string("frontstage"))
            XCTAssertEqual(raw.object?["version"], .number(1))
        }
    }
    func testWordTemplatesCannotBeOpenedOrOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let word = root.appendingPathComponent("Word template.dot"), bytes = Data([0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1])
        try bytes.write(to: word)
        XCTAssertThrowsError(try Project.load(from: word))
        XCTAssertThrowsError(try Project().save(to: word))
        XCTAssertEqual(try Data(contentsOf: word), bytes)
        let alias = root.appendingPathComponent("alias.dot")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: word)
        XCTAssertThrowsError(try Project().save(to: alias))
        XCTAssertEqual(try Data(contentsOf: word), bytes)
        let legacy = root.appendingPathComponent("original.backstage")
        try Data(#"{"beats":[]}"#.utf8).write(to: legacy)
        XCTAssertThrowsError(try Project().save(to: legacy))
    }
}
