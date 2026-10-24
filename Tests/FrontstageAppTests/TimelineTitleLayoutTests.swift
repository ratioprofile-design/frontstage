#if os(macOS)
import AppKit
import XCTest
@testable import FrontstageApp

final class TimelineTitleLayoutTests: XCTestCase {
    func testCompleteLinesAndFullTitleMeasurement() async throws {
        await MainActor.run {
            _ = NSApplication.shared
            let title = "The nurse explains why the patient must wait for the family — மருத்துவமனையில் காத்திருக்கிறார்கள்"
            for width in [40.0, 80.0, 160.0] {
                let full = TimelineTitleLayout.height(title, width: width, lines: nil)
                let two = TimelineTitleLayout.height(title, width: width, lines: 2)
                let five = TimelineTitleLayout.height(title, width: width, lines: 5)
                XCTAssertGreaterThan(full, two)
                XCTAssertGreaterThanOrEqual(five, two)
                XCTAssertGreaterThanOrEqual(full, five)
                let field = TimelineTitleLayout.field(title, width: width, lines: nil)
                XCTAssertEqual(field.stringValue, title)
                XCTAssertEqual(field.maximumNumberOfLines, 0)
                XCTAssertFalse(field.cell?.truncatesLastVisibleLine ?? true)
            }
            XCTAssertTrue(TimelineTitleLayout.isNarrow(title, width: 1))
            XCTAssertFalse(TimelineTitleLayout.isNarrow(title, width: 40))
        }
    }
}
#endif
