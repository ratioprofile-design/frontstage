#if os(macOS)
import AppKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class WhiteboardPresentationAcceptanceTests: XCTestCase {
    func testDisplayModesRenderWithoutRecoloringTheProject() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            var project = try Project(data: Data(contentsOf: fixture))
            try project.editWhiteboard { board in
                board.beats[0].characters = ["MAYA", "DARA"]
                for index in board.beats.indices { board.beats[index].tags = ["Hope"] }
            }
            let workspace = Workspace(recoveryStore: nil); workspace.loadCopy(project)
            let view = NativeWhiteboard(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view; defer { window.close() }
            view.workspace = workspace; view.acceptModel(workspace)
            @MainActor func render() throws -> Data {
                let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: image)
                return try XCTUnwrap(image.representation(using: .png, properties: [:]))
            }
            let original = try render()
            view.colorMode = .characters; view.flowKind = "tags"; view.flowName = "Hope"
            let presentation = try render()
            XCTAssertNotEqual(original, presentation)
            XCTAssertEqual(workspace.project, project)
            XCTAssertFalse(workspace.history.canUndo)
            view.colorMode = .authored; view.flowKind = ""; view.flowName = ""
            XCTAssertEqual(try render(), original)
        }
    }
}
#endif
