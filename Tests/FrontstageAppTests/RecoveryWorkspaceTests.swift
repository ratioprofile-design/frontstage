#if os(macOS)
import Foundation
import AppKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class RecoveryWorkspaceTests: XCTestCase {
    func testTextUndoCannotCrossSceneAndImportedProjectBoundaries() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let workspace = Workspace()
            workspace.addScene()
            let first = workspace.selectedSceneID!
            workspace.addScene()
            let second = workspace.selectedSceneID!
            workspace.selectedSceneID = first
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 250),
                styleMask: [.titled], backing: .buffered, defer: false)
            let text = NSTextView(frame: window.contentView!.bounds)
            text.allowsUndo = true
            window.contentView = text
            window.makeFirstResponder(text)
            workspace.editor.textView = text
            let undo = try XCTUnwrap(text.undoManager)
            text.insertText("First scene edit", replacementRange: NSRange(location: 0, length: 0))
            XCTAssertTrue(undo.canUndo)
            workspace.selectedSceneID = second
            XCTAssertFalse(undo.canUndo)
            text.insertText("Second scene edit", replacementRange: text.selectedRange())
            XCTAssertTrue(undo.canUndo)
            var imported = Project(name: "Another project")
            _ = imported.addScene()
            workspace.loadCopy(imported)
            XCTAssertFalse(undo.canUndo)
            XCTAssertFalse(workspace.history.canUndo)
            XCTAssertEqual(workspace.project.name, "Another project")
            XCTAssertTrue(workspace.hasChanges)
        }
    }
    func testUnreadableRecoveryCopyIsNotOverwrittenByNewEdits() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = RecoveryStore(directory: directory)
            let damaged = Data("unreadable recovery payload".utf8)
            try damaged.write(to: store.fileURL)
            let workspace = Workspace(recoveryStore: store)
            workspace.checkRecovery()
            XCTAssertNotNil(workspace.errorMessage)
            workspace.addScene()
            XCTAssertThrowsError(try workspace.flushRecovery())
            XCTAssertEqual(try Data(contentsOf: store.fileURL), damaged)
        }
    }
    func testProjectUndoRedoTracksDirtyStateAndSelection() async throws {
        await MainActor.run {
            let workspace = Workspace()
            workspace.addScene()
            let id = workspace.selectedSceneID!
            workspace.updateScene(id: id, title: "Arrival")
            workspace.undoProject()
            XCTAssertEqual(workspace.selectedScene?.title, "Untitled Scene")
            workspace.undoProject()
            XCTAssertTrue(workspace.project.scenes.isEmpty)
            XCTAssertNil(workspace.selectedSceneID)
            XCTAssertFalse(workspace.hasChanges)
            workspace.redoProject()
            XCTAssertEqual(workspace.selectedSceneID, id)
            XCTAssertTrue(workspace.hasChanges)
        }
    }

    func testRecoveredProjectRemainsUnsavedAndCanBeDiscardedExplicitly() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = RecoveryStore(directory: directory)
            let first = Workspace(recoveryStore: store)
            first.addScene()
            first.updateScene(id: first.selectedSceneID!, title: "Recovered title")
            try first.flushRecovery()
            let restored = Workspace(recoveryStore: store)
            restored.checkRecovery()
            XCTAssertNotNil(restored.recoveryCandidate)
            restored.recoverSession()
            XCTAssertEqual(restored.selectedScene?.title, "Recovered title")
            XCTAssertTrue(restored.hasChanges)
            XCTAssertFalse(restored.history.canUndo)
            let discarded = Workspace(recoveryStore: store)
            discarded.checkRecovery()
            discarded.discardRecovery()
            XCTAssertNil(discarded.recoveryCandidate)
            XCTAssertNil(try store.load())
        }
    }

    func testFailedEditIsAtomicAndDoesNotPolluteUndoHistory() async throws {
        await MainActor.run {
            let workspace = Workspace()
            workspace.edit("Broken edit") {
                $0.name = "Should roll back"
                throw ProjectError.sceneNotFound
            }
            XCTAssertEqual(workspace.project.name, "Untitled Screenplay")
            XCTAssertFalse(workspace.history.canUndo)
            XCTAssertNotNil(workspace.errorMessage)
        }
    }
}
#endif
