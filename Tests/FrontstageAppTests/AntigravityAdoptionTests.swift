#if os(macOS)
import AppKit
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
            XCTAssertFalse(encoded.contains("table"))
            let firstStyle = decoded.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            let dialogue = (decoded.string as NSString).range(of: "தமிழ்")
            let dialogueStyle = decoded.attribute(.paragraphStyle, at: dialogue.location, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertTrue(firstStyle?.textBlocks.first === dialogueStyle?.textBlocks.first)
        }
    }
}
#endif
