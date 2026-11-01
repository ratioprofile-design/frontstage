#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class TimelineInteractionTests: XCTestCase {
    func testWheelZoomClampsAndRejectsInvalidInput() async {
        await MainActor.run {
            let view = TimelineWheelView()
            var changes: [Double] = []
            view.changed = { changes.append($0) }
            view.applyZoom(deltaY: 20, localX: 400, scroll: nil)
            XCTAssertEqual(view.zoomScale, 60 * exp(0.24), accuracy: 0.0001)
            view.applyZoom(deltaY: 10_000, localX: 400, scroll: nil)
            XCTAssertEqual(view.zoomScale, 180)
            view.applyZoom(deltaY: -10_000, localX: 400, scroll: nil)
            XCTAssertEqual(view.zoomScale, 2)
            view.applyZoom(deltaY: .nan, localX: 400, scroll: nil)
            view.applyZoom(deltaY: 20, localX: .infinity, scroll: nil)
            XCTAssertEqual(changes.count, 3)
        }
    }

    func testWriterTimelineToggleKeepsHostedEditorAndSelection() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let suite = "dot-timeline-acceptance-" + UUID().uuidString, key = "frontstage-write-mini-timeline"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(false, forKey: key)
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
            let workspace = Workspace(recoveryStore: nil)
            workspace.loadCopy(try Project(data: Data(contentsOf: fixture))); workspace.mode = .edit
            let host = NSHostingView(rootView: ScriptWritingWorkspace(workspace: workspace).defaultAppStorage(defaults))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 950), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = host; window.orderFront(nil)
            defer { window.close() }
            @MainActor func settle() { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.1)); host.layoutSubtreeIfNeeded() }
            settle()
            let controller = workspace.scriptController("write-continuous")
            let text = try XCTUnwrap(controller.textView)
            window.makeFirstResponder(text)
            text.setSelectedRange(NSRange(location: min(8, text.string.utf16.count), length: 0))
            let selection = text.selectedRange(), original = workspace.project
            defaults.set(true, forKey: key); settle()
            XCTAssertTrue(controller.textView === text)
            XCTAssertEqual(text.selectedRange(), selection)
            defaults.set(false, forKey: key); settle()
            XCTAssertTrue(controller.textView === text)
            XCTAssertEqual(text.selectedRange(), selection)
            XCTAssertEqual(workspace.project, original)
            XCTAssertFalse(workspace.history.canUndo)
        }
    }
}
#endif
