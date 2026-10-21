#if os(macOS)
import AppKit
import SwiftUI
import PDFKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class WhiteboardAcceptanceTests: XCTestCase {
    func testDraggingSelectedStandaloneCardsMovesBothAndUndoRestoresThem() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let workspace = Workspace()
            workspace.whiteboardRipple = false
            workspace.addWhiteboardBeat(position: .init(x: 50, y: 70))
            let a = try XCTUnwrap(workspace.selectedBoardBeatID)
            workspace.addWhiteboardBeat(position: .init(x: 400, y: 70))
            let b = try XCTUnwrap(workspace.selectedBoardBeatID)
            workspace.popup.close()
            let original = workspace.whiteboard
            let canvas = NativeWhiteboard(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
            canvas.workspace = workspace; canvas.board = original; canvas.selection = [a, b]
            let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = canvas
            defer { window.close() }
            let rect = try XCTUnwrap(WhiteboardLayout(original).beatRects[a])
            @MainActor func mouse(_ type: NSEvent.EventType, dx: Double) throws -> NSEvent {
                let point = canvas.convert(NSPoint(x: rect.center.x + dx, y: rect.center.y), to: nil)
                return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            }
            canvas.mouseDown(with: try mouse(.leftMouseDown, dx: 0))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, dx: 30))
            canvas.mouseUp(with: try mouse(.leftMouseUp, dx: 30))
            XCTAssertNil(workspace.errorMessage)
            for block in original.blocks {
                XCTAssertEqual(workspace.whiteboard.blocks.first { $0.id == block.id }?.position.x, block.position.x + 30)
            }
            workspace.undoProject()
            XCTAssertEqual(workspace.whiteboard, original)
        }
    }
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
                _ = try project.addStoryMilestone(title: "Act I: The invitation", page: 0)
                _ = try project.addStoryMilestone(title: "Act II: The consequence", page: 3)
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
            let group = try XCTUnwrap(workspace.whiteboard.blocks.last?.id)
            workspace.edit("Ungroup") { try $0.ungroupBoardBlocks([group]) }
            XCTAssertTrue(workspace.whiteboard.blocks.allSatisfy { $0.parentID == nil })
            workspace.undoProject(); XCTAssertEqual(workspace.project, restored)
            workspace.popup.close()
            let view = NSHostingView(rootView: WhiteboardWorkspace(workspace: workspace))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1267, height: 720), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = view; view.frame = NSRect(x: 0, y: 0, width: 1267, height: 720)
            view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            @MainActor func canvas(in parent: NSView) -> NativeWhiteboard? {
                if let result = parent as? NativeWhiteboard { return result }
                return parent.subviews.lazy.compactMap { canvas(in: $0) }.first
            }
            let native = try XCTUnwrap(canvas(in: view))
            let children = try XCTUnwrap(native.accessibilityChildren() as? [NSAccessibilityElement])
            XCTAssertTrue(children.contains { $0.accessibilityLabel() == "The invitation" })
            native.selection = [first]
            let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125))
            native.keyDown(with: down)
            XCTAssertEqual(workspace.selectedBoardBeatID, second)
            let sourceBlock = try XCTUnwrap(workspace.whiteboard.beats.first { $0.id == first }?.blockID)
            let blockRect = try XCTUnwrap(WhiteboardLayout(workspace.whiteboard).blockRects[sourceBlock])
            let originalWidth = try XCTUnwrap(workspace.whiteboard.blocks.first { $0.id == sourceBlock }?.width)
            @MainActor func mouse(_ type: NSEvent.EventType, x: Double) throws -> NSEvent {
                let point = native.convert(NSPoint(x: x, y: blockRect.y + 10), to: nil)
                return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            }
            native.mouseDown(with: try mouse(.leftMouseDown, x: blockRect.maxX - 2))
            native.mouseDragged(with: try mouse(.leftMouseDragged, x: blockRect.maxX + 63))
            native.mouseUp(with: try mouse(.leftMouseUp, x: blockRect.maxX + 63))
            XCTAssertEqual(workspace.whiteboard.blocks.first { $0.id == sourceBlock }?.width, originalWidth + 65)
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
