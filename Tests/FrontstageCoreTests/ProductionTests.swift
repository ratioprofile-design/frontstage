import Foundation
import XCTest
@testable import FrontstageCore

final class ProductionTests: XCTestCase {
    func testStrictCalendarDatesAndTimesRejectInvalidInput() {
        XCTAssertNotNil(ProductionDates.date("2028-02-29"))
        for date in ["2027-02-29", "2026-13-01", "2026-1-2", "nonsense"] { XCTAssertNil(ProductionDates.date(date)) }
        for time in ["24:00", "12:60", "6:00", "", "-1:20"] { XCTAssertNil(ProductionDates.minutes(time)) }
        XCTAssertEqual(ProductionDates.minutes("23:59"), 1439)
    }

    func testAssignmentsMoveBetweenDaysWithoutDuplicatesAndOmittedScenesCannotBeScheduled() throws {
        var project = Project()
        let a = project.addScene(), b = project.addScene()
        let first = try project.addProductionDay(date: "2026-11-01")
        let second = try project.addProductionDay(date: "2026-11-02")
        try project.assignScene(a, toProductionDay: first)
        try project.assignScene(a, toProductionDay: first)
        XCTAssertEqual(project.productionDays.first?.sceneIDs, [a])
        try project.assignScene(a, toProductionDay: second)
        XCTAssertTrue(project.productionDays.first!.sceneIDs.isEmpty)
        try project.assignScene(b, toProductionDay: second)
        try project.moveScheduledScene(b, dayID: second, offset: -1)
        XCTAssertEqual(project.productionDays.last?.sceneIDs, [b, a])
        let before = project
        XCTAssertThrowsError(try project.assignScene(a, toProductionDay: "missing"))
        XCTAssertEqual(project, before)
        try project.setSceneOmitted(b, omitted: true)
        XCTAssertThrowsError(try project.assignScene(b, toProductionDay: first))
        XCTAssertEqual(project.scheduledScenes(for: second).map(\.id), [a])
        XCTAssertTrue(project.scheduleWarnings(for: second).contains { $0.contains("Omitted") })
        try project.assignScene(a, toProductionDay: nil)
        XCTAssertFalse(project.productionDays.contains { $0.sceneIDs.contains(a) })
    }

    func testOvernightTurnaroundCapacityAndOverlapWarnings() throws {
        var project = Project()
        let scene = project.addScene()
        let first = try project.addProductionDay(date: "2026-11-01", callTime: "18:00", wrapTime: "02:00")
        let second = try project.addProductionDay(date: "2026-11-02", callTime: "08:00", wrapTime: "10:00")
        try project.assignScene(scene, toProductionDay: second)
        try project.setSceneEstimate(scene, minutes: 180)
        XCTAssertTrue(project.scheduleWarnings(for: second).contains { $0.contains("turnaround") })
        XCTAssertTrue(project.scheduleWarnings(for: second).contains { $0.contains("exceed") })
        try project.updateProductionDay(second, field: .callTime, value: "01:00")
        XCTAssertTrue(project.scheduleWarnings(for: second).contains { $0.contains("overlaps") })
        XCTAssertTrue(project.scheduleWarnings(for: first).isEmpty)
        XCTAssertThrowsError(try project.setSceneEstimate(scene, minutes: 0))
    }

    func testCallSheetUsesConfirmedCastRequirementsAndConsistentSceneNumbers() throws {
        var project = try Project(data: Data(#"{"beats":[{"id":7,"title":"A","content":"","slug":{"prefix":"EXT.","location":"STATION","time":"NIGHT"}}]}"#.utf8))
        let role = try project.createCharacter(name: "Ranga")
        let actor = try project.addCastingOption(character: role, name: "Actor One")
        try project.confirmCastingOption(character: role, artistID: actor)
        try project.assignCharacter(role, to: 7, assigned: true)
        try project.addBreakdownItem(sceneID: 7, category: .props, name: "Lantern", count: 2)
        let day = try project.addProductionDay(date: "2026-11-01")
        try project.assignScene(7, toProductionDay: day)
        try project.updateCastCall(dayID: day, characterID: role, field: .makeupTime, value: "05:30")
        let text = try project.callSheetText(for: day)
        XCTAssertTrue(text.contains("RANGA — Actor One"))
        XCTAssertTrue(text.contains("Makeup: 05:30"))
        XCTAssertTrue(text.contains("Lantern ×2"))
        XCTAssertTrue(text.contains("1 · EXT. STATION - NIGHT"))
        XCTAssertTrue(text.contains("Hospital: Not entered"))
        XCTAssertEqual(project.castForProductionDay(day).map(\.id), [role])
        try project.updateCastCall(dayID: day, characterID: role, field: .makeupTime, value: "")
        XCTAssertNil(project.productionDays.first?.castCalls[role]?["makeupTime"])
        XCTAssertEqual(try Project(data: project.encoded()), project)
    }

    func testProductionPatchesPreserveUnknownFieldsAndRejectFutureSchemas() throws {
        var project = try Project(data: Data(#"{"beats":[],"frontstageProduction":{"schemaVersion":1,"future":"keep","days":[{"id":"day","number":1,"date":"2026-11-01","callTime":"06:00","wrapTime":"18:00","sceneIDs":[],"futureDay":true}]}}"#.utf8))
        try project.updateProductionDay("day", field: .hospitalName, value: "Real Hospital")
        XCTAssertEqual(project.preservedState["frontstageProduction"]?.object?["future"], .string("keep"))
        XCTAssertEqual(project.preservedState["frontstageProduction"]?.object?["days"]?.array?.first?.object?["futureDay"], .bool(true))
        var future = try Project(data: Data(#"{"beats":[],"frontstageProduction":{"schemaVersion":2,"days":[],"future":true}}"#.utf8))
        let before = future
        XCTAssertThrowsError(try future.addProductionDay(date: "2026-11-01"))
        XCTAssertEqual(future, before)
    }

    func testCSVQuotesUnicodeAndFormulaLikeTextAndExcludesOmittedScenes() throws {
        XCTAssertEqual(ProductionCSV.cell("A, \"B\"\nதமிழ்"), "\"A, \"\"B\"\"\nதமிழ்\"")
        XCTAssertEqual(ProductionCSV.cell("=SUM(A1)"), "\"'=SUM(A1)\"")
        XCTAssertTrue(ProductionCSV.encode([["A", "B"]]).hasSuffix("\r\n"))
        var project = Project()
        let scene = project.addScene()
        let day = try project.addProductionDay(date: "2026-11-01")
        try project.updateScene(id: scene, heading: SceneHeading(location: "UNIQUE PLACE"))
        try project.addBreakdownItem(sceneID: scene, category: .props, name: "UNIQUE PROP")
        try project.assignScene(scene, toProductionDay: day)
        XCTAssertTrue(project.scheduleCSV().contains("UNIQUE PLACE"))
        XCTAssertTrue(project.breakdownCSV().contains("UNIQUE PROP"))
        try project.setSceneOmitted(scene, omitted: true)
        XCTAssertFalse(project.scheduleCSV().contains("UNIQUE PLACE"))
        XCTAssertFalse(project.breakdownCSV().contains("UNIQUE PROP"))
    }

    func testCSVExportCannotOverwriteSourceViaSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.frontstage")
        let alias = directory.appendingPathComponent("alias.csv")
        try Project().save(to: source)
        let before = try Data(contentsOf: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        XCTAssertThrowsError(try ProductionCSV.save("CSV", to: alias))
        XCTAssertEqual(try Data(contentsOf: source), before)
        let destination = directory.appendingPathComponent("report.csv")
        try ProductionCSV.save("தமிழ்", to: destination)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "தமிழ்")
    }

    func testFivePhaseWorkflowSurvivesRecoveryAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var project = Project(name: "Integrated Production")
        let first = project.addScene(), second = project.addScene()
        try project.updateScene(id: first, html: "<div class='sc-character'>RANGA</div><div class='sc-dialogue'>Hello</div>")
        let revision = try project.saveRevision(sceneID: first, label: "Approved")
        try project.connectScenes(from: first, to: second, label: "Therefore")
        let role = try project.createCharacter(name: "Ranga")
        let actor = try project.addCastingOption(character: role, name: "Actor One")
        try project.confirmCastingOption(character: role, artistID: actor)
        try project.assignCharacter(role, to: first, assigned: true)
        try project.addBreakdownItem(sceneID: first, category: .props, name: "Lantern")
        let day = try project.addProductionDay(date: "2026-11-01")
        try project.assignScene(first, toProductionDay: day)
        let store = RecoveryStore(directory: directory)
        try store.save(project)
        project = try XCTUnwrap(store.load())
        var history = ProjectHistory()
        history.record(project, label: "Omit")
        try project.setSceneOmitted(first, omitted: true)
        XCTAssertTrue(project.castForProductionDay(day).isEmpty)
        project = try XCTUnwrap(history.undo(current: project))
        XCTAssertEqual(project.storyGraph.links.count, 1)
        XCTAssertEqual(project.revisions(for: first).first?.id, revision)
        XCTAssertTrue(try project.callSheetText(for: day).contains("Actor One"))
        XCTAssertTrue(try project.callSheetText(for: day).contains("Lantern"))
    }
}
