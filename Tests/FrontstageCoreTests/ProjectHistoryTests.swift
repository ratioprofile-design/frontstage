import Foundation
import XCTest
@testable import FrontstageCore

final class ProjectHistoryTests: XCTestCase {
    func testUndoRedoCoalescingAndBranching() {
        var history = ProjectHistory(limit: 2)
        var project = Project(name: "Original")
        let time = Date(timeIntervalSince1970: 100)
        history.record(project, label: "Rename", key: "name", now: time)
        project.name = "A"
        history.record(project, label: "Rename", key: "name", now: time.addingTimeInterval(0.2))
        project.name = "AB"
        project = history.undo(current: project)!
        XCTAssertEqual(project.name, "Original")
        XCTAssertFalse(history.canUndo)
        project = history.redo(current: project)!
        XCTAssertEqual(project.name, "AB")
        project = history.undo(current: project)!
        history.record(project, label: "Branch")
        XCTAssertFalse(history.canRedo)
    }

    func testParagraphCommandsHaveIndependentUndoFromTyping() {
        var history = ProjectHistory(), project = Project(name: "Prefix")
        let time = Date(timeIntervalSince1970: 100)
        history.record(project, label: "Type", key: "writer", now: time)
        project.name = "Accepted name"
        history.endTypingGroup()
        history.record(project, label: "Change element", key: "writer", now: time.addingTimeInterval(0.1))
        project.name = "Transition"
        history.endTypingGroup()
        XCTAssertEqual(history.undo(current: project)?.name, "Accepted name")
        XCTAssertEqual(history.undo(current: project)?.name, "Prefix")
    }

    func testHistoryLimitAndSnapshotsRemainIndependent() {
        var history = ProjectHistory(limit: 2)
        var project = Project()
        for index in 0..<4 {
            history.record(project, label: "Add \(index)")
            _ = project.addScene()
        }
        project = history.undo(current: project)!
        XCTAssertEqual(project.scenes.count, 3)
        project = history.undo(current: project)!
        XCTAssertEqual(project.scenes.count, 2)
        XCTAssertFalse(history.canUndo)
    }

    func testRecoveryRoundTripAndClearNeverTouchImportedSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryStore(directory: directory.appendingPathComponent("Recovery"))
        XCTAssertNil(try store.load())
        var project = Project(name: "Recovery")
        _ = project.addScene()
        try store.save(project)
        XCTAssertEqual(try store.load(), project)
        project.name = "Second snapshot"
        try store.save(project)
        XCTAssertEqual(try store.load()?.name, "Second snapshot")
        try store.clear()
        XCTAssertNil(try store.load())
        try store.clear()
    }
}
