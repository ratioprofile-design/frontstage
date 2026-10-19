#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class ScreenplayEditingTests: XCTestCase {
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
}

@MainActor
private final class ScriptState {
    var html: String
    init(_ html: String) { self.html = html }
}
#endif
