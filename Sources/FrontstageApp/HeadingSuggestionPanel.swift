#if os(macOS)
import AppKit
import FrontstageCore

private final class HeadingSuggestionWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Unlike NSTextView.complete, showing choices never inserts a preview suffix.
@MainActor
final class HeadingSuggestionPanel: NSObject {
    private var panel: NSPanel?
    private var choices = [String]()
    private var selected = 0
    private weak var text: NSTextView?
    private var replacement = NSRange(), caret = NSRange()
    private var expected = ""
    private var buttons = [NSButton]()
    var isShown: Bool { panel?.isVisible == true }

    func close() { if let panel { panel.orderOut(nil); panel.parent?.removeChildWindow(panel) }; choices = []; buttons = [] }
    func show(in text: NSTextView, headings: [SceneHeading]) {
        close()
        let source = text.string as NSString, caret = text.selectedRange()
        guard let window = text.window, text.isEditable, !text.hasMarkedText(), caret.length == 0, caret.location < source.length,
              let context = ScriptHeadingEditing.context(in: text, replacing: caret) else { return }
        let line = source.substring(with: context.range).trimmingCharacters(in: .newlines) as NSString
        let offset = caret.location - context.range.location
        guard offset > 0, offset <= line.length else { return }
        choices = Array(SceneHeading.completions(for: line.substring(to: offset), headings: headings).prefix(12))
        guard !choices.isEmpty else { return }
        let separator = try? NSRegularExpression(pattern: #"\s+[-–—]\s*"#)
        let split = separator?.matches(in: line as String, range: NSRange(location: 0, length: line.length)).last?.range
        let prefix = try? NSRegularExpression(pattern: #"^(?:INT\./EXT\.|EXT\./INT\.|INT\.|EXT\.|I/E\.)\s+"#, options: .caseInsensitive)
        let kind = prefix?.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length))?.range
        let end: Int, labelStart: Int
        if let split, offset >= NSMaxRange(split) { end = line.length; labelStart = NSMaxRange(split) }
        else if let kind, offset >= NSMaxRange(kind) { end = split?.location ?? line.length; labelStart = NSMaxRange(kind) }
        else { end = (line as String).firstIndex(where: { $0.isWhitespace }).map { (String((line as String)[..<$0]) as NSString).length } ?? line.length; labelStart = 0 }
        self.text = text; self.caret = caret; replacement = NSRange(location: context.range.location, length: end)
        expected = source.substring(with: replacement); selected = 0
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        for (index, choice) in choices.enumerated() {
            let title = (choice as NSString).substring(from: min(labelStart, (choice as NSString).length))
            let button = NSButton(title: title, target: self, action: #selector(clicked(_:)))
            button.tag = index; button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 12); button.alignment = .left
            button.setAccessibilityLabel("Heading suggestion: " + title)
            button.widthAnchor.constraint(equalToConstant: 270).isActive = true
            stack.addArrangedSubview(button); buttons.append(button)
        }
        let content = NSViewController(); content.view = stack
        let size = NSSize(width: 280, height: CGFloat(choices.count) * 26 + 10)
        let popup = panel ?? HeadingSuggestionWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel = popup; popup.isReleasedWhenClosed = false; popup.contentViewController = content
        popup.hasShadow = true; popup.level = .popUpMenu; popup.backgroundColor = .windowBackgroundColor
        let anchor = text.firstRect(forCharacterRange: caret, actualRange: nil), screen = window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let x = max(screen.minX, min(anchor.minX, screen.maxX - size.width))
        let y = anchor.minY - size.height - 4 >= screen.minY ? anchor.minY - size.height - 4 : min(screen.maxY - size.height, anchor.maxY + 4)
        popup.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true); highlight(); window.addChildWindow(popup, ordered: .above); popup.orderFront(nil)
    }
    private func highlight() {
        for (index, button) in buttons.enumerated() { button.bezelColor = index == selected ? .selectedControlColor : .controlColor }
    }
    @objc private func clicked(_ sender: NSButton) { selected = sender.tag; accept() }
    private func accept() {
        guard let text, choices.indices.contains(selected), !text.hasMarkedText(), text.selectedRange() == caret,
              NSMaxRange(replacement) <= text.string.utf16.count, (text.string as NSString).substring(with: replacement) == expected else { close(); return }
        let value = choices[selected], range = replacement; close()
        text.window?.makeFirstResponder(text); text.insertText(value, replacementRange: range)
    }
    func handle(_ selector: Selector) -> Bool {
        guard isShown, !choices.isEmpty else { return false }
        if selector == #selector(NSResponder.moveDown(_:)) { selected = (selected + 1) % choices.count; highlight(); return true }
        if selector == #selector(NSResponder.moveUp(_:)) { selected = (selected + choices.count - 1) % choices.count; highlight(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertTab(_:)) { accept(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        close(); return false
    }
}
#endif
