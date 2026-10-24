#if os(macOS)
import AppKit

/// Drawing and layout must use identical font fallback and line-fragment metrics.
@MainActor
enum WhiteboardBeatText {
    static var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.minimumLineHeight = 16.5
        return [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
    }

    static func size(_ title: String, _ maximumWidth: Double) -> (width: Double, height: Double) {
        let text = (title.isEmpty ? " " : title) as NSString
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let natural = text.boundingRect(with: NSSize(width: 1_000_000, height: 1_000_000), options: options, attributes: attributes)
        let width = max(32, min(maximumWidth, ceil(natural.width) + 18))
        let wrapped = text.boundingRect(with: NSSize(width: width - 14, height: 1_000_000), options: options, attributes: attributes)
        return (width, max(26, ceil(wrapped.height) + 12))
    }
}
#endif
