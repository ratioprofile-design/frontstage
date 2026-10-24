#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class ScreenplayEditingTests: XCTestCase {
    func testTypedCompletionHandlesMultiwordNamesWithoutChangingText() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let text = NSTextView(), controller = ScreenplayEditorController()
            controller.textView = text
            text.textStorage?.setAttributedString(try ScreenplayTextCodec.decode("<p class='sc-character'>MARY JA</p>"))
            text.setSelectedRange(NSRange(location: 7, length: 0)); controller.selectionChanged()
            let coordinator = ScreenplayEditor.Coordinator(html: .constant(""), controller: controller, onError: { _ in })
            coordinator.suggestions = [.character: ["MARY JANE", "MAYA"], .transition: ["CUT TO:"]]
            var index = 0
            let suggestions = coordinator.textView(text, completions: [], forPartialWordRange: NSRange(location: 5, length: 2), indexOfSelectedItem: &index)
            XCTAssertEqual(suggestions, ["JANE"])
            XCTAssertEqual(text.string.trimmingCharacters(in: .newlines), "MARY JA")
            XCTAssertEqual(index, -1)
        }
    }

    func testSuggestionInsertionPreservesSurroundingScriptAndRespectsLocks() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let text = NSTextView(), controller = ScreenplayEditorController()
            text.isRichText = true; text.isEditable = true; text.allowsUndo = true
            controller.textView = text
            text.textStorage?.setAttributedString(try ScreenplayTextCodec.decode("<p class='sc-action'>Before.</p><p class='sc-action'>After.</p>"))
            text.setSelectedRange(NSRange(location: 2, length: 0))
            controller.insertCue("LENA", element: .character)
            XCTAssertTrue(text.string.contains("Before.\nLENA\nAfter."))
            let cue = (text.string as NSString).range(of: "LENA")
            XCTAssertEqual(ScreenplayTextCodec.element(in: text.attributedString(), at: cue.location), .character)
            controller.insertCue("MAYA", element: .character)
            XCTAssertFalse(text.string.contains("LENA"))
            XCTAssertTrue(text.string.contains("Before.\nMAYA\nAfter."))
            controller.insertCue("CUT TO:", element: .transition)
            XCTAssertTrue(text.string.contains("MAYA\nCUT TO:\nAfter."))
            let original = text.string
            text.isEditable = false; controller.insertCue("FADE OUT.", element: .transition)
            XCTAssertEqual(text.string, original)
        }
    }

    func testSemanticHTMLRoundTripPreservesTypesTamilAndEmphasis() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let html = "<div>" + ScreenplayElement.editable.map {
                "<div class='sc-line sc-\($0.rawValue)'><p>\($0.rawValue) <b>வணக்கம்</b> &amp; 🌕</p></div>"
            }.joined() + "</div>"
            let decoded = try ScreenplayTextCodec.decode(html)
            let encoded = ScreenplayTextCodec.encode(decoded)
            let restored = try ScreenplayTextCodec.decode(encoded)
            XCTAssertEqual(restored.string, decoded.string)
            XCTAssertFalse(restored.string.contains("FS"))
            for element in ScreenplayElement.editable {
                let range = (restored.string as NSString).range(of: element.rawValue)
                XCTAssertNotEqual(range.location, NSNotFound)
                if range.location != NSNotFound {
                    XCTAssertEqual(ScreenplayTextCodec.element(in: restored, at: range.location), element)
                }
                XCTAssertTrue(encoded.contains("sc-\(element.rawValue)"))
            }
            XCTAssertTrue(encoded.contains("வணக்கம்"))
            XCTAssertTrue(encoded.contains("&amp;"))
            XCTAssertTrue(encoded.contains("🌕"))
            XCTAssertTrue(encoded.contains("<b>"))
        }
    }

    func testWrappersDoNotInventBlankParagraphsAndUnclassifiedTextIsAction() async throws {
        try await MainActor.run {
            let text = try ScreenplayTextCodec.decode("<div><div><p>First</p><p>Second</p></div></div>")
            XCTAssertEqual(text.string.trimmingCharacters(in: .newlines), "First\nSecond")
            XCTAssertEqual(ScreenplayTextCodec.element(in: text, at: 0), .action)
            let character = try ScreenplayTextCodec.decode("<div class=sc-character>RANGA</div>")
            XCTAssertEqual(ScreenplayTextCodec.element(in: character, at: 0), .character)
        }
    }

    func testEmojiAtEndOfNativeParagraphEncodesWithoutUTF16Crash() async throws {
        await MainActor.run {
            let text = NSAttributedString(string: "A final 🌕", attributes: ScreenplayTypography.attributes(.action, width: 432))
            XCTAssertTrue(ScreenplayTextCodec.encode(text).contains("🌕"))
        }
    }

    func testManualParagraphNavigation() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let controller = ScreenplayEditorController(), text = NSTextView()
            text.isRichText = true; controller.textView = text
            text.textStorage?.setAttributedString(try ScreenplayTextCodec.decode("<p class='sc-action'>Action text</p>"))
            text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0)); controller.selectionChanged()
            XCTAssertTrue(controller.handleCommand(#selector(NSResponder.insertTab(_:)), in: text))
            XCTAssertEqual(controller.activeElement, .character)
            XCTAssertTrue(text.string.contains("Action text"))
            XCTAssertTrue(controller.handleCommand(#selector(NSResponder.insertNewline(_:)), in: text))
            XCTAssertEqual(controller.activeElement, .dialogue)
            text.insertText("Dialogue", replacementRange: text.selectedRange())
            XCTAssertTrue(controller.handleCommand(#selector(NSResponder.insertNewline(_:)), in: text))
            XCTAssertEqual(controller.activeElement, .action)
            controller.format(.parenthetical)
            XCTAssertTrue(controller.handleCommand(#selector(NSResponder.insertNewline(_:)), in: text))
            XCTAssertEqual(controller.activeElement, .dialogue)
        }
    }

    func testReturnTabAndSaveRetainDialogueSemantics() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let state = ScriptState("<div class='sc-character'>RANGA</div>")
            let binding = Binding(get: { state.html }, set: { state.html = $0 })
            let controller = ScreenplayEditorController()
            let coordinator = ScreenplayEditor.Coordinator(html: binding, controller: controller, onError: { _ in XCTFail() })
            let text = NSTextView()
            text.isRichText = true
            text.allowsUndo = true
            text.delegate = coordinator
            controller.textView = text
            coordinator.load(state.html, into: text)
            text.setSelectedRange(NSRange(location: 5, length: 0))
            controller.selectionChanged()
            XCTAssertEqual(controller.activeElement, .character)
            XCTAssertTrue(controller.handleCommand(#selector(NSResponder.insertNewline(_:)), in: text))
            XCTAssertEqual(controller.activeElement, .dialogue)
            text.insertText("வணக்கம்", replacementRange: text.selectedRange())
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
            XCTAssertTrue(state.html.contains("sc-dialogue"))
            let restored = try ScreenplayTextCodec.decode(state.html)
            let dialogue = (restored.string as NSString).range(of: "வணக்கம்")
            XCTAssertNotEqual(dialogue.location, NSNotFound)
            if dialogue.location != NSNotFound {
                XCTAssertEqual(ScreenplayTextCodec.element(in: restored, at: dialogue.location), .dialogue)
            }
            XCTAssertTrue(controller.handleCommand(#selector(NSResponder.insertTab(_:)), in: text))
            XCTAssertEqual(controller.activeElement, .parenthetical)
            XCTAssertTrue(controller.handleCommand(#selector(NSResponder.insertBacktab(_:)), in: text))
            XCTAssertEqual(controller.activeElement, .dialogue)
        }
    }

    func testLoadingSceneDoesNotRewriteSourceHTML() async throws {
        await MainActor.run {
            let original = "<div class='sc-dialogue' data-custom='keep'><b>Hello</b></div>"
            let state = ScriptState(original)
            let controller = ScreenplayEditorController()
            let coordinator = ScreenplayEditor.Coordinator(html: Binding(get: { state.html }, set: { state.html = $0 }),
                controller: controller, onError: { _ in XCTFail() })
            let text = NSTextView()
            text.delegate = coordinator
            coordinator.load(original, into: text)
            XCTAssertEqual(state.html, original)
        }
    }

    func testPastedRichTextKeepsDestinationDialogueElement() async throws {
        try await MainActor.run {
            let state = ScriptState("<div class='sc-dialogue'>Old dialogue</div>")
            let controller = ScreenplayEditorController()
            let coordinator = ScreenplayEditor.Coordinator(html: Binding(get: { state.html }, set: { state.html = $0 }),
                controller: controller, onError: { _ in XCTFail() })
            let text = NSTextView()
            text.isRichText = true
            text.delegate = coordinator
            controller.textView = text
            coordinator.load(state.html, into: text)
            text.setSelectedRange(NSRange(location: 0, length: 12))
            controller.selectionChanged()
            let clipboard = NSAttributedString(string: "Pasted dialogue", attributes: [.font: NSFont.systemFont(ofSize: 36)])
            text.insertText(clipboard, replacementRange: text.selectedRange())
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
            let restored = try ScreenplayTextCodec.decode(state.html)
            XCTAssertEqual(ScreenplayTextCodec.element(in: restored, at: 0), .dialogue)
            XCTAssertTrue(restored.string.contains("Pasted dialogue"))
        }
    }

    func testFormattingParticipatesInNativeUndo() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let controller = ScreenplayEditorController()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false)
            let text = NSTextView(frame: window.contentView!.bounds)
            text.isRichText = true
            text.allowsUndo = true
            window.contentView = text
            window.makeFirstResponder(text)
            controller.textView = text
            text.textStorage?.setAttributedString(try ScreenplayTextCodec.decode("<div class='sc-action'>Arrival</div>"))
            text.setSelectedRange(NSRange(location: 0, length: 0))
            let undo = try XCTUnwrap(text.undoManager)
            undo.removeAllActions()
            controller.format(.dialogue)
            XCTAssertEqual(ScreenplayTextCodec.element(in: text.attributedString(), at: 0), .dialogue)
            XCTAssertTrue(undo.canUndo)
            undo.undo()
            XCTAssertEqual(ScreenplayTextCodec.element(in: text.attributedString(), at: 0), .action)
        }
    }
}

@MainActor
private final class ScriptState {
    var html: String
    init(_ html: String) { self.html = html }
}
#endif
