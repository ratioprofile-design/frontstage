import Foundation
import XCTest
@testable import FrontstageCore

final class WhiteboardPresentationTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Expected: Decodable { var names: [String]; var colors: [String]; var lines: [[String]] }
        var board: Whiteboard; var expected: Expected
    }
    func testColorAndFlowProjectionNeverChangesAuthoredData() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/board-presentation.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)), board = fixture.board, beat = board.beats[0]
        let before = board
        XCTAssertEqual(board.trackNames(for: beat, kind: "characters"), fixture.expected.names)
        XCTAssertEqual(board.displayColors(for: beat, mode: .characters), fixture.expected.colors)
        XCTAssertEqual(board.displayColors(for: beat, mode: .authored), [beat.color])
        XCTAssertEqual(board.displayColors(for: BoardBeat(sceneID: 1, blockID: "block-1", title: "Empty"), mode: .tags), ["#a34eae"])
        XCTAssertEqual(board.flowLines(kind: "tags", name: "Hope").map { [$0.cause, $0.effect] }, fixture.expected.lines)
        XCTAssertEqual(board.flowLines(kind: "characters", name: "MAYA").map { [$0.cause, $0.effect] }, fixture.expected.lines)
        XCTAssertTrue(board.flowLines(kind: "bad", name: "Hope").isEmpty)
        XCTAssertTrue(board.flowLines(kind: "tags", name: "Missing").isEmpty)
        var unicode = beat; unicode.characters = ["E\u{0301}", "É", " É "]
        XCTAssertEqual(board.trackNames(for: unicode, kind: "characters"), ["É"])
        XCTAssertEqual(board, before)
    }
}
