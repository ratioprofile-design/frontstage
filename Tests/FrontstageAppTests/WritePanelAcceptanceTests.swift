#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp
final class WritePanelAcceptanceTests: XCTestCase {
    func testEmbeddedWritePaperEditsHeadingsAndSplitsScenes() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            let workspace = Workspace(); workspace.loadCopy(try Project(data: Data(contentsOf: fixture)))
            let controller = workspace.scriptController("embedded-write")
            let root = ContinuousScriptEditor(workspace: workspace, controller: controller, width: workspace.paper.contentWidth, zoom: 1, theme: .warm)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; host.layoutSubtreeIfNeeded()
            defer { window.close() }
            let text = try XCTUnwrap(controller.textView as? ScreenplayTextView)
            XCTAssertTrue(text.isEditable); XCTAssertTrue(text.isSelectable); XCTAssertTrue(window.makeFirstResponder(text))
            XCTAssertEqual(workspace.paper, .a4)
            XCTAssertEqual(text.frame.width, workspace.paper.width, accuracy: 1)
            XCTAssertEqual(text.backgroundColor, WritingPaperTheme.warm.paper)
            let count = workspace.project.scenes.count
            let heading = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.setSelectedRange(NSRange(location: 0, length: heading.length - 1)); controller.selectionChanged()
            text.insertText("ext. park - night", replacementRange: text.selectedRange())
            XCTAssertEqual(workspace.project.scenes.first { $0.id == 1 }?.heading.location, "PARK")
            XCTAssertEqual(workspace.project.scenes.first { $0.id == 1 }?.heading.time, "NIGHT")
            XCTAssertEqual(workspace.project.scenes.count, count)
            var body: NSRange?
            text.attributedString().enumerateAttributes(in: NSRange(location: 0, length: text.attributedString().length)) { attributes, range, stop in
                if attributes[NSAttributedString.Key("FrontstageBeatOwner")] as? String == "beat-1", attributes[NSAttributedString.Key("FrontstageSceneHeading")] == nil { body = range; stop.pointee = true }
            }
            let bodyRange = try XCTUnwrap(body)
            text.setSelectedRange(NSRange(location: bodyRange.location + max(1, bodyRange.length / 2), length: 0))
            let notes = workspace.project.writingNotes(sceneID: 1)
            text.splitScene?()
            XCTAssertEqual(workspace.project.scenes.count, count + 1)
            XCTAssertEqual(workspace.project.writingNotes(sceneID: 1), notes)
            XCTAssertNil(workspace.errorMessage)
            workspace.undoProject(); XCTAssertEqual(workspace.project.scenes.count, count)
        }
    }
    func testTypingExistingHeadingAndTimeCompletionKeepsSceneIdentity() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            let workspace = Workspace(); workspace.loadCopy(try Project(data: Data(contentsOf: fixture)))
            let controller = workspace.scriptController("heading-typing")
            let coordinator = ContinuousScriptEditor.Coordinator(workspace, controller)
            let text = ScreenplayTextView(); text.isRichText = true; text.delegate = coordinator; text.screenplayController = controller; controller.textView = text
            coordinator.load(text)
            let count = workspace.project.scenes.count, originalBeat = workspace.whiteboard.beats.first { $0.sceneID == 1 }!.id
            let heading = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.setSelectedRange(NSRange(location: 0, length: heading.length - 1))
            controller.selectionChanged()
            text.insertText("ext. தமிழ் வீடு - n", replacementRange: text.selectedRange())
            XCTAssertEqual(workspace.project.scenes.first { $0.id == 1 }?.heading.location, "தமிழ் வீடு")
            XCTAssertEqual(workspace.project.scenes.first { $0.id == 1 }?.heading.time, "N")
            XCTAssertEqual(workspace.project.scenes.count, count)
            let partial = NSRange(location: text.selectedRange().location - 1, length: 1)
            var index = -1
            let choices = coordinator.textView(text, completions: [], forPartialWordRange: partial, indexOfSelectedItem: &index)
            XCTAssertEqual(choices, ["NIGHT"]); XCTAssertEqual(index, 0)
            text.insertText("NIGHT", replacementRange: partial)
            XCTAssertEqual(workspace.project.scenes.first { $0.id == 1 }?.heading.time, "NIGHT")
            XCTAssertEqual(workspace.whiteboard.beats.first { $0.sceneID == 1 }?.id, originalBeat)
            XCTAssertFalse(workspace.whiteboard.beats.first { $0.id == originalBeat }!.html.contains("தமிழ் வீடு"))
            XCTAssertNil(workspace.errorMessage)
        }
    }
    func testNotesMatchBrowserInkAndOpaqueBackgroundInBothAppearances() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for color in ["#fff4bc", "#d9edff", "#e1f4dc", "#f8dce7", "#ffffff"] {
                    let editor = NoteRichEditor(html: .constant("<p><strong>தமிழ் note</strong></p>"), color: color)
                    let scroll = NSScrollView(), text = NoteTextView(); scroll.documentView = text; text.appearance = NSAppearance(named: appearance)
                    text.textStorage?.setAttributedString(try NoteTextCodec.decode("<p><strong>தமிழ் note</strong></p>"))
                    editor.configure(scroll, text)
                    XCTAssertTrue(text.drawsBackground); XCTAssertTrue(scroll.drawsBackground)
                    XCTAssertEqual(text.backgroundColor.alphaComponent, 1)
                    XCTAssertEqual(scroll.backgroundColor, text.backgroundColor)
                    XCTAssertEqual(text.insertionPointColor, NoteRichEditor.ink)
                    XCTAssertEqual(text.typingAttributes[.foregroundColor] as? NSColor, NoteRichEditor.ink)
                    XCTAssertEqual(text.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NoteRichEditor.ink)
                    XCTAssertTrue(NoteTextCodec.encode(text.attributedString()).contains("<strong>"))
                }
            }
        }
    }
    func testLiveMarkdownFormattingAndSemanticRoundTrip() async throws {
        try await MainActor.run {
            let text = NSTextView(); text.string = "**Hello தமிழ்**"; text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
            LiveNoteFormatting.apply(to: text)
            XCTAssertEqual(text.string, "Hello தமிழ்")
            XCTAssertTrue(NoteTextCodec.encode(text.attributedString()).contains("<strong>"))
            let decoded = try NoteTextCodec.decode("<h3>தமிழ் heading</h3><p><strong>Bold</strong> and <code>code</code></p><blockquote>Quote</blockquote>")
            let saved = NoteTextCodec.encode(decoded)
            XCTAssertTrue(saved.contains("<h3>")); XCTAssertTrue(saved.contains("தமிழ் heading")); XCTAssertTrue(saved.contains("<blockquote>"))
            XCTAssertFalse(saved.contains("FSNOTE"))
        }
    }
    func testContinuousEditorCommitsInlineHeadingAndKeepsNotes() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            let workspace = Workspace(); workspace.loadCopy(try Project(data: Data(contentsOf: fixture)))
            let controller = workspace.scriptController("write-continuous")
            let coordinator = ContinuousScriptEditor.Coordinator(workspace, controller)
            let text = ScreenplayTextView(); controller.textView = text; text.screenplayController = controller
            coordinator.load(text)
            XCTAssertTrue(text.string.contains(workspace.project.scenes[0].heading.text))
            let notes = workspace.project.writingNotes(sceneID: 1)
            let headingRange = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.textStorage?.replaceCharacters(in: headingRange, with: "EXT. RIVER - NIGHT\n")
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
            XCTAssertEqual(workspace.project.scenes[0].heading.location, "RIVER")
            XCTAssertEqual(workspace.project.writingNotes(sceneID: 1), notes)
            workspace.edit("Omit") { try $0.setBeatOmitted("beat-1", omitted: true) }
            coordinator.load(text)
            XCTAssertFalse(text.string.contains("RIVER"))
            workspace.edit("Pull Out") { try $0.pullOutBeats(["beat-1"]) }
            XCTAssertEqual(workspace.project.pulledOutBeats.count, 1)
            workspace.undoProject()
            XCTAssertTrue(workspace.project.pulledOutBeats.isEmpty)
            workspace.edit("Repeated Scene") { project in
                try project.setBeatOmitted("beat-1", omitted: false)
                try project.editWhiteboard { board in
                    var repeated = board.beats.first { $0.id == "beat-1" }!
                    repeated.id = "repeat"; repeated.order = 100; board.beats.append(repeated)
                }
            }
            coordinator.load(text)
            let firstHeading = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.textStorage?.replaceCharacters(in: firstHeading, with: "EXT. PIER - NIGHT\n")
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
            XCTAssertEqual(workspace.project.scenes[0].heading.location, "PIER")
            XCTAssertEqual(text.string.components(separatedBy: "EXT. PIER - NIGHT").count - 1, 2)
        }
    }
    func testPanelsKeepEditorControllerAndTargetNotesAcrossSceneChanges() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            let workspace = Workspace(); workspace.loadCopy(try Project(data: Data(contentsOf: fixture))); workspace.mode = .edit
            let controller = workspace.scriptController("write-continuous")
            let view = NSHostingView(rootView: ScriptWritingWorkspace(workspace: workspace))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 950), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = view; view.layoutSubtreeIfNeeded()
            let oldSynopsis = workspace.whiteboard.beats.first { $0.id == "beat-1" }?.synopsis
            workspace.edit("Summary") { try $0.updateSceneSummary(1, summary: "தமிழ் summary") }
            XCTAssertEqual(workspace.whiteboard.beats.first { $0.id == "beat-1" }?.synopsis, oldSynopsis)
            var noteID = ""
            workspace.edit("Note") { noteID = try $0.addWritingNote(sceneID: 1, content: "<p>First scene</p>") }
            workspace.selectBoardBeat("beat-2")
            workspace.edit("Pending Note") { try $0.updateWritingNote(sceneID: 1, id: noteID, content: "<p>Still scene one</p>") }
            XCTAssertTrue(workspace.project.writingNotes(sceneID: 2).isEmpty)
            XCTAssertTrue(workspace.project.writingNotes(sceneID: 1).contains { $0.content.contains("Still scene one") })
            XCTAssertTrue(workspace.scriptController("write-continuous") === controller)
            workspace.undoProject(); XCTAssertTrue(workspace.project.writingNotes(sceneID: 1).contains { $0.content.contains("First scene") })
            workspace.redoProject(); XCTAssertTrue(workspace.project.writingNotes(sceneID: 1).contains { $0.content.contains("Still scene one") })
            window.setContentSize(NSSize(width: 800, height: 800)); view.layoutSubtreeIfNeeded()
            XCTAssertTrue(workspace.scriptController("write-continuous") === controller)
            window.orderOut(nil)
        }
    }
}
#endif
