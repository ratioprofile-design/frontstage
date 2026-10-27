#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class WriteNavigationEditingTests: XCTestCase {
    @MainActor private static func fixture() throws -> Project {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
        return try Project(data: Data(contentsOf: url))
    }
    @MainActor private static func editor(_ project: Project) throws -> (Workspace, ScreenplayEditorController, NSWindow, WritingTextView) {
        _ = NSApplication.shared
        let workspace = Workspace(); workspace.loadCopy(project)
        let controller = workspace.scriptController("navigation-test")
        let host = NSHostingView(rootView: ContinuousScriptEditor(workspace: workspace, controller: controller, width: workspace.paper.contentWidth, zoom: 1))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.layoutSubtreeIfNeeded()
        let text = try XCTUnwrap(controller.textView as? WritingTextView)
        XCTAssertTrue(window.makeFirstResponder(text))
        return (workspace, controller, window, text)
    }
    func testHostedHeadingReplacementKeepsDraftCaretAndIdentity() async throws {
        try await MainActor.run {
            let (workspace, _, window, text) = try Self.editor(Self.fixture()); defer { window.close() }
            let count = workspace.project.scenes.count, notes = workspace.project.writingNotes(sceneID: 1)
            let range = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.setSelectedRange(NSRange(location: 0, length: range.length - 1))
            var typed = ""
            for character in "ext. தமிழ் வீடு - n" {
                typed += String(character)
                text.insertText(String(character), replacementRange: text.selectedRange())
                XCTAssertEqual((text.string as NSString).substring(to: typed.utf16.count), typed.uppercased())
                XCTAssertEqual(text.selectedRange(), NSRange(location: typed.utf16.count, length: 0))
                XCTAssertEqual(workspace.project.scenes.count, count)
                XCTAssertEqual(text.attributedString().attribute(ScriptHeadingEditing.heading, at: 0, effectiveRange: nil) as? String, "1")
            }
            let partial = NSRange(location: typed.utf16.count - 1, length: 1)
            text.insertText("night", replacementRange: partial)
            XCTAssertEqual(workspace.project.scenes[0].heading.time, "NIGHT")
            let location = (text.string as NSString).range(of: "தமிழ் வீடு")
            text.setSelectedRange(location); text.insertText("புது வீடு", replacementRange: location)
            XCTAssertEqual(workspace.project.scenes[0].heading.location, "புது வீடு")
            XCTAssertEqual(workspace.project.writingNotes(sceneID: 1), notes)
            XCTAssertEqual(workspace.whiteboard.beats.first { $0.id == "beat-1" }?.sceneID, 1)
            XCTAssertNil(workspace.errorMessage)
        }
    }
    func testStaleHeadingTypingAttributesCannotReplaceSluglineFromBody() async throws {
        try await MainActor.run {
            var project = try Self.fixture()
            for scene in project.scenes { try project.updateScene(id: scene.id, heading: SceneHeading(inline: scene.heading.inlineText)) }
            let (workspace, _, window, text) = try Self.editor(project); defer { window.close() }
            let headings = workspace.project.scenes.map(\.heading)
            let first = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            let bodyStart = NSMaxRange(first), before = text.string
            text.setSelectedRange(NSRange(location: bodyStart, length: 0))
            // Reproduce TextKit retaining the preceding paragraph's identity.
            text.typingAttributes = text.attributedString().attributes(at: 0, effectiveRange: nil)
            for character in "ordinary body text. " { text.insertText(String(character), replacementRange: text.selectedRange()) }
            XCTAssertEqual(workspace.project.scenes.map(\.heading), headings)
            XCTAssertTrue(text.string.hasPrefix((before as NSString).substring(with: first) + "ordinary body text. "))
            XCTAssertNil(text.attributedString().attribute(ScriptHeadingEditing.heading, at: bodyStart, effectiveRange: nil))
            XCTAssertEqual(ScreenplayTextCodec.element(in: text.attributedString(), at: bodyStart), .action)
            XCTAssertEqual(text.selectedRange().location, bodyStart + "ordinary body text. ".utf16.count)
        }
    }
    func testBodyPasteAndEndOfDocumentTypingDoNotCarryHeadingIdentity() async throws {
        try await MainActor.run {
            var project = try Self.fixture()
            for scene in project.scenes { try project.updateScene(id: scene.id, heading: SceneHeading(inline: scene.heading.inlineText)) }
            let (workspace, controller, window, text) = try Self.editor(project); defer { window.close() }
            let headings = workspace.project.scenes.map(\.heading)
            let bodyStart = NSMaxRange((text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0)))
            var paste = text.attributedString().attributes(at: bodyStart, effectiveRange: nil)
            paste[ScriptHeadingEditing.heading] = "1"
            text.setSelectedRange(NSRange(location: bodyStart, length: 0))
            text.insertText(NSAttributedString(string: "Pasted body. ", attributes: paste), replacementRange: text.selectedRange())
            XCTAssertEqual(workspace.project.scenes.map(\.heading), headings)
            text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
            text.typingAttributes = text.attributedString().attributes(at: 0, effectiveRange: nil)
            text.insertText("Final body paragraph.", replacementRange: text.selectedRange())
            XCTAssertEqual(workspace.project.scenes.map(\.heading), headings)
            XCTAssertTrue(text.string.hasSuffix("Final body paragraph."))
            XCTAssertNil(text.typingAttributes[ScriptHeadingEditing.heading])
            XCTAssertEqual(try Project(data: workspace.project.encoded()).scenes.map(\.heading), headings)
            text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
            controller.toggleInlineStyle("bold")
            XCTAssertEqual(workspace.project.scenes.map(\.heading), headings)
            XCTAssertEqual(workspace.project.scenes.count, project.scenes.count)
        }
    }
    func testBodyCompositionDoesNotInheritSluglineIdentity() async throws {
        try await MainActor.run {
            var project = try Self.fixture()
            for scene in project.scenes { try project.updateScene(id: scene.id, heading: SceneHeading(inline: scene.heading.inlineText)) }
            let (workspace, _, window, text) = try Self.editor(project); defer { window.close() }
            let headings = workspace.project.scenes.map(\.heading)
            let bodyStart = NSMaxRange((text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0)))
            text.setSelectedRange(NSRange(location: bodyStart, length: 0))
            text.typingAttributes = text.attributedString().attributes(at: 0, effectiveRange: nil)
            text.setMarkedText("தமிழ்", selectedRange: NSRange(location: "தமிழ்".utf16.count, length: 0), replacementRange: text.selectedRange())
            XCTAssertTrue(text.hasMarkedText())
            text.unmarkText()
            let coordinator = try XCTUnwrap(text.delegate as? ContinuousScriptEditor.Coordinator)
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
            XCTAssertEqual(workspace.project.scenes.map(\.heading), headings)
            XCTAssertNil(text.attributedString().attribute(ScriptHeadingEditing.heading, at: bodyStart, effectiveRange: nil))
            XCTAssertTrue(workspace.whiteboard.beats.first(where: { $0.id == "beat-1" })?.html.contains("தமிழ்") == true)
        }
    }
    func testHeadingDeletePasteAndReturnDoNotConsumeSceneBody() async throws {
        try await MainActor.run {
            let (workspace, _, window, text) = try Self.editor(Self.fixture()); defer { window.close() }
            let count = workspace.project.scenes.count, originalBody = workspace.whiteboard.beats.first { $0.id == "beat-1" }!.html
            let bodyText = try ScreenplayTextCodec.decode(originalBody).string
            var heading = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.setSelectedRange(NSRange(location: 0, length: heading.length - 1)); text.insertText("", replacementRange: text.selectedRange())
            XCTAssertTrue(workspace.project.pulledOutBeats.isEmpty)
            XCTAssertEqual(workspace.project.scenes.count, count)
            text.insertText("ext. park - night", replacementRange: text.selectedRange())
            heading = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.setSelectedRange(heading)
            text.insertText("int. bridge\n- day", replacementRange: heading)
            XCTAssertTrue(text.string.hasPrefix("INT. BRIDGE - DAY\n"))
            XCTAssertEqual(workspace.project.scenes.count, count)
            XCTAssertEqual(try ScreenplayTextCodec.decode(workspace.whiteboard.beats.first { $0.id == "beat-1" }!.html).string, bodyText)
            let delegate = try XCTUnwrap(text.delegate as? ContinuousScriptEditor.Coordinator)
            text.setSelectedRange(NSRange(location: 5, length: 0))
            XCTAssertTrue(delegate.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            let bodyStart = NSMaxRange((text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0)))
            XCTAssertEqual(text.selectedRange().location, bodyStart)
            XCTAssertNil(text.typingAttributes[ScriptHeadingEditing.heading])
            XCTAssertEqual(workspace.project.scenes.count, count)
        }
    }
    func testRepeatedHeadingUpdatesInPlaceAndKeepsBothOccurrences() async throws {
        try await MainActor.run {
            var project = try Self.fixture()
            try project.editWhiteboard { board in
                var repeated = board.beats[0]; repeated.id = "repeat"; repeated.order = 10; board.beats.append(repeated)
            }
            let (workspace, _, window, text) = try Self.editor(project); defer { window.close() }
            let first = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.setSelectedRange(NSRange(location: 0, length: first.length - 1))
            for character in "ext. pier - " { text.insertText(String(character), replacementRange: text.selectedRange()) }
            XCTAssertTrue(text.string.hasPrefix("EXT. PIER - \n"), "The trailing separator must survive while typing")
            XCTAssertEqual(text.selectedRange().location, "EXT. PIER - ".utf16.count)
            text.insertText("night", replacementRange: text.selectedRange())
            XCTAssertEqual(text.string.components(separatedBy: "EXT. PIER - NIGHT").count - 1, 2)
            let later = (text.string as NSString).range(of: "EXT. PIER - NIGHT", options: .backwards)
            text.setSelectedRange(later); text.insertText("int. hall - day", replacementRange: later)
            XCTAssertEqual(workspace.project.scenes[0].heading.location, "HALL")
            XCTAssertEqual(text.string.components(separatedBy: "INT. HALL - DAY").count - 1, 2)
            XCTAssertEqual(workspace.project.scenes.count, 2)
        }
    }
    func testNavigationCentersTheActualHeadingAndPreservesHorizontalScroll() async throws {
        try await MainActor.run {
            var project = try Self.fixture()
            try project.editWhiteboard { board in
                for index in board.beats.indices { board.beats[index].html = String(repeating: "<p class='sc-action'>Long screenplay paragraph.</p>", count: 120) }
            }
            let (workspace, _, window, text) = try Self.editor(project); defer { window.close() }
            let scroll = try XCTUnwrap(text.enclosingScrollView), canvas = try XCTUnwrap(scroll.documentView as? WritingCanvasView)
            canvas.layoutPaper()
            let horizontal = scroll.contentView.bounds.minX
            text.revealBeat?("beat-2")
            XCTAssertEqual(workspace.selectedBoardBeatID, "beat-2")
            XCTAssertTrue(window.firstResponder === text)
            let range = (text.string as NSString).paragraphRange(for: text.selectedRange())
            XCTAssertEqual(text.attributedString().attribute(ScriptHeadingEditing.heading, at: range.location, effectiveRange: nil) as? String, "2")
            let manager = try XCTUnwrap(text.layoutManager), container = try XCTUnwrap(text.textContainer)
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.y += text.textContainerOrigin.y; rect.origin.x += text.textContainerOrigin.x
            let actual = canvas.convert(rect, from: text).midY
            XCTAssertEqual(actual, scroll.contentView.bounds.midY, accuracy: 2)
            XCTAssertEqual(scroll.contentView.bounds.minX, horizontal, accuracy: 0.1)
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
            text.revealBeat?("beat-1")
            XCTAssertEqual(workspace.selectedBoardBeatID, "beat-1")
            XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 2)
        }
    }
    func testReloadKeepsIncompleteHeadingAndRelativeSelection() async throws {
        try await MainActor.run {
            let (workspace, controller, window, text) = try Self.editor(Self.fixture()); defer { window.close() }
            let heading = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.setSelectedRange(NSRange(location: 0, length: heading.length - 1))
            text.insertText("ext. தமிழ் வீடு - ", replacementRange: text.selectedRange())
            let before = text.selectedRange(), draft = text.string
            let coordinator = try XCTUnwrap(text.delegate as? ContinuousScriptEditor.Coordinator)
            controller.typography.fontSize *= 1.1; coordinator.load(text)
            XCTAssertEqual(text.selectedRange(), before)
            XCTAssertEqual(text.string, draft)
            XCTAssertEqual(workspace.project.scenes.count, 2)
            text.insertText("night", replacementRange: text.selectedRange())
            XCTAssertEqual(workspace.project.scenes[0].heading.time, "NIGHT")
            let saved = try Project(data: workspace.project.encoded())
            XCTAssertEqual(saved.scenes[0].heading.time, "NIGHT")
            workspace.undoProject(); XCTAssertNotEqual(workspace.project.scenes[0].heading.time, "NIGHT")
            workspace.redoProject(); XCTAssertEqual(workspace.project.scenes[0].heading.time, "NIGHT")
        }
    }
    func testCompositionDefersNavigationAndCapitalizationPreservesSelection() async throws {
        try await MainActor.run {
            let (workspace, _, window, text) = try Self.editor(Self.fixture()); defer { window.close() }
            text.setSelectedRange(NSRange(location: 5, length: 0))
            text.setMarkedText("தமிழ்", selectedRange: NSRange(location: 5, length: 0), replacementRange: text.selectedRange())
            XCTAssertTrue(text.hasMarkedText())
            text.revealBeat?("beat-2")
            XCTAssertNotEqual(workspace.selectedBoardBeatID, "beat-2")
            text.unmarkText()
            let coordinator = try XCTUnwrap(text.delegate as? ContinuousScriptEditor.Coordinator)
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
            XCTAssertEqual(workspace.selectedBoardBeatID, "beat-2")
            XCTAssertEqual(workspace.project.scenes.count, 2)
            let plain = NSTextView()
            plain.textStorage?.setAttributedString(NSAttributedString(string: "ext. straße - day", attributes: [.screenplayElement: "slugline"]))
            plain.setSelectedRange(NSRange(location: 5, length: 6))
            ScriptCueNames.capitalize(in: plain)
            XCTAssertEqual(plain.string, "EXT. STRASSE - DAY")
            XCTAssertEqual(plain.selectedRange(), NSRange(location: 5, length: 7))
        }
    }
    func testHeadingSuggestionsAcceptExplicitlyWithoutMovingCaretWhileTyping() async throws {
        try await MainActor.run {
            let (workspace, _, window, text) = try Self.editor(Self.fixture()); defer { window.close() }
            window.orderFront(nil)
            let heading = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.setSelectedRange(NSRange(location: 0, length: heading.length - 1))
            text.insertText("ext. park - n", replacementRange: text.selectedRange())
            let coordinator = try XCTUnwrap(text.delegate as? ContinuousScriptEditor.Coordinator)
            XCTAssertTrue(coordinator.headingSuggestions.isShown)
            XCTAssertTrue(text.string.hasPrefix("EXT. PARK - N\n"), "Suggestions must not insert a preview into the paper")
            XCTAssertEqual(text.selectedRange(), NSRange(location: "EXT. PARK - N".utf16.count, length: 0))
            XCTAssertTrue(coordinator.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            XCTAssertEqual(workspace.project.scenes[0].heading.time, "NIGHT")
            XCTAssertFalse(coordinator.headingSuggestions.isShown)
            XCTAssertTrue(text.string.hasPrefix("EXT. PARK - NIGHT\n"))
            XCTAssertTrue(coordinator.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            XCTAssertEqual(text.selectedRange().location, "EXT. PARK - NIGHT\n".utf16.count)
            let updated = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            text.setSelectedRange(NSRange(location: 0, length: updated.length - 1))
            text.insertText("EXT. PARK - ", replacementRange: text.selectedRange())
            XCTAssertTrue(coordinator.headingSuggestions.isShown, "Show day/night choices after the separator without inserting one")
            XCTAssertTrue(text.string.hasPrefix("EXT. PARK - \n"))
            XCTAssertTrue(coordinator.textView(text, doCommandBy: #selector(NSResponder.insertTab(_:))))
            XCTAssertEqual(workspace.project.scenes[0].heading.time, "DAY")
        }
    }
}
#endif
