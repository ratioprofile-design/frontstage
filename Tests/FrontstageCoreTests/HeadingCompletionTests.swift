import XCTest
@testable import FrontstageCore

final class HeadingCompletionTests: XCTestCase {
    func testContextualHeadingCompletion() {
        let headings = [SceneHeading(inline: "INT. தமிழ் வீடு - NIGHT"), SceneHeading(inline: "EXT. RIVER - DAY")]
        XCTAssertEqual(SceneHeading.completions(for: "EX", headings: headings), ["EXT.", "EXT./INT."])
        XCTAssertEqual(SceneHeading.completions(for: "EXT. த", headings: headings), ["EXT. தமிழ் வீடு"])
        for separator in [" - ", " – ", " — "] {
            XCTAssertEqual(SceneHeading.completions(for: "EXT. தமிழ் வீடு" + separator + "n", headings: headings), ["EXT. தமிழ் வீடு" + separator + "NIGHT"])
            let parsed = SceneHeading(inline: "ext. தமிழ் வீடு" + separator + "night")
            XCTAssertEqual(parsed.location, "தமிழ் வீடு"); XCTAssertEqual(parsed.time, "NIGHT")
        }
        XCTAssertEqual(SceneHeading.completions(for: "INT. HALL - SAME ", headings: headings), ["INT. HALL - SAME TIME"])
        XCTAssertEqual(SceneHeading.completions(for: "INT. HALL - ", headings: headings).count, 10)
        XCTAssertEqual(SceneHeading(inline: "INT. HOUSE - KITCHEN - NIGHT").location, "HOUSE - KITCHEN")
        XCTAssertEqual(SceneHeading.completions(for: "INT. HOUSE - KITCHEN - N", headings: headings), ["INT. HOUSE - KITCHEN - NIGHT"])
    }
}
