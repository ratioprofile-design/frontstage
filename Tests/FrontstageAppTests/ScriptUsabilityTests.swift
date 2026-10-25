#if os(macOS)
import AppKit
import XCTest
@testable import FrontstageApp

final class ScriptUsabilityTests: XCTestCase {
    func testCuesDiscoverNamesAndCapitalizeWithoutTouchingDialogue() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let html = "<p class='sc-character'>kamal (V.O.)</p><p class='sc-dialogue'>Keep dialogue lowercase.</p><p class='sc-character'>அன்பு</p>"
            XCTAssertEqual(ScriptCueNames.characters(in: html), ["KAMAL", "அன்பு"])
            let text = NSTextView()
            text.textStorage?.setAttributedString(try ScreenplayTextCodec.decode(html))
            text.setSelectedRange(NSRange(location: 3, length: 0))
            ScriptCueNames.capitalize(in: text)
            XCTAssertTrue(text.string.hasPrefix("KAMAL (V.O.)"))
            XCTAssertTrue(text.string.contains("Keep dialogue lowercase."))
            XCTAssertEqual(text.selectedRange().location, 3)
            let workspace = Workspace(); workspace.addScene()
            workspace.updateScene(id: workspace.selectedSceneID!, html: html)
            XCTAssertTrue(workspace.screenplayCompletions[.character]?.contains("KAMAL") == true)
            XCTAssertTrue(workspace.project.characters.isEmpty)
        }
    }
}
#endif
