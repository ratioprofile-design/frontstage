#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class WorkspaceParityAcceptanceTests: XCTestCase {
    func testAllWorkspacesRenderTheSamePortableProject() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/workspace-parity.frontstage")
            let project = try Project(data: Data(contentsOf: fixture))
            let workspace = Workspace()
            workspace.loadCopy(project)
            let ids = ["board", "edit", "pages", "revisions", "people", "breakdown", "production", "writingTools", "studio", "shared"]
            XCTAssertEqual(Workspace.Mode.allCases.map(\.rawValue), WorkspaceDesign.pageTitles)
            let output = ProcessInfo.processInfo.environment["FRONTSTAGE_PARITY_OUTPUT"].map { URL(fileURLWithPath: $0) }
            if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 950), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { workspace.popup.close(); window.contentView = nil; window.close() }
            @MainActor func capture(_ view: NSView, name: String) throws {
                guard let output else { return }
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("mac-\(name).png"))
            }
            for (index, mode) in Workspace.Mode.allCases.enumerated() {
                workspace.mode = mode
                if mode == .pages { workspace.makePreview() }
                let view = NSHostingView(rootView: WorkspaceView(workspace: workspace))
                view.frame = NSRect(x: 0, y: 0, width: 1440, height: 950)
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                view.layoutSubtreeIfNeeded()
                XCTAssertEqual(workspace.project, project, "Opening \(mode.rawValue) must not change the project")
                XCTAssertNil(workspace.errorMessage)
                try capture(view, name: ids[index])
            }
            workspace.mode = .board; workspace.showBoardScript = true
            let sideView = NSHostingView(rootView: WorkspaceView(workspace: workspace))
            sideView.frame = NSRect(x: 0, y: 0, width: 1440, height: 950); window.contentView = sideView
            sideView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            try capture(sideView, name: "board-script")
            let sideText = try XCTUnwrap(workspace.scriptController("reader-beat-1").textView)
            XCTAssertTrue(sideText.string.contains("invitation arrives"))
            sideText.insertText("Side paper. ", replacementRange: NSRange(location: 0, length: 0))
            XCTAssertTrue(workspace.whiteboard.beats.first { $0.id == "beat-1" }?.html.contains("Side paper.") == true)
            workspace.undoProject()
            XCTAssertEqual(workspace.project, project)
            window.setContentSize(NSSize(width: 1073, height: 800))
            sideView.frame = NSRect(x: 0, y: 0, width: 1073, height: 800)
            sideView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            sideView.layoutSubtreeIfNeeded()
            @MainActor func findCanvas(_ view: NSView) -> NativeWhiteboard? {
                if let canvas = view as? NativeWhiteboard { return canvas }
                return view.subviews.lazy.compactMap { findCanvas($0) }.first
            }
            let canvas = try XCTUnwrap(findCanvas(sideView))
            let canvasRect = canvas.convert(canvas.bounds, to: sideView)
            XCTAssertGreaterThan(canvasRect.height, 100)
            XCTAssertTrue(sideView.bounds.insetBy(dx: -1, dy: -1).contains(canvasRect), "Compact windows must keep the board inside the visible workspace")
            try capture(sideView, name: "board-compact")
            workspace.popup.open("beat-1", workspace: workspace)
            let popup = try XCTUnwrap(workspace.popup.panel?.contentView)
            popup.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(popup, name: "popup")
        }
    }
}
#endif
