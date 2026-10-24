#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

/// Measuring and displaying through the same AppKit text cell keeps fallback fonts
/// (including Tamil) and complete line heights consistent.
@MainActor
enum TimelineTitleLayout {
    static let font = NSFont.systemFont(ofSize: 11)
    static func isNarrow(_ title: String, width: Double) -> Bool {
        let widest = title.reduce(0.0) { max($0, Double((String($1) as NSString).size(withAttributes: [.font: font]).width)) }
        return width < widest
    }
    static func field(_ title: String, width: Double, lines: Int?) -> NSTextField {
        let field = PassiveTimelineTextField(wrappingLabelWithString: title)
        field.font = font; field.textColor = .white; field.isSelectable = false
        field.maximumNumberOfLines = lines ?? 0
        field.preferredMaxLayoutWidth = max(1, width)
        field.cell?.wraps = true; field.cell?.lineBreakMode = .byWordWrapping
        field.cell?.truncatesLastVisibleLine = lines != nil
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    static func height(_ title: String, width: Double, lines: Int?) -> Double {
        guard !isNarrow(title, width: width) else { return 16 }
        let text = field(title, width: width, lines: lines)
        let size = text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(1, width), height: 10_000_000)) ?? .zero
        return max(16, ceil(size.height))
    }
    static func rowHeight(_ items: [StoryTimeline.Item], scale: Double, lines: Int?) -> Double {
        max(28, (items.map { height($0.title, width: max(3, $0.duration * scale - 1) - 10, lines: lines) }.max() ?? 16) + 10)
    }
}

private final class PassiveTimelineTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct TimelineTitleLabel: NSViewRepresentable {
    var title: String
    var width: Double
    var lines: Int?
    func makeNSView(context: Context) -> NSTextField { TimelineTitleLayout.field(title, width: width, lines: lines) }
    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = title; field.maximumNumberOfLines = lines ?? 0
        field.preferredMaxLayoutWidth = max(1, width)
        field.cell?.truncatesLastVisibleLine = lines != nil
    }
}
#endif
