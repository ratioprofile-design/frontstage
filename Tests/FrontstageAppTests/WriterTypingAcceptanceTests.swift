#if os(macOS)
import AppKit
import SwiftUI
import PDFKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class WriterTypingAcceptanceTests: XCTestCase {
    @MainActor private static func editor(_ html: String) throws -> (Workspace, ScreenplayEditorController, NSWindow, WritingTextView) {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
        var project = try Project(data: Data(contentsOf: url))
        // Isolate paragraph commands from the legacy fixture's mixed-case heading.
        for scene in project.scenes { try project.updateScene(id: scene.id, heading: SceneHeading(inline: scene.heading.inlineText)) }
        try project.editWhiteboard { board in board.beats[0].html = html }
        let workspace = Workspace(); workspace.loadCopy(project)
        let controller = workspace.scriptController("typing-acceptance")
        let host = NSHostingView(rootView: ContinuousScriptEditor(workspace: workspace, controller: controller, width: workspace.paper.contentWidth, zoom: 1))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.layoutSubtreeIfNeeded()
        let text = try XCTUnwrap(controller.textView as? WritingTextView)
        window.makeFirstResponder(text)
        let body = NSMaxRange((text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0)))
        text.setSelectedRange(NSRange(location: body, length: 0))
        return (workspace, controller, window, text)
    }
    @MainActor private static func press(_ text: WritingTextView, _ key: String, modifiers: NSEvent.ModifierFlags = []) throws {
        let code: UInt16 = key == "\t" ? 48 : 36
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: text.window!.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
        text.keyDown(with: event)
    }
    @MainActor private static func kind(_ text: NSTextView) -> ScreenplayElement {
        if text.selectedRange().location == text.string.utf16.count { return (text.typingAttributes[.screenplayElement] as? String).flatMap(ScreenplayElement.init(rawValue:)) ?? .action }
        return ScreenplayTextCodec.element(in: text.attributedString(), at: text.selectedRange().location)
    }
    func testActualTabReturnFlowCreatesNoSpacerParagraphs() async throws {
        try await MainActor.run {
            let (_, controller, window, text) = try Self.editor("<p class='sc-action'><br></p>"); defer { window.close() }
            let original = text.string, start = text.selectedRange().location
            try Self.press(text, "\t")
            XCTAssertEqual(text.string.debugDescription, original.debugDescription); XCTAssertEqual(text.selectedRange().location, start)
            XCTAssertEqual(Self.kind(text), .character)
            let style = try XCTUnwrap(text.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
            XCTAssertEqual(style.headIndent, controller.contentWidth * 0.33, accuracy: 0.1)
            text.insertText("கமல்", replacementRange: text.selectedRange())
            try Self.press(text, "\n"); XCTAssertEqual(Self.kind(text), .dialogue)
            let dialogueStart = text.selectedRange().location
            try Self.press(text, "\t"); XCTAssertEqual(Self.kind(text), .parenthetical)
            XCTAssertEqual(text.selectedRange().location, dialogueStart + 1)
            XCTAssertEqual((text.string as NSString).substring(with: NSRange(location: dialogueStart, length: 2)), "()")
            text.insertText("(custom delivery)", replacementRange: text.selectedRange())
            try Self.press(text, "\n"); XCTAssertEqual(Self.kind(text), .dialogue)
            let emptyStart = text.selectedRange().location, count = text.string.utf16.count
            try Self.press(text, "\n"); XCTAssertEqual(Self.kind(text), .character)
            XCTAssertEqual(text.selectedRange().location, emptyStart); XCTAssertEqual(text.string.utf16.count, count)
            XCTAssertFalse(text.string.contains("\n\n\n"))
        }
    }
    func testHostedParentheticalPairBackspaceAndProjectHistory() async throws {
        try await MainActor.run {
            let (workspace, controller, window, text) = try Self.editor("<p class='sc-dialogue'><br></p>")
            defer { window.close() }
            let start = text.selectedRange().location
            try Self.press(text, "\t")
            XCTAssertEqual(Self.kind(text), .parenthetical)
            XCTAssertEqual((text.string as NSString).substring(with: NSRange(location: start, length: 2)), "()")
            XCTAssertEqual(text.selectedRange().location, start + 1)
            XCTAssertTrue(controller.handleCommand(#selector(NSResponder.deleteBackward(_:)), in: text))
            XCTAssertEqual(Self.kind(text), .dialogue)
            XCTAssertFalse(text.string.contains("()"))
            let originalCount = try workspace.project.whiteboard().beats.count
            let id = try XCTUnwrap(workspace.project.whiteboard().beats.first?.id)
            workspace.duplicateBeat(id)
            XCTAssertEqual(try workspace.project.whiteboard().beats.count, originalCount + 1)
            let undo = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
            text.keyDown(with: undo)
            XCTAssertEqual(try workspace.project.whiteboard().beats.count, originalCount)
            let redo = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "Z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
            text.keyDown(with: redo)
            XCTAssertEqual(try workspace.project.whiteboard().beats.count, originalCount + 1)
        }
    }
    func testKeyboardCycleClearsOnlyAcceptedNameAndCreatesScene() async throws {
        try await MainActor.run {
            let html = "<p class='sc-character'>KAMAL KUMAR</p><p class='sc-dialogue'>First.</p><p class='sc-action'>Target</p>"
            let (workspace, controller, window, text) = try Self.editor(html); defer { window.close() }
            window.orderFront(nil)
            let range = (text.string as NSString).range(of: "Target")
            text.setSelectedRange(range); controller.format(.character)
            text.insertText("kam", replacementRange: text.selectedRange())
            try Self.press(text, "\t")
            XCTAssertTrue(text.string.contains("KAMAL KUMAR"))
            try Self.press(text, "\t"); XCTAssertEqual(Self.kind(text), .transition)
            let line = (text.string as NSString).paragraphRange(for: text.selectedRange())
            XCTAssertEqual((text.string as NSString).substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines), "")
            try Self.press(text, "\t"); XCTAssertEqual(Self.kind(text), .action)
            try Self.press(text, "\t"); XCTAssertEqual(Self.kind(text), .character)
            text.insertText("CUSTOM NAME", replacementRange: text.selectedRange())
            try Self.press(text, "\t"); XCTAssertEqual(Self.kind(text), .transition); XCTAssertTrue(text.string.contains("CUSTOM NAME"))
            let originalCount = workspace.whiteboard.beats.count
            try Self.press(text, "\n")
            XCTAssertEqual(workspace.whiteboard.beats.count, originalCount + 1)
            XCTAssertEqual(Self.kind(text), .sceneHeading)
            XCTAssertTrue(workspace.whiteboard.beats.contains { $0.html.contains("CUSTOM NAME") })
            try Self.press(text, "\n"); XCTAssertEqual(Self.kind(text), .action)
            text.insertText("தமிழ் action", replacementRange: text.selectedRange())
            try Self.press(text, "\n", modifiers: [.command]); XCTAssertEqual(Self.kind(text), .action)
            try Self.press(text, "\t"); text.insertText("ANOTHER", replacementRange: text.selectedRange())
            try Self.press(text, "\n"); XCTAssertEqual(Self.kind(text), .dialogue)
            text.insertText("Hello", replacementRange: text.selectedRange())
            try Self.press(text, "\n"); XCTAssertEqual(Self.kind(text), .character)
            try Self.press(text, "\n", modifiers: [.control]); XCTAssertEqual(Self.kind(text), .action)
        }
    }
    func testTransitionKeepsTrailingTextAndHeadingCanBeReused() async throws {
        try await MainActor.run {
            let (workspace, _, window, text) = try Self.editor("<p class='sc-transition'>CUT TO:</p><p class='sc-action'>Trailing Tamil தமிழ்</p>"); defer { window.close() }
            let oldCount = workspace.whiteboard.beats.count
            try Self.press(text, "\n")
            XCTAssertEqual(workspace.whiteboard.beats.count, oldCount + 1)
            let id = try XCTUnwrap(workspace.selectedBoardBeatID)
            XCTAssertTrue(try XCTUnwrap(workspace.whiteboard.beats.first { $0.id == id }).html.contains("Trailing Tamil தமிழ்"))
            XCTAssertEqual(Self.kind(text), .sceneHeading)
            try Self.press(text, "\n"); XCTAssertEqual(Self.kind(text), .action)
            XCTAssertEqual(workspace.whiteboard.beats.count, oldCount + 1)
        }
    }
    func testRepeatedTransitionReturnReusesEmptyHeading() async throws {
        try await MainActor.run {
            let (workspace, _, window, text) = try Self.editor("<p class='sc-transition'>CUT TO:</p>"); defer { window.close() }
            let oldCount = workspace.whiteboard.beats.count
            try Self.press(text, "\n")
            XCTAssertEqual(workspace.whiteboard.beats.count, oldCount + 1)
            let oldTransition = (text.string as NSString).range(of: "CUT TO:")
            text.setSelectedRange(NSRange(location: oldTransition.location, length: 0))
            try Self.press(text, "\n")
            XCTAssertEqual(workspace.whiteboard.beats.count, oldCount + 1)
            XCTAssertEqual(Self.kind(text), .sceneHeading)
        }
    }
    func testFilledActionTabPreservesWholeParagraphAndSelectionFormatting() async throws {
        try await MainActor.run {
            let (_, controller, window, text) = try Self.editor("<p class='sc-action'>She walks across the room.</p>"); defer { window.close() }
            let start = text.selectedRange().location
            text.setSelectedRange(NSRange(location: start + 3, length: 0))
            let count = text.string.components(separatedBy: "\n").count
            try Self.press(text, "\t")
            XCTAssertEqual(text.string.components(separatedBy: "\n").count, count + 1)
            XCTAssertTrue(text.string.contains("She walks across the room.\n"))
            XCTAssertEqual(Self.kind(text), .character)
            let before = text.string, caret = text.selectedRange()
            try Self.press(text, "\t")
            XCTAssertEqual(text.string, before); XCTAssertEqual(text.selectedRange(), caret)
            XCTAssertEqual(Self.kind(text), .transition)
            text.setSelectedRange(NSRange(location: start + 4, length: 5))
            controller.format(.dialogue)
            XCTAssertEqual(text.string, before); XCTAssertEqual(text.selectedRange(), NSRange(location: start + 4, length: 5))
            XCTAssertEqual(ScreenplayTextCodec.element(in: text.attributedString(), at: start), .dialogue)
        }
    }
    func testCharacterCompletionDoesNotPreviewOrMoveCaret() async throws {
        try await MainActor.run {
            let (_, controller, window, text) = try Self.editor("<p class='sc-character'>KAMAL KUMAR</p><p class='sc-dialogue'>First.</p><p class='sc-action'>Target</p>"); defer { window.close() }
            window.orderFront(nil)
            let target = (text.string as NSString).range(of: "Target")
            text.setSelectedRange(target); controller.format(.character)
            text.insertText("kam", replacementRange: text.selectedRange())
            let coordinator = try XCTUnwrap(text.delegate as? ContinuousScriptEditor.Coordinator)
            XCTAssertTrue(coordinator.headingSuggestions.isShown)
            XCTAssertEqual(text.selectedRange(), NSRange(location: target.location + 3, length: 0))
            XCTAssertEqual((text.string as NSString).substring(with: NSRange(location: target.location, length: 3)), "KAM")
            try Self.press(text, "\t"); XCTAssertEqual(Self.kind(text), .character)
            text.insertText(" (", replacementRange: text.selectedRange())
            XCTAssertTrue(coordinator.headingSuggestions.isShown)
            try Self.press(text, "\t")
            XCTAssertTrue(text.string.contains("KAMAL KUMAR (V.O.)"))
            try Self.press(text, "\n"); XCTAssertEqual(Self.kind(text), .dialogue)
        }
    }
    func testPDFDOCXMaterializeOnceAndPreserveAuthoredNames() async throws {
        try await MainActor.run {
            var project = Project(); let id = project.addScene()
            let html = "<p class='sc-character'>KAMAL</p><p class='sc-dialogue'>Hello.</p><p class='sc-action'>He waits.</p><p class='sc-character'>KAMAL (V.O.)</p><p class='sc-dialogue'>Again.</p><p class='sc-character'>KAMAL (CONT'D)</p><p class='sc-dialogue'>Manual label.</p>"
            try project.updateScene(id: id, html: html)
            let pdf = try ScreenplayPDF.render(project: project, paper: .a4)
            XCTAssertEqual(pdf.text.string.components(separatedBy: "(CONT'D)").count - 1, 2)
            XCTAssertTrue(PDFDocument(data: pdf.data)?.string?.contains("CONT'D") == true)
            let restored = try NSAttributedString(data: ScreenplayDOCX.render(project, paper: .a4), options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
            XCTAssertEqual(restored.string.components(separatedBy: "(CONT'D)").count - 1, 2)
            XCTAssertEqual(project.scenes[0].html, html)
        }
    }
    func testContinuationIsPresentationOnlyAndHeadingIsOnlyHighlight() async throws {
        try await MainActor.run {
            let html = "<p class='sc-character'>KAMAL</p><p class='sc-dialogue'>Hello.</p><p class='sc-action'>He waits.</p><p class='sc-character'>KAMAL (V.O.)</p><p class='sc-dialogue'>Again.</p><p class='sc-character'>JAY</p><p class='sc-dialogue'>Yes.</p><p class='sc-character'>KAMAL</p><p class='sc-dialogue'>Last.</p>"
            let (workspace, _, window, text) = try Self.editor(html); defer { window.close() }
            XCTAssertEqual(text.continuationTokens.count, 1)
            XCTAssertFalse(text.string.contains("CONT'D"))
            XCTAssertNotNil(DialoguePresentation.tokenRect(try XCTUnwrap(text.continuationTokens.first), in: text))
            let exported = DialoguePresentation.materialized(text.attributedString())
            XCTAssertEqual(exported.string.components(separatedBy: "(CONT'D)").count - 1, 1)
            let saved = try ScreenplayTextCodec.encode(text.attributedString())
            XCTAssertFalse(saved.contains("CONT'D")); XCTAssertFalse(saved.contains("ContinuationReservation"))
            text.revealBeat?("beat-1")
            let manager = try XCTUnwrap(text.layoutManager)
            XCTAssertNotNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil))
            let body = NSMaxRange((text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0)))
            XCTAssertNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: body, effectiveRange: nil))
            XCTAssertFalse(workspace.whiteboard.beats[0].html.contains("CONT'D"))
        }
    }
}
#endif
