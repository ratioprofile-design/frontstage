#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import FrontstageApp

final class NativeEditingTests: XCTestCase {
    func testImportLoadsTamilIntoTextKitWithoutChangingOriginalHTML() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let original = "<p>வணக்கம் <b>world</b></p>"
            let state = HTMLState(original)
            let binding = Binding(get: { state.value }, set: { state.value = $0 })
            let coordinator = RichTextEditor.Coordinator(html: binding)
            let text = NSTextView()
            coordinator.load(original, into: text)
            XCTAssertTrue(text.string.contains("வணக்கம்"))
            XCTAssertTrue(text.string.contains("world"))
            XCTAssertEqual(state.value, original)
            XCTAssertEqual(coordinator.lastHTML, original)
            let range = (text.string as NSString).range(of: "world")
            let font = try XCTUnwrap(text.textStorage?.attribute(.font, at: range.location,
                                                               effectiveRange: nil) as? NSFont)
            XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        }
    }

    func testNativeTextEditWritesHTMLWithTamilContent() async throws {
        await MainActor.run {
            _ = NSApplication.shared
            let state = HTMLState("<p>Old</p>")
            let binding = Binding(get: { state.value }, set: { state.value = $0 })
            let coordinator = RichTextEditor.Coordinator(html: binding)
            let text = NSTextView()
            coordinator.load(state.value, into: text)
            text.string = "புதிய காட்சி"
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
            let reloaded = NSTextView()
            coordinator.load(state.value, into: reloaded)
            XCTAssertTrue(reloaded.string.contains("புதிய காட்சி"))
            XCTAssertNotEqual(state.value, "<p>Old</p>")
        }
    }

    func testWorkspaceSelectionKeepsIndependentSceneEdits() async throws {
        await MainActor.run {
            let workspace = Workspace()
            workspace.addScene()
            let first = workspace.selectedSceneID!
            workspace.updateScene(id: first, title: "First scene", html: "<p>First</p>")
            workspace.addScene()
            let second = workspace.selectedSceneID!
            workspace.updateScene(id: second, title: "Second scene", html: "<p>Second</p>")
            workspace.selectedSceneID = first
            XCTAssertEqual(workspace.selectedScene?.title, "First scene")
            XCTAssertEqual(workspace.selectedScene?.html, "<p>First</p>")
            workspace.selectedSceneID = second
            XCTAssertEqual(workspace.selectedScene?.title, "Second scene")
            XCTAssertTrue(workspace.hasChanges)
        }
    }
}

@MainActor
private final class HTMLState {
    var value: String
    init(_ value: String) { self.value = value }
}
#endif
