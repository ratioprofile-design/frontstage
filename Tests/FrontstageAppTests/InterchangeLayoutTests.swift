#if os(macOS)
import AppKit
import PDFKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class InterchangeLayoutTests: XCTestCase {
    func testExplicitScenePageStartProducesASeparatePage() async throws {
        try await MainActor.run {
            var project = Project(); let a = project.addScene(), b = project.addScene()
            try project.updateScene(id: a, html: "<div class=\"sc-action\">First scene text.</div>", heading: SceneHeading(location: "FIRST"))
            try project.updateScene(id: b, html: "<div class=\"sc-action\">Second scene text.</div>", heading: SceneHeading(location: "SECOND"))
            try project.setScenePageStart(b, newPage: true)
            let result = try ScreenplayPDF.render(project: project, paper: .letter)
            let pdf = try XCTUnwrap(PDFDocument(data: result.data))
            XCTAssertEqual(pdf.pageCount, 2)
            XCTAssertTrue(pdf.page(at: 0)?.string?.contains("First scene text.") == true)
            XCTAssertFalse(pdf.page(at: 0)?.string?.contains("Second scene text.") == true)
            XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Second scene text.") == true)
        }
    }
    func testDOCXCanBeReadBackByAppKitAndParallelPDFKeepsBothColumns() async throws {
        try await MainActor.run {
            var project = Project(); let id = project.addScene()
            try project.updateScene(id: id, html: "<div class=\"sc-action\">A visible detail.</div><div class=\"sc-dialogue\">தமிழ் dialogue.</div>")
            let docx = try ScreenplayDOCX.render(project)
            let restored = try NSAttributedString(data: docx, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
            XCTAssertTrue(restored.string.contains("A visible detail.")); XCTAssertTrue(restored.string.contains("தமிழ் dialogue."))
            let parallel = try ParallelScriptPDF.render(rows: [ParallelScriptRow(left: "Left source", right: "Right translation")], title: "Parallel", paper: .letter)
            let pdf = try XCTUnwrap(PDFDocument(data: parallel.data))
            XCTAssertTrue(pdf.string?.contains("Left source") == true); XCTAssertTrue(pdf.string?.contains("Right translation") == true)
        }
    }
    func testNativeOfficeImportsRetainOwnDOCXTypesAndXLSXCells() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            var project = Project(); let id = project.addScene()
            try project.updateScene(id: id, html: "<div class=\"sc-character\">MARA</div><div class=\"sc-dialogue\">A typed line.</div>")
            let docx = directory.appendingPathComponent("script.docx")
            try ScreenplayDOCX.render(project).write(to: docx)
            let imported = try OfficeImport.docx(docx)
            let last = (imported.string as NSString).range(of: "A typed line.").location
            XCTAssertNotEqual(last, NSNotFound)
            XCTAssertEqual(ScreenplayTextCodec.element(in: imported, at: last), .dialogue)
            let xlsx = directory.appendingPathComponent("table.xlsx"), rows = [["Name", "Text"], ["தமிழ்", "=literal & <text>"]]
            try OfficeArchive.spreadsheet(rows: rows).write(to: xlsx)
            XCTAssertEqual(try OfficeImport.spreadsheet(xlsx), rows)
        }
    }
}
#endif
