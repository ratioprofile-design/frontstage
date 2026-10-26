#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp
final class WritePanelAcceptanceTests: XCTestCase {
    func testContinuousEditorCommitsInlineHeadingAndKeepsNotes() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            let workspace = Workspace(); workspace.loadCopy(try Project(data: Data(contentsOf: fixture)))
            let controller = workspace.scriptController("write-continuous")
            let coordinator = ContinuousScriptEditor.Coordinator(workspace, controller)
            let text = ScreenplayTextView(); controller.textView = text; text.screenplayController = controller
            coordinator.load(text)
            XCTAssertTrue(text.string.contains(workspace.project.scenes[0].heading.text))
            let notes = workspace.project.writingNotes(sceneID: 1)
            let headingRange = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.textStorage?.replaceCharacters(in: headingRange, with: "EXT. RIVER - NIGHT\n")
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
            XCTAssertEqual(workspace.project.scenes[0].heading.location, "RIVER")
            XCTAssertEqual(workspace.project.writingNotes(sceneID: 1), notes)
            workspace.edit("Omit") { try $0.setBeatOmitted("beat-1", omitted: true) }
            coordinator.load(text)
            XCTAssertFalse(text.string.contains("RIVER"))
            workspace.edit("Pull Out") { try $0.pullOutBeats(["beat-1"]) }
            XCTAssertEqual(workspace.project.pulledOutBeats.count, 1)
            workspace.undoProject()
            XCTAssertTrue(workspace.project.pulledOutBeats.isEmpty)
        }
    }
    func testPanelsKeepEditorControllerAndTargetNotesAcrossSceneChanges() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            let workspace = Workspace(); workspace.loadCopy(try Project(data: Data(contentsOf: fixture))); workspace.mode = .edit
            let controller = workspace.scriptController("write-continuous")
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
            XCTAssertTrue(workspace.scriptController("write-continuous") === controller)
            workspace.undoProject(); XCTAssertTrue(workspace.project.writingNotes(sceneID: 1).contains { $0.content.contains("First scene") })
            workspace.redoProject(); XCTAssertTrue(workspace.project.writingNotes(sceneID: 1).contains { $0.content.contains("Still scene one") })
            window.setContentSize(NSSize(width: 800, height: 800)); view.layoutSubtreeIfNeeded()
            XCTAssertTrue(workspace.scriptController("write-continuous") === controller)
            window.orderOut(nil)
        }
    }
}
#endif
