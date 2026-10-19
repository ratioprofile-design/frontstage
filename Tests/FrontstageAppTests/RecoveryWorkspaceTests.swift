#if os(macOS)
import Foundation
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class RecoveryWorkspaceTests: XCTestCase {
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
