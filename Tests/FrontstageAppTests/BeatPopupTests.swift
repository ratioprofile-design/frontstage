#if os(macOS)
import AppKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class BeatPopupTests: XCTestCase {
    func testPopupKeepsItsBeatIdentityWhileBoardSelectionChangesAndClosesOnImport() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let workspace = Workspace()
            var a = "", b = ""
            workspace.edit("Story") { project in
                a = try project.addBoardBeat(title: "First")
                b = try project.addBoardBeat(title: "Second")
            }
            workspace.selectBoardBeat(a)
            workspace.popup.open(a, workspace: workspace, near: NSRect(x: -10000, y: -10000, width: 10, height: 10))
            defer { workspace.popup.close() }
            let controller = try XCTUnwrap(workspace.popup.controller)
            let panel = try XCTUnwrap(workspace.popup.panel)
            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let text = try XCTUnwrap(controller.textView)
            XCTAssertFalse(controller === workspace.editor)
            workspace.selectBoardBeat(b)
            XCTAssertEqual(workspace.popup.beatID, a)
            text.insertText("Only the first beat changes.", replacementRange: NSRange(location: 0, length: 0))
            XCTAssertTrue(try workspace.project.whiteboard().beats.first { $0.id == a }!.html.contains("Only the first beat changes."))
            XCTAssertEqual(try workspace.project.whiteboard().beats.first { $0.id == b }!.html, "")
            if let screen = panel.screen { XCTAssertTrue(screen.visibleFrame.intersects(panel.frame)) }
            if let directory = ProcessInfo.processInfo.environment["FRONTSTAGE_TEST_ARTIFACTS"], let view = panel.contentView {
                let url = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("beat-popup.png"))
            }
            workspace.loadCopy(Project())
            XCTAssertNil(workspace.popup.panel)
        }
    }
}
#endif
