#if os(macOS)
import AppKit
import SwiftUI
import PDFKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class WhiteboardAcceptanceTests: XCTestCase {
    func testGroupedStoryPopupSplitUndoReopenAndPDF() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let workspace = Workspace()
            var first = "", second = "", last = ""
            workspace.edit("Create story") { project in
                first = try project.addBoardBeat(position: .init(x: 60, y: 60), title: "The invitation")
                let block = try project.whiteboard().beats[0].blockID
                second = try project.addBoardBeat(blockID: block, title: "The decision")
                last = try project.addBoardBeat(position: .init(x: 400, y: 85), title: "The consequence")
                try project.updateBoardBeat(first) { $0.html = "<div class=\"sc-action\">An invitation arrives.</div>"; $0.color = "#39798c" }
                try project.updateBoardBeat(second) { $0.html = "<div class=\"sc-dialogue\">தமிழ் — the choice remains.</div>"; $0.color = "#ab7d22" }
                try project.updateBoardBeat(last) { $0.html = "<div class=\"sc-action\">The door closes.</div>"; $0.mustBeCaused = true }
                try project.connectBoardBeats(cause: second, effect: last)
                try project.groupBoardBlocks(Set(try project.whiteboard().blocks.map(\.id)), name: "Act I: The accident")
                try project.editWhiteboard { board in
                    board.layers.insert(BoardLayer(name: "Taylor's backstory"), at: 1)
                    try board.resolveCauses()
                }
            }
            workspace.selectBoardBeat(second)
            workspace.popup.open(second, workspace: workspace)
            defer { workspace.popup.close() }
            workspace.popup.panel?.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let editor = try XCTUnwrap(workspace.popup.controller?.textView)
            editor.insertText("A promise. ", replacementRange: NSRange(location: 0, length: 0))
            editor.setSelectedRange(NSRange(location: 11, length: 0))
            let beforeSplit = workspace.project
            workspace.splitBoardBeat(second, controller: workspace.popup.controller)
            XCTAssertEqual(try workspace.project.whiteboard().beats.count, 4)
            workspace.undoProject()
            XCTAssertEqual(workspace.project, beforeSplit)
            workspace.redoProject()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("acceptance.frontstage")
            try workspace.project.save(to: file)
            let restored = try Project.load(from: file)
            XCTAssertEqual(restored, workspace.project)
            XCTAssertTrue(try restored.whiteboard().issues.isEmpty)
            let pdf = try XCTUnwrap(PDFDocument(data: ScreenplayPDF.render(project: restored, paper: .letter).data))
            XCTAssertTrue(pdf.string?.contains("A promise.") == true)
            XCTAssertTrue(pdf.string?.contains("The door closes.") == true)
            workspace.popup.close()
            let view = NSHostingView(rootView: WhiteboardWorkspace(workspace: workspace))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1267, height: 720), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = view; view.frame = NSRect(x: 0, y: 0, width: 1267, height: 720)
            view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            if let path = ProcessInfo.processInfo.environment["FRONTSTAGE_TEST_ARTIFACTS"] {
                let output = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("whiteboard-acceptance.png"))
                try restored.encoded().write(to: output.appendingPathComponent("whiteboard-acceptance.frontstage"))
                try pdf.dataRepresentation()?.write(to: output.appendingPathComponent("whiteboard-acceptance.pdf"))
            }
        }
    }
}
#endif
