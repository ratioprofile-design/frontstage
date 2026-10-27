import Foundation
import XCTest
@testable import FrontstageCore

final class ScreenplayWritingRulesTests: XCTestCase {
    func testSharedCommandCueAndContinuationFixtures() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/screenplay-writing-rules.json")
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for item in data["commands"] as! [[String: Any]] {
            let decision = ScreenplayCommand.resolve(element: ScreenplayElement(rawValue: item["element"] as! String)!, key: item["key"] as! String, empty: item["empty"] as! Bool, selection: item["selection"] as? Bool ?? false)
            XCTAssertEqual(decision.element.rawValue, item["target"] as? String)
            XCTAssertEqual(decision.placement.rawValue, item["placement"] as? String)
        }
        for item in data["cues"] as! [[String: Any]] {
            let cue = CharacterCue(item["source"] as! String)
            XCTAssertEqual(cue.name, item["name"] as? String)
            XCTAssertEqual(cue.extensions, item["extensions"] as! [String])
            XCTAssertEqual(cue.hasContinuation, item["continued"] as! Bool)
            XCTAssertFalse(cue.withoutContinuation.contains("CONT"))
        }
        for item in data["dialogues"] as! [[String: Any]] {
            var tracker = DialogueContinuation(), generated = [Int]()
            for (index, line) in (item["lines"] as! [[String]]).enumerated() {
                if tracker.observe(ScreenplayElement(rawValue: line[0])!, text: line[1]) { generated.append(index) }
            }
            XCTAssertEqual(generated, item["continued"] as! [Int], item["name"] as! String)
        }
    }
    func testComponentCompletionsPreserveOtherComponentsAndUnicode() {
        let names = ["KAMAL", "MARY JANE", "மாயா"]
        let name = ScreenplayCompletionRules.character("MA (V.O.)", caret: 2, names: names)
        XCTAssertEqual(name.start, 0); XCTAssertEqual(name.end, 2); XCTAssertEqual(name.values, ["MARY JANE"])
        let extensionValue = ScreenplayCompletionRules.character("KAMAL (O)", caret: 8, names: names)
        XCTAssertEqual(extensionValue.start, 6); XCTAssertEqual(extensionValue.end, 9)
        XCTAssertEqual(extensionValue.values, ["(O.S.)", "(O.C.)"])
        let heading = ScreenplayCompletionRules.heading("EXT. PARK - NIGHT", caret: 1, headings: [])
        XCTAssertEqual(heading.start, 0); XCTAssertEqual(heading.end, 4); XCTAssertTrue(heading.values.contains("EXT."))
        let time = ScreenplayCompletionRules.heading("EXT. PARK - N", caret: 13, headings: [])
        XCTAssertEqual(time.values, ["NIGHT"]); XCTAssertEqual(time.start, 12)
        XCTAssertEqual(ScreenplayCompletionRules.parenthetical("(over").values, ["(over the phone)"])
        XCTAssertNoThrow(ScreenplayCompletionRules.character("🎬 (", caret: 2, names: ["🎬"]))
    }
}
