#if os(macOS)
import AppKit
import PDFKit
import SwiftUI
import XCTest
import FrontstageCore
@testable import FrontstageApp

final class AntigravityNativeAdoptionTests: XCTestCase {
    func testTypographyFallbackAndLegacyDualMetadataRoundTrip() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var settings = ScriptLayoutSettings()
            settings.elements["character"] = ElementTypography(fontName: "Missing DOT Test Font", fontSize: 18, isItalic: true, isUppercase: true, isTamil: true)
            let attributes = ScreenplayTypography.attributes(.character, width: 432, settings: settings)
            XCTAssertEqual((attributes[.font] as? NSFont)?.pointSize, 18)
            XCTAssertGreaterThanOrEqual((attributes[.paragraphStyle] as? NSParagraphStyle)?.minimumLineHeight ?? 0, 26)
            XCTAssertEqual(settings.elements["character"]?.fontName, "Missing DOT Test Font")
            let source = "<p class='sc-character sc-dual-left sc-rev' data-dual-pair='stable-pair'>KAMAL</p><p class='sc-dialogue sc-dual-left' data-dual-pair='stable-pair'>தமிழ்</p><p class='sc-character sc-dual-right' data-dual-pair='stable-pair'>ABI</p><p class='sc-dialogue sc-dual-right' data-dual-pair='stable-pair'>Yes</p>"
            let decoded = try ScreenplayTextCodec.decode(source)
            let text = decoded.string
            ScreenplayDualDialogue.layout(decoded, width: 432, settings: settings)
            XCTAssertEqual(decoded.string, text)
            let encoded = ScreenplayTextCodec.encode(decoded)
            XCTAssertTrue(encoded.contains("data-dual-pair=\"stable-pair\"")); XCTAssertTrue(encoded.contains("sc-dual-left")); XCTAssertTrue(encoded.contains("sc-dual-right")); XCTAssertTrue(encoded.contains("sc-rev")); XCTAssertTrue(encoded.contains("தமிழ்"))
            XCTAssertFalse(encoded.contains("<table"))
            let firstStyle = decoded.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            let dialogue = (decoded.string as NSString).range(of: "தமிழ்")
            let dialogueStyle = decoded.attribute(.paragraphStyle, at: dialogue.location, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertTrue(firstStyle?.textBlocks.first === dialogueStyle?.textBlocks.first)
        }
    }
    func testDualColumnsAndPDFUseOneSharedTop() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let html = "<p class='sc-character sc-dual-left' data-dual-pair='pair'>KAMAL</p><p class='sc-dialogue sc-dual-left' data-dual-pair='pair'>" + String(repeating: "Unequal speech length. ", count: 25) + "</p><p class='sc-character sc-dual-right' data-dual-pair='pair'>ABI</p><p class='sc-dialogue sc-dual-right' data-dual-pair='pair'>Yes.</p><p class='sc-action'>After both speakers.</p>"
            let storage = NSTextStorage(attributedString: try ScreenplayTextCodec.decode(html))
            ScreenplayDualDialogue.layout(storage, width: 432, settings: .init())
            let manager = NSLayoutManager(), container = NSTextContainer(containerSize: NSSize(width: 432, height: 2000)); container.lineFragmentPadding = 0
            storage.addLayoutManager(manager); manager.addTextContainer(container); manager.ensureLayout(for: container)
            func rect(_ value: String) -> NSRect {
                let range = (storage.string as NSString).range(of: value)
                return manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
            }
            XCTAssertEqual(rect("KAMAL").minY, rect("ABI").minY, accuracy: 1)
            XCTAssertGreaterThan(rect("ABI").minX, rect("KAMAL").minX + 150)
            XCTAssertGreaterThan(rect("After both speakers.").minY, rect("Yes.").maxY)
            let pdf = try ScreenplayPDF.renderText(storage, title: "Dual", paper: .a4)
            let document = try XCTUnwrap(PDFDocument(data: pdf.data))
            XCTAssertTrue(document.string?.contains("KAMAL") == true); XCTAssertTrue(document.string?.contains("ABI") == true)
            XCTAssertTrue(document.string?.contains("After both speakers.") == true)
        }
    }

    func testHostedPairingKeepsCaretAndProjectUndo() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var project = Project(oneBeatPerScene: true)
            let id = try project.addBoardBeat(title: "Paired scene")
            try project.updateBoardBeat(id) { $0.html = "<p class='sc-character'>KAMAL</p><p class='sc-dialogue'>தமிழ் words.</p><p class='sc-character'>ABI</p><p class='sc-dialogue'>Yes.</p><p class='sc-action'>After.</p>" }
            let workspace = Workspace(); workspace.loadCopy(project); workspace.selectBoardBeat(id)
            let controller = workspace.scriptController("hosted-dual")
            let host = NSHostingView(rootView: ContinuousScriptEditor(workspace: workspace, controller: controller, width: workspace.paper.contentWidth, zoom: 1))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; host.layoutSubtreeIfNeeded(); defer { window.close() }
            let text = try XCTUnwrap(controller.textView)
            window.makeFirstResponder(text)
            let range = (text.string as NSString).range(of: "ABI")
            let caret = NSRange(location: NSMaxRange(range), length: 0)
            text.setSelectedRange(caret); let original = text.string
            ScreenplayDualDialogue.toggle(controller)
            XCTAssertEqual(text.selectedRange(), caret); XCTAssertEqual(text.string, original)
            XCTAssertTrue(try workspace.project.whiteboard().beats.first { $0.id == id }?.html.contains("sc-dual-right") == true)
            workspace.undoProject()
            XCTAssertFalse(try workspace.project.whiteboard().beats.first { $0.id == id }?.html.contains("sc-dual-right") == true)
            workspace.redoProject()
            XCTAssertTrue(try workspace.project.whiteboard().beats.first { $0.id == id }?.html.contains("sc-dual-right") == true)
            let data = try ScreenplayDOCX.render(workspace.project)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
            try data.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
            let xml = String(data: try OfficeZIP.member("word/document.xml", from: file), encoding: .utf8) ?? ""
            XCTAssertTrue(xml.contains("<w:tbl>")); XCTAssertTrue(xml.contains("தமிழ்")); XCTAssertTrue(xml.contains("<w:vAlign w:val=\"top\"/>"))
        }
    }
    func testDualPDFKeepsUnequalLongSpeechesAcrossPages() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let html = "<p class='sc-character sc-dual-left' data-dual-pair='long'>KAMAL</p><p class='sc-dialogue sc-dual-left' data-dual-pair='long'>" + String(repeating: "LEFT_UNIQUE ", count: 250) + "</p><p class='sc-character sc-dual-right' data-dual-pair='long'>ABI</p><p class='sc-dialogue sc-dual-right' data-dual-pair='long'>" + String(repeating: "RIGHT_UNIQUE ", count: 40) + "</p><p class='sc-action'>AFTER_UNIQUE</p>"
            let decoded = try ScreenplayTextCodec.decode(html)
            let result = try ScreenplayPDF.renderText(decoded, title: "Long dual", paper: .a4)
            let pdf = try XCTUnwrap(PDFDocument(data: result.data)), content = pdf.string ?? ""
            XCTAssertGreaterThan(pdf.pageCount, 1)
            XCTAssertEqual(content.components(separatedBy: "LEFT_UNIQUE").count - 1, 250)
            XCTAssertEqual(content.components(separatedBy: "RIGHT_UNIQUE").count - 1, 40)
            XCTAssertTrue(content.contains("AFTER_UNIQUE"))
            XCTAssertTrue(content.contains("(MORE)")); XCTAssertTrue(content.contains("(CONT'D)"))
            XCTAssertFalse(content.contains("(CONT'D) (CONT'D)"))
            XCTAssertTrue(pdf.page(at: 0)?.string?.contains("ABI") == true)
        }
    }

}
#endif
