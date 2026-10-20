import Foundation
import XCTest
@testable import FrontstageCore

final class ProjectMergeTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    func testDisjointFieldsOfSameBeatMergeWithoutDroppingUnknownValues() throws {
        let base = try json(#"{"beats":[{"id":"a","title":"Original","x":0,"future":true}]}"#)
        let local = try json(#"{"beats":[{"id":"a","title":"Edited","x":0,"future":true}]}"#)
        let remote = try json(#"{"beats":[{"id":"a","title":"Original","x":50,"future":true}]}"#)
        let result = ProjectMerge.merge(base: base, local: local, remote: remote)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(result.value, try json(#"{"beats":[{"id":"a","title":"Edited","x":50,"future":true}]}"#))
    }
    func testSameFieldAndDeleteVersusEditRequireAChoice() throws {
        let base = try json(#"{"beats":[{"id":1,"title":"Original"}]}"#)
        let local = try json(#"{"beats":[{"id":1,"title":"Local"}]}"#)
        let remote = try json(#"{"beats":[{"id":1,"title":"Remote"}]}"#)
        XCTAssertEqual(ProjectMerge.merge(base: base, local: local, remote: remote).conflicts, ["/beats/1/title"])
        XCTAssertEqual(ProjectMerge.merge(base: base, local: try json(#"{"beats":[]}"#), remote: remote).conflicts, ["/beats/1"])
    }
    func testConcurrentIndependentInsertionsMergeAndOpposingReordersConflict() throws {
        let base = try json(#"[{"id":"a"},{"id":"z"}]"#)
        let local = try json(#"[{"id":"a"},{"id":"b"},{"id":"z"}]"#)
        let remote = try json(#"[{"id":"a"},{"id":"c"},{"id":"z"}]"#)
        let result = ProjectMerge.merge(base: base, local: local, remote: remote)
        XCTAssertTrue(result.conflicts.isEmpty); XCTAssertEqual(result.value.array?.count, 4)
        let conflict = ProjectMerge.merge(base: try json(#"[{"id":"a"},{"id":"b"},{"id":"c"}]"#), local: try json(#"[{"id":"b"},{"id":"a"},{"id":"c"}]"#), remote: try json(#"[{"id":"a"},{"id":"c"},{"id":"b"}]"#))
        XCTAssertEqual(conflict.conflicts, ["/@order"])
    }
}
