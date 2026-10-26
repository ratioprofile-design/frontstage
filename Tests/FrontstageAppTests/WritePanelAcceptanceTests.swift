#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp
final class WritePanelAcceptanceTests: XCTestCase {
    func testPanelsKeepEditorControllerAndTargetNotesAcrossSceneChanges() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            let workspace = Workspace(); workspace.loadCopy(try Project(data: Data(contentsOf: fixture))); workspace.mode = .edit
            let controller = workspace.scriptController("beat-1")
            let view = NSHostingView(rootView: ScriptWritingWorkspace(workspace: workspace))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 950), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = view; view.layoutSubtreeIfNeeded()
            let oldSynopsis = workspace.whiteboard.beats.first { $0.id == "beat-1" }?.synopsis
            workspace.edit("Summary") { try $0.updateSceneSummary(1, summary: "தமிழ் summary") }
            XCTAssertEqual(workspace.whiteboard.beats.first { $0.id == "beat-1" }?.synopsis, oldSynopsis)
            var noteID = ""
            workspace.edit("Note") { noteID = try $0.addWritingNote(sceneID: 1, content: "<p>First scene</p>") }
            workspace.selectBoardBeat("beat-2")
            workspace.edit("Pending Note") { try $0.updateWritingNote(sceneID: 1, id: noteID, content: "<p>Still scene one</p>") }
            XCTAssertTrue(workspace.project.writingNotes(sceneID: 2).isEmpty)
            XCTAssertTrue(workspace.project.writingNotes(sceneID: 1).contains { $0.content.contains("Still scene one") })
            XCTAssertTrue(workspace.scriptController("beat-1") === controller)
            workspace.undoProject(); XCTAssertTrue(workspace.project.writingNotes(sceneID: 1).contains { $0.content.contains("First scene") })
            workspace.redoProject(); XCTAssertTrue(workspace.project.writingNotes(sceneID: 1).contains { $0.content.contains("Still scene one") })
            window.setContentSize(NSSize(width: 800, height: 800)); view.layoutSubtreeIfNeeded()
            XCTAssertTrue(workspace.scriptController("beat-1") === controller)
            window.orderOut(nil)
        }
    }
}
#endif
