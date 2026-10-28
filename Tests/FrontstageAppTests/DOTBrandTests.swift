#if os(macOS)
import AppKit
import XCTest
@testable import FrontstageApp
final class DOTBrandTests: XCTestCase {
    func testIconSelectionUsesSystemAppearanceNotPaperTheme() async throws {
        try await MainActor.run {
            XCTAssertEqual(DOTTheme.iconResource(for: try XCTUnwrap(NSAppearance(named: .aqua))), "dot-app-light")
            XCTAssertEqual(DOTTheme.iconResource(for: try XCTUnwrap(NSAppearance(named: .darkAqua))), "dot-app-dark")
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            for resource in ["dot-app-light.png","dot-app-dark.png","wordmark-light.png","wordmark-dark.png"] {
                XCTAssertNotNil(NSImage(contentsOf: root.appendingPathComponent("Resources/Brand/" + resource)))
            }
        }
    }
}
#endif
