#if os(macOS)
import AppKit
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class TimelinePageLayoutTests: XCTestCase {
    func testMeasuredTimingUsesPdfFramesFontsPaperAndDualColumns() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var project = Project(oneBeatPerScene: true)
            let first = try project.addBoardBeat(title: "Measured Tamil"), second = try project.addBoardBeat(title: "Next scene")
            let body = (0..<75).map { "<p class='sc-action'>\($0): தமிழ் கதையின் சொற்கள் — a measured screenplay line with dialogue and action on the printed page.</p>" }.joined()
            try project.updateBoardBeat(first) { $0.html = body }
            try project.updateBoardBeat(second) { $0.html = "<p class='sc-character'>MAYA</p><p class='sc-dialogue'>I will go.</p>" }
            let before = project
            let a4 = try XCTUnwrap(ScreenplayPDF.timelinePageCounts(project: project, paper: .a4))
            let pdf = try ScreenplayPDF.render(project: project, paper: .a4)
            let extent = a4.values.reduce(0, +)
            XCTAssertGreaterThan(a4[first] ?? 0, 1)
            XCTAssertGreaterThan(extent, Double(pdf.pages.count - 1))
            XCTAssertLessThanOrEqual(extent, Double(pdf.pages.count) + 0.001)
            let letter = try XCTUnwrap(ScreenplayPDF.timelinePageCounts(project: project, paper: .letter))
            XCTAssertGreaterThanOrEqual(letter[first] ?? 0, a4[first] ?? 0)
            XCTAssertEqual(project, before)
            var settings = project.scriptLayout; settings.fontSize = 20; settings.lineHeight = 24; try project.setScriptLayout(settings)
            let large = try XCTUnwrap(ScreenplayPDF.timelinePageCounts(project: project, paper: .a4))
            XCTAssertGreaterThan(large[first] ?? 0, (a4[first] ?? 0) * 1.5)
            let speech = "<p class='sc-character sc-dual-left' data-dual-pair='pair'>KAMAL</p><p class='sc-dialogue sc-dual-left' data-dual-pair='pair'>" + String(repeating: "A longer speech. ", count: 90) + "</p><p class='sc-character sc-dual-right' data-dual-pair='pair'>ABI</p><p class='sc-parenthetical sc-dual-right' data-dual-pair='pair'>(quietly)</p><p class='sc-dialogue sc-dual-right' data-dual-pair='pair'>தமிழ்.</p>"
            try project.setScriptLayout(before.scriptLayout)
            try project.updateBoardBeat(first) { $0.html = speech }
            let paired = project
            let dual = try XCTUnwrap(ScreenplayPDF.timelinePageCounts(project: project, paper: .a4))
            let dualPdf = try ScreenplayPDF.render(project: project, paper: .a4)
            XCTAssertGreaterThan(dual.values.reduce(0, +), Double(dualPdf.pages.count - 1))
            XCTAssertLessThanOrEqual(dual.values.reduce(0, +), Double(dualPdf.pages.count) + 0.001)
            XCTAssertEqual(project, paired)
            let cache = TimelinePageLayoutCache()
            XCTAssertEqual(try cache.pages(project: project, paper: .a4), dual)
            try project.editWhiteboard { $0.viewport.zoom = 2 }
            XCTAssertEqual(try cache.pages(project: project, paper: .a4), dual)
        }
    }
}
#endif
