import XCTest
@testable import FrontstageCore

final class ScriptAnnotationTests: XCTestCase {
    private func project() throws -> Project {
        var p = Project()
        let id = try p.addBoardBeat(title: "Car")
        let scene = try XCTUnwrap(p.whiteboard().beats.first { $0.id == id }?.sceneID)
        try p.addBreakdownItem(sceneID: scene, category: .vehicles, name: "red car", sourceQuote: "red car")
        let item = try XCTUnwrap(p.breakdownItems(for: scene).first)
        try p.updateBoardBeat(id) { $0.html = "<p class='sc-action'>Before.</p><p class='sc-action'><span data-dot-breakdown='\(item.recordID!)' data-dot-category='VEHICLES'><span data-dot-highlight='Yellow'>red car</span></span></p>" }
        return p
    }
    func testDuplicateAndSplitPreserveIndependentSourceLinks() throws {
        var p = try project(); let original = try XCTUnwrap(p.whiteboard().beats.first)
        let first = try XCTUnwrap(p.breakdownItems(for: original.sceneID).first)
        let duplicated = try p.duplicateBoardBeat(original.id), copy = try XCTUnwrap(p.whiteboard().beats.first { $0.id == duplicated })
        let copied = try XCTUnwrap(p.breakdownItems(for: copy.sceneID).first)
        XCTAssertNotEqual(first.id, copied.id); XCTAssertTrue(copy.html.contains(copied.recordID!)); XCTAssertFalse(copy.html.contains(first.recordID!)); XCTAssertTrue(copy.html.contains("data-dot-highlight"))
        let fragment = try p.insertScriptScene(afterSplitting: original.id, beforeHTML: "<p>Before.</p>", afterHTML: "<p><span data-dot-breakdown='\(first.recordID!)'>red car</span></p>", heading: "EXT. ROAD - DAY")
        let moved = try XCTUnwrap(p.whiteboard().beats.first { $0.id == fragment })
        XCTAssertTrue(p.breakdownItems(for: original.sceneID).isEmpty)
        XCTAssertEqual(p.breakdownItems(for: moved.sceneID).first?.recordID, first.recordID)
        XCTAssertTrue(moved.html.contains("data-dot-category=\"VEHICLES\""))
        XCTAssertEqual(try Project(data: p.encoded()), p)
    }
    func testProductionComparisonIgnoresAnnotationsButPreservesAuthoredChanges() {
        let plain = "<p>A red car waits.</p>", tagged = "<p>A <span data-dot-breakdown='req-1'><span data-dot-highlight='Blue'>red car</span></span> waits.</p>"
        XCTAssertEqual(ScriptAnnotations.comparisonHTML(plain), ScriptAnnotations.comparisonHTML(tagged))
        XCTAssertNotEqual(ScriptAnnotations.comparisonHTML(plain), ScriptAnnotations.comparisonHTML(tagged.replacingOccurrences(of: "waits", with: "leaves")))
        XCTAssertNotEqual(ScriptAnnotations.comparisonHTML(plain), ScriptAnnotations.comparisonHTML(tagged.replacingOccurrences(of: "red car", with: "<b>red car</b>")))
    }
    func testCategoryChangesAndDeletionUpdateMarkupWithoutDeletingText() throws {
        var p = try project(); let beat = try XCTUnwrap(p.whiteboard().beats.first), item = try XCTUnwrap(p.breakdownItems(for: beat.sceneID).first)
        try p.moveBreakdownItem(sceneID: beat.sceneID, itemID: item.id, category: .props); p.reconcileScriptAnnotations()
        XCTAssertTrue(try p.whiteboard().beats[0].html.contains("data-dot-category=\"PROPS\""))
        try p.removeBreakdownItem(sceneID: beat.sceneID, itemID: p.breakdownItems(for: beat.sceneID).first!.id); p.reconcileScriptAnnotations()
        let html = try p.whiteboard().beats[0].html
        XCTAssertFalse(html.contains("data-dot-breakdown")); XCTAssertTrue(html.contains("red car")); XCTAssertTrue(html.contains("data-dot-highlight"))
        XCTAssertTrue(p.requiredWriteFeatures.contains("scriptAnnotations"))
        XCTAssertThrowsError(try p.validateWriterCompatibility(previous: p, supported: ["elementTypography","dualDialogue","productionBaselines"]))
    }
}
