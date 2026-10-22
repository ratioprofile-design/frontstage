#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class StoryWorkspaceTests: XCTestCase {
    func testRippleIsOneUndoStepAndScriptEditsReachBoardAndRecovery() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = RecoveryStore(directory: directory)
            let workspace = Workspace(recoveryStore: store)
            workspace.addScene(); let cause = workspace.selectedSceneID!
            workspace.addScene(); let effect = workspace.selectedSceneID!
            workspace.edit("Set Story") { project in
                try project.moveStoryBeats([effect], by: 0, toLane: 1, ripple: false, snap: false)
                try project.connectScenes(from: cause, to: effect)
                try project.resolveStory()
            }
            let before = workspace.project
            workspace.edit("Move Story Beats") { try $0.moveStoryBeats([cause], by: 300, snap: false) }
            let moved = workspace.project
            XCTAssertNotEqual(before, moved)
            XCTAssertTrue(moved.storySequencer().issues.isEmpty)
            workspace.undoProject(); XCTAssertEqual(workspace.project, before)
            workspace.redoProject(); XCTAssertEqual(workspace.project, moved)
            workspace.selectedSceneID = effect; workspace.mode = .board
            workspace.updateScene(id: effect, title: "An irreversible choice", html: "<div class=\"sc-action\">She closes the door.</div>")
            XCTAssertEqual(workspace.project.storySequencer().beats.last?.node.title, "An irreversible choice")
            try workspace.flushRecovery()
            let recovered = try XCTUnwrap(store.load())
            XCTAssertEqual(recovered, workspace.project)
            XCTAssertTrue(recovered.scenes.last?.html.contains("She closes the door.") == true)
        }
    }

    func testNativeStoryWorkspaceRendersAndKeepsProjectUnchanged() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let workspace = Workspace()
            for title in ["The invitation", "A locked door", "The discovery", "A dangerous choice"] {
                workspace.addScene()
                workspace.updateScene(id: workspace.selectedSceneID!, title: title,
                    html: "<div class=\"sc-action\">Rain moves across the empty courtyard.</div><div class=\"sc-character\">MARA</div><div class=\"sc-dialogue\">Someone was here before us.</div>",
                    summary: "Every decision changes what can happen next.")
            }
            workspace.edit("Example Story") { project in
                try project.moveStoryBeats([2], by: 0, toLane: 1, ripple: false, snap: false)
                try project.moveStoryBeats([4], by: 0, toLane: 1, ripple: false, snap: false)
                try project.connectScenes(from: 1, to: 2)
                try project.connectScenes(from: 2, to: 3)
                try project.connectScenes(from: 3, to: 4)
                try project.resolveStory()
                _ = try project.addStoryMilestone(title: "The turning point", page: 5)
            }
            workspace.mode = .board; workspace.selectedSceneID = 3; workspace.showBoardScript = true
            let before = workspace.project
            let view = NSHostingView(rootView: StoryWorkspaceView(workspace: workspace, boardFirst: true))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 1000),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.frame = NSRect(x: 0, y: 0, width: 1440, height: 1000)
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(workspace.project, before)
            let segment = try XCTUnwrap(before.orderedScript().first { $0.scene.id == 3 })
            let controller = workspace.scriptController(segment.beatIDs.first ?? "scene-3")
            let text = try XCTUnwrap(controller.textView)
            XCTAssertTrue(text.string.contains("Someone was here before us."))
            XCTAssertEqual(text.backgroundColor, .white)
            XCTAssertTrue(window.makeFirstResponder(text))
            XCTAssertTrue(workspace.screenplayController(in: window) === controller)
            if let directory = ProcessInfo.processInfo.environment["FRONTSTAGE_TEST_ARTIFACTS"] {
                let output = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: output.appendingPathComponent("story-workspace.png"))
                try workspace.project.encoded().write(to: output.appendingPathComponent("story-workspace.frontstage"))
            }
            window.close()
        }
    }
}
#endif
