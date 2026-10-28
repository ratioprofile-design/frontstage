#if os(macOS)
import AppKit
import XCTest
import SwiftUI
import FrontstageCore
@testable import FrontstageApp

final class ScriptAnnotationAcceptanceTests: XCTestCase {
    func testAnnotationsSurviveNativeCodecAndStayOutOfDefaultExports() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let old = UserDefaults.standard.object(forKey: "dot_export_highlights")
            defer { if let old { UserDefaults.standard.set(old, forKey: "dot_export_highlights") } else { UserDefaults.standard.removeObject(forKey: "dot_export_highlights") } }
            UserDefaults.standard.set(false, forKey: "dot_export_highlights")
            let html = "<p class='sc-action'>A <span data-dot-breakdown='req-1' data-dot-category='VEHICLES'><span data-dot-highlight='Yellow'><b>red car</b></span></span> waits. தமிழ்</p>"
            let text = try ScreenplayTextCodec.decode(html)
            XCTAssertEqual(text.string.trimmingCharacters(in: .newlines), "A red car waits. தமிழ்")
            let range = (text.string as NSString).range(of: "red car")
            XCTAssertEqual(text.attribute(.screenplayBreakdown, at: range.location, effectiveRange: nil) as? String, "req-1")
            XCTAssertEqual(text.attribute(.screenplayHighlight, at: range.location, effectiveRange: nil) as? String, "Yellow")
            XCTAssertNotNil(text.attribute(.backgroundColor, at: range.location, effectiveRange: nil))
            let darkView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
            darkView.textStorage?.setAttributedString(text); darkView.textColor = .white
            ScreenplayTextCodec.refreshHighlightInk(darkView)
            XCTAssertEqual(darkView.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: range.location, effectiveRange: nil) as? NSColor, .black)
            let saved = ScreenplayTextCodec.encode(text)
            XCTAssertTrue(saved.contains("data-dot-breakdown=\"req-1\"")); XCTAssertTrue(saved.contains("data-dot-highlight=\"Yellow\"")); XCTAssertFalse(saved.contains("INLINE"))
            let printText = try ScreenplayTextCodec.decode(saved, printing: true)
            XCTAssertNil(printText.attribute(.backgroundColor, at: range.location, effectiveRange: nil))
            UserDefaults.standard.set(true, forKey: "dot_export_highlights")
            let highlighted = try ScreenplayTextCodec.decode(saved, printing: true)
            XCTAssertNotNil(highlighted.attribute(.backgroundColor, at: range.location, effectiveRange: nil))
            let live = try ScreenplayTextCodec.decode(saved, printing: true, showAnnotations: true)
            XCTAssertNotNil(live.attribute(.backgroundColor, at: range.location, effectiveRange: nil))
        }
    }
    func testPreferencesHostBothTabs() async throws {
        await MainActor.run {
            _ = NSApplication.shared
            let workspace = Workspace(recoveryStore: nil)
            let host = NSHostingView(rootView: DOTPreferences(workspace: workspace))
            host.frame = NSRect(x: 0, y: 0, width: 820, height: 700)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.width, 0)
        }
    }
}
#endif
