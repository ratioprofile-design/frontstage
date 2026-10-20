import Foundation
import XCTest
@testable import FrontstageCore

final class OfficeArchiveTests: XCTestCase {
    func testCSVHandlesQuotedNewlinesEscapedQuotesCRLFAndEmptyFinalCells() throws {
        XCTAssertEqual(try OfficeArchive.parseCSV("\"A\",\"line\nnext\",\"a\"\"b\"\r\n1,2,\r\n"), [["A", "line\nnext", "a\"b"], ["1", "2", ""]])
        XCTAssertThrowsError(try OfficeArchive.parseCSV("\"unterminated"))
        XCTAssertThrowsError(try OfficeArchive.parseCSV("\"x\"unexpected"))
    }
    func testOfficeZIPIsDeterministicAndRejectsParentPaths() throws {
        let files = ["word/document.xml": Data("தமிழ்".utf8)]
        let a = try OfficeArchive.zip(files), b = try OfficeArchive.zip(files)
        XCTAssertEqual(a, b); XCTAssertEqual(Array(a.prefix(4)), [0x50, 0x4b, 3, 4])
        XCTAssertTrue(String(decoding: a, as: UTF8.self).contains("word/document.xml"))
        XCTAssertThrowsError(try OfficeArchive.zip(["../escape": Data()]))
    }
    func testSpreadsheetStoresFormulaLikeValuesAsTextAndEscapesXML() throws {
        let data = try OfficeArchive.spreadsheet(rows: [["Name", "Notes"], ["தமிழ்", "=1+1 & <x>"]])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("inlineStr")); XCTAssertTrue(text.contains("=1+1 &amp; &lt;x&gt;"))
        XCTAssertFalse(text.contains("<f>")); XCTAssertTrue(text.contains("xl/worksheets/sheet1.xml"))
    }
}
