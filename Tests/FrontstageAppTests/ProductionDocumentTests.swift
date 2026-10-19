#if os(macOS)
import Foundation
import PDFKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class ProductionDocumentTests: XCTestCase {
    func testProductionPDFContainsLiveCastScheduleAndRequirementsWithoutMutatingProject() async throws {
        try await MainActor.run {
            var project = Project(name: "Sample Production")
            let scene = project.addScene()
            try project.updateScene(id: scene, heading: SceneHeading(prefix: "EXT.", location: "STATION", time: "NIGHT"))
            let role = try project.createCharacter(name: "Ranga")
            let actor = try project.addCastingOption(character: role, name: "Sample Actor")
            try project.confirmCastingOption(character: role, artistID: actor)
            try project.assignCharacter(role, to: scene, assigned: true)
            try project.addBreakdownItem(sceneID: scene, category: .props, name: "Lantern", count: 2)
            let day = try project.addProductionDay(date: "2026-11-01")
            try project.assignScene(scene, toProductionDay: day)
            try project.updateProductionDay(day, field: .notes, value: "FINAL REPORT NOTE")
            let before = try project.encoded()
            let report = try ProductionDocument.render(project: project, dayID: day, paper: .a4)
            let document = try XCTUnwrap(PDFDocument(data: report.data))
            let text = document.string ?? ""
            for phrase in ["CALL SHEET", "STATION", "Sample Actor", "Lantern", "FINAL REPORT NOTE"] { XCTAssertTrue(text.contains(phrase), phrase) }
            XCTAssertEqual(try project.encoded(), before)
            XCTAssertEqual(report.pageRanges.last.map(NSMaxRange), report.text.length)
            if let path = ProcessInfo.processInfo.environment["FRONTSTAGE_TEST_ARTIFACTS"] {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                try report.save(to: URL(fileURLWithPath: path).appendingPathComponent("call-sheet-sample.pdf"))
            }
        }
    }

    func testProductionChangesAreUndoableThroughWorkspace() async throws {
        await MainActor.run {
            let workspace = Workspace()
            workspace.addScene()
            workspace.edit("Add Shooting Day") { _ = try $0.addProductionDay(date: "2026-11-01") }
            XCTAssertEqual(workspace.project.productionDays.count, 1)
            workspace.undoProject()
            XCTAssertTrue(workspace.project.productionDays.isEmpty)
            workspace.redoProject()
            XCTAssertEqual(workspace.project.productionDays.count, 1)
        }
    }
}
#endif
