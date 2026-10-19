#if os(macOS)
import AppKit
import PDFKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class ScreenplayPDFTests: XCTestCase {
    func testMultipagePDFContainsEveryParagraphAndCorrectPaperBounds() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var project = Project(name: "Screenplay pagination fixture")
            let id = project.addScene()
            let html = (0..<180).map { "<div class='sc-action'>TOKEN\($0) The train arrives at the station.</div>" }.joined()
            try project.updateScene(id: id, html: html, heading: SceneHeading(prefix: "EXT.", location: "STATION", time: "NIGHT"),
                                    sceneNumber: "12A")
            for paper in ScreenplayPaper.allCases {
                let result = try ScreenplayPDF.render(project: project, paper: paper)
                let document = try XCTUnwrap(PDFDocument(data: result.data))
                XCTAssertGreaterThan(document.pageCount, 1)
                XCTAssertEqual(document.pageCount, result.pageRanges.count)
                let bounds = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
                XCTAssertEqual(bounds.width, paper.width, accuracy: 0.01)
                XCTAssertEqual(bounds.height, paper.height, accuracy: 0.01)
                let output = document.string ?? ""
                for index in 0..<180 { XCTAssertTrue(output.contains("TOKEN\(index) "), "Missing paragraph \(index)") }
                XCTAssertTrue(output.contains("12A"))
                XCTAssertTrue(output.contains("EXT. STATION - NIGHT"))
                var end = 0
                for range in result.pageRanges {
                    XCTAssertEqual(range.location, end)
                    XCTAssertGreaterThan(range.length, 0)
                    end = NSMaxRange(range)
                }
                XCTAssertEqual(end, result.text.length)
                if let path = ProcessInfo.processInfo.environment["FRONTSTAGE_TEST_ARTIFACTS"] {
                    let directory = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try result.save(to: directory.appendingPathComponent("screenplay-\(paper.rawValue).pdf"))
                }
            }
        }
    }

    func testPaginationMovesOrphanCuesAndHeadingsToFollowingPage() async throws {
        try await MainActor.run {
            for count in 22...32 {
                let text = NSMutableAttributedString(string: String(repeating: "Action\n", count: count),
                    attributes: ScreenplayTypography.attributes(.action, width: 432, printing: true))
                for (type, value) in [(ScreenplayElement.sceneHeading, "INT. STATION - DAY\n"),
                                       (.character, "RANGA\n"), (.parenthetical, "(quietly)\n"),
                                       (.dialogue, "The train is here.\n")] {
                    text.append(NSAttributedString(string: value, attributes: ScreenplayTypography.attributes(type, width: 432, printing: true)))
                }
                let ranges = try ScreenplayPDF.paginate(text, paper: .letter)
                for page in ranges.dropLast() {
                    let last = (text.string as NSString).paragraphRange(for: NSRange(location: NSMaxRange(page) - 1, length: 0))
                    XCTAssertFalse(ScreenplayTextCodec.element(in: text, at: last.location).keepsWithNext,
                        "Orphan at end of page for \(count) filler lines")
                }
            }
        }
    }

    func testOmittedScenesAreNotPrintedAndRenderingDoesNotMutateProject() async throws {
        try await MainActor.run {
            let project = try Project(data: Data(#"{"beats":[{"id":1,"title":"Active","content":"<p>VISIBLE</p>"},{"id":2,"title":"Omitted","content":"<p>HIDDEN</p>","isDisabled":true}]}"#.utf8))
            let before = try project.encoded()
            let result = try ScreenplayPDF.render(project: project, paper: .letter)
            let text = PDFDocument(data: result.data)?.string ?? ""
            XCTAssertTrue(text.contains("VISIBLE"))
            XCTAssertFalse(text.contains("HIDDEN"))
            XCTAssertEqual(try project.encoded(), before)
        }
    }

    func testNoActiveScenesProducesClearFailure() async throws {
        await MainActor.run {
            XCTAssertThrowsError(try ScreenplayPDF.render(project: Project(), paper: .letter))
        }
    }

    func testPDFDestinationCannotOverwriteProjectThroughSymlink() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = directory.appendingPathComponent("source.frontstage")
            let alias = directory.appendingPathComponent("alias.pdf")
            var project = Project()
            _ = project.addScene()
            try project.save(to: source)
            let before = try Data(contentsOf: source)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
            let rendered = try ScreenplayPDF.render(project: project, paper: .letter)
            XCTAssertThrowsError(try rendered.save(to: alias))
            XCTAssertEqual(try Data(contentsOf: source), before)
        }
    }
}
#endif
