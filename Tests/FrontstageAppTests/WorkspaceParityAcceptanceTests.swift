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
            func capture(_ view: NSView, name: String) throws {
                guard let output else { return }
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("mac-\(name).png"))
            }
            for (index, mode) in Workspace.Mode.allCases.enumerated() {
                workspace.mode = mode
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
            workspace.popup.open("beat-1", workspace: workspace)
            let popup = try XCTUnwrap(workspace.popup.panel?.contentView)
            popup.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            try capture(popup, name: "popup")
        }
    }
}
#endif
