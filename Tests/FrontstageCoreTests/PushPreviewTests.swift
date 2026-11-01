import XCTest
@testable import FrontstageCore

final class PushPreviewTests: XCTestCase {
    private func fixture() throws -> Project {
        var p = Project(); let left = try p.addBoardBeat(title: "Left"), right = try p.addBoardBeat(title: "Right")
        try p.editWhiteboard { board in
            let a = board.beats.first { $0.id == left }!.blockID, b = board.beats.first { $0.id == right }!.blockID
            for i in board.blocks.indices { board.blocks[i].position = .init(x: board.blocks[i].id == a ? 50 : 300, y: 20); board.blocks[i].width = 140 }
            board.beats[0].order = 1; board.beats[1].order = 0
            XCTAssertNotEqual(a, b)
        }
        return p
    }
    func testPreviewUsesSharedPushContractWithoutMutatingSource() throws {
        struct Case: Decodable { var distance: Double; var rightX: Double }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/push-preview.json")
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: file)), source = try fixture(), before = source
        for item in cases {
            let result = try source.previewWhiteboardPush(from: 200, by: item.distance), board = try result.whiteboard()
            XCTAssertEqual(board.blocks[0].position, .init(x: 50, y: 20))
            XCTAssertEqual(board.blocks[1].position, .init(x: item.rightX, y: 20))
            XCTAssertEqual(source, before)
        }
        XCTAssertEqual(try source.previewWhiteboardPush(from: 900, by: 50), source)
        XCTAssertEqual(try source.previewWhiteboardPush(from: 200, by: 4), source)
    }
    func testInvalidOrLockedPushIsAtomic() throws {
        var source = try fixture(); let before = source
        XCTAssertThrowsError(try source.previewWhiteboardPush(from: .nan, by: 50)); XCTAssertEqual(source, before)
        XCTAssertThrowsError(try source.previewWhiteboardPush(from: 200, by: .infinity)); XCTAssertEqual(source, before)
        try source.editWhiteboard { $0.beats[1].locked = true }; let locked = source
        XCTAssertThrowsError(try source.previewWhiteboardPush(from: 200, by: 20)); XCTAssertEqual(source, locked)
    }
}
