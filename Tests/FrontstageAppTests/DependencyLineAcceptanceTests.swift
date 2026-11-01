#if os(macOS)
import AppKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class DependencyLineAcceptanceTests: XCTestCase {
    func testLineMenuNavigationDeletionUndoAndLockedEndpoints() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            let workspace = Workspace(recoveryStore: nil)
            workspace.loadCopy(try Project(data: Data(contentsOf: fixture)))
            let view = NativeWhiteboard(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
            view.workspace = workspace; view.acceptModel(workspace)
            let geometry = WhiteboardLayout(workspace.whiteboard, measureBeat: WhiteboardBeatText.size)
            let route = BoardDependencyRoute(cause: try XCTUnwrap(geometry.beatRects["beat-1"]), effect: try XCTUnwrap(geometry.beatRects["beat-2"]))
            let menu = try XCTUnwrap(view.dependencyMenu(at: route.point(at: 0.5)))
            XCTAssertTrue(menu.items[0].title.hasPrefix("Go to Cause:"))
            let effect = menu.items[1]
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(effect.action), to: effect.target, from: nil))
            XCTAssertEqual(workspace.selectedBoardBeatID, "beat-2")
            XCTAssertNil(workspace.pendingBoardCauseID)
            let before = workspace.project
            let remove = try XCTUnwrap(menu.items.first { $0.title == "Remove Connection" })
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(remove.action), to: remove.target, from: nil))
            XCTAssertTrue(workspace.whiteboard.dependencies.isEmpty)
            workspace.undoProject(); XCTAssertEqual(workspace.project, before)
            workspace.redoProject(); XCTAssertTrue(workspace.whiteboard.dependencies.isEmpty)
            workspace.undoProject()
            workspace.edit("Lock endpoint") { try $0.editWhiteboard { $0.beats[0].locked = true } }
            view.acceptModel(workspace)
            let locked = try XCTUnwrap(view.dependencyMenu(at: route.point(at: 0.5)))
            XCTAssertTrue(locked.items[0].isEnabled)
            XCTAssertFalse(try XCTUnwrap(locked.items.first { $0.title == "Remove Connection" }).isEnabled)
        }
    }
}
#endif
