#if os(macOS)
import AppKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class PushPreviewAcceptanceTests: XCTestCase {
    func testHostedPushPreviewCancelAndSingleUndo() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var project = Project(); _ = try project.addBoardBeat(title: "Left"); _ = try project.addBoardBeat(title: "Right")
            try project.editWhiteboard { board in for i in board.blocks.indices { board.blocks[i].position = .init(x: i == 0 ? 50 : 300, y: 60); board.blocks[i].width = 140 } }
            let workspace = Workspace(recoveryStore: nil); workspace.loadCopy(project)
            let view = NativeWhiteboard(frame: NSRect(x: 0, y: 0, width: 900, height: 600)), window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view; window.makeFirstResponder(view); defer { window.close() }
            view.workspace = workspace; view.acceptModel(workspace); view.pushingMode = true
            @MainActor func mouse(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent { NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 400), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)! }
            view.mouseDown(with: mouse(.leftMouseDown, x: 310)); view.mouseDragged(with: mouse(.leftMouseDragged, x: 360))
            XCTAssertEqual(workspace.project, project); XCTAssertEqual(view.board.blocks[1].position.x, 350); XCTAssertFalse(workspace.history.canUndo)
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            view.keyDown(with: escape); view.mouseUp(with: mouse(.leftMouseUp, x: 360))
            XCTAssertEqual(workspace.project, project); XCTAssertEqual(view.board.blocks[1].position.x, 300); XCTAssertFalse(workspace.history.canUndo)
            view.mouseDown(with: mouse(.leftMouseDown, x: 310)); view.mouseDragged(with: mouse(.leftMouseDragged, x: 360)); view.mouseUp(with: mouse(.leftMouseUp, x: 360))
            XCTAssertEqual(try workspace.project.whiteboard().blocks[1].position.x, 350); XCTAssertTrue(workspace.history.canUndo)
            let committed = workspace.project; workspace.undoProject(); XCTAssertEqual(workspace.project, project); workspace.redoProject(); XCTAssertEqual(workspace.project, committed)
        }
    }
}
#endif
