import Foundation
import XCTest
@testable import FrontstageCore

final class ScreenplayTests: XCTestCase {
    func testHeadingUpdatesPreserveLegacyMetadataAndRefreshRawCache() throws {
        let data = Data(#"{"beats":[{"id":1,"title":"Pilot","content":"<p>Untouched</p>","slug":{"prefix":"EXT.","location":"OLD","time":"DAY","raw":"old text","future":"keep"},"shots":[{"custom":true}]}]}"#.utf8)
        var project = try Project(data: data)
        let heading = SceneHeading(prefix: "INT.", location: "railway station", time: "NIGHT")
        try project.updateScene(id: 1, heading: heading, sceneNumber: "12A")
        let restored = try Project(data: project.encoded())
        XCTAssertEqual(restored.scenes.first?.heading.text, "INT. RAILWAY STATION - NIGHT")
        XCTAssertEqual(restored.scenes.first?.sceneNumber, "12A")
        let fields = restored.preservedState["beats"]?.array?.first?.object
        XCTAssertEqual(fields?["slug"]?.object?["future"], .string("keep"))
        XCTAssertEqual(fields?["slug"]?.object?["raw"], .string(heading.text))
        XCTAssertEqual(restored.scenes.first?.html, "<p>Untouched</p>")
        XCTAssertEqual(fields?["shots"]?.array?.count, 1)
    }

    func testMissingHeadingHasUsableDefaultsAndOmittedFlagIsExposed() throws {
        let project = try Project(data: Data(#"{"beats":[{"id":1,"title":"Pilot","content":"","isDisabled":true}]}"#.utf8))
        XCTAssertEqual(project.scenes.first?.heading.text, "INT. UNTITLED SCENE - DAY")
        XCTAssertEqual(project.scenes.first?.isDisabled, true)
        XCTAssertEqual(project.scenes.first?.sceneNumber, "")
    }

    func testReturnPolicyMatchesWriterDialogueAndTransitionFlow() {
        XCTAssertEqual(ScreenplayElement.character.afterReturn(isEmpty: false), .dialogue)
        XCTAssertEqual(ScreenplayElement.parenthetical.afterReturn(isEmpty: false), .dialogue)
        XCTAssertEqual(ScreenplayElement.dialogue.afterReturn(isEmpty: false), .character)
        XCTAssertEqual(ScreenplayElement.lyrics.afterReturn(isEmpty: false), .lyrics)
        for type in ScreenplayElement.editable { XCTAssertEqual(type.afterReturn(isEmpty: true), type == .character || type == .parenthetical ? .dialogue : type == .lyrics ? .lyrics : type == .dialogue ? .character : type == .transition ? .sceneHeading : .action) }
    }

    func testTabCycleIsReversibleAndIncludesEveryEditableElement() {
        var element = ScreenplayElement.action
        var visited = Set<ScreenplayElement>()
        for _ in ScreenplayElement.editable {
            visited.insert(element)
            XCTAssertEqual(element.cycled().cycled(backward: true), element)
            element = element.cycled()
        }
        XCTAssertEqual(visited, Set(ScreenplayElement.editable))
        XCTAssertEqual(element, .action)
    }

    func testPaperGeometryReservesBindingAndPrintMargins() {
        for paper in ScreenplayPaper.allCases {
            XCTAssertEqual(paper.leftMargin, 108)
            XCTAssertEqual(paper.rightMargin, 72)
            XCTAssertEqual(paper.contentWidth + paper.leftMargin + paper.rightMargin, paper.width, accuracy: 0.001)
            XCTAssertEqual(paper.contentHeight + paper.topMargin + paper.bottomMargin, paper.height, accuracy: 0.001)
            XCTAssertGreaterThan(paper.contentWidth, 400)
        }
    }
}
