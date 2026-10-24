#if os(macOS)
import AppKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class WhiteboardBeatTextTests: XCTestCase {
    func testShapedTitlesFitCards() async {
        await MainActor.run {
            _ = NSApplication.shared
            for title in ["Untitled Beat", "காகித கப்பல் கடலுல க வந்துடுச்சா?", "தமிழ் English 👨‍👩‍👧‍👦", String(repeating: "கப்பல்", count: 30), "First\nஇரண்டாவது வரி\n"] {
                for limit in [80.0, 140.0, 212.0] {
                    let size = WhiteboardBeatText.size(title, limit)
                    let rect = (title as NSString).boundingRect(with: NSSize(width: size.width - 14, height: 1_000_000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: WhiteboardBeatText.attributes)
                    XCTAssertLessThanOrEqual(size.width, limit)
                    XCTAssertLessThanOrEqual(ceil(rect.height), size.height - 10)
                    XCTAssertLessThanOrEqual(ceil(rect.width), size.width - 14)
                }
            }
            XCTAssertLessThan(WhiteboardBeatText.size("Go", 212).width, WhiteboardBeatText.size("A longer choice", 212).width)
            XCTAssertGreaterThan(WhiteboardBeatText.size(String(repeating: "கப்பல் ", count: 20), 140).height, WhiteboardBeatText.size("கப்பல்", 140).height)
        }
    }
}
#endif
