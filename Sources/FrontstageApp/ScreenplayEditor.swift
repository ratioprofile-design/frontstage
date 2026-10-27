#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

@MainActor
final class ScreenplayEditorController: ObservableObject {
    @Published private(set) var activeElement = ScreenplayElement.action
    @Published private(set) var layoutHeight: CGFloat = 80
    weak var textView: NSTextView?
    var minimumHeight: CGFloat = 48
    var contentWidth: CGFloat = 432
    var typography = ScriptLayoutSettings()
    var completionRequest: (() -> Void)?
    func measure() {
        guard let textView, let container = textView.textContainer, let manager = textView.layoutManager else { return }
        manager.ensureLayout(for: container)
        let height = max(minimumHeight, ceil(manager.usedRect(for: container).height + textView.textContainerInset.height * 2 + 8))
        if abs(layoutHeight - height) > 1 {
            DispatchQueue.main.async { [weak self] in self?.layoutHeight = height }
        }
    }
    func toggleInlineStyle(_ style: String) {
        guard let textView, textView.isEditable, !textView.hasMarkedText() else { return }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        let attributes = range.length > 0 ? textView.attributedString().attributes(at: range.location, effectiveRange: nil) : textView.typingAttributes
        let font = attributes[.font] as? NSFont ?? NSFont.monospacedSystemFont(ofSize: typography.fontSize, weight: .regular)
        let trait: NSFontTraitMask = style == "bold" ? .boldFontMask : .italicFontMask
        let remove = style == "underline" ? (attributes[.underlineStyle] as? Int ?? 0) != 0 : NSFontManager.shared.traits(of: font).contains(trait)
        func adjusted(_ source: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var value = source
            if style == "underline" { value[.underlineStyle] = remove ? 0 : NSUnderlineStyle.single.rawValue }
            else {
                let current = value[.font] as? NSFont ?? font
                value[.font] = remove ? NSFontManager.shared.convert(current, toNotHaveTrait: trait) : NSFontManager.shared.convert(current, toHaveTrait: trait)
            }
            return value
        }
        if range.length == 0 { textView.typingAttributes = adjusted(attributes); return }
        let source = textView.attributedString().attributedSubstring(from: range)
        let replacement = NSMutableAttributedString(attributedString: source)
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length), options: []) { attributes, range, _ in
            replacement.setAttributes(adjusted(attributes), range: range)
        }
        textView.insertText(replacement, replacementRange: range)
        textView.setSelectedRange(range)
    }

    func selectionChanged() {
        guard let textView, !textView.hasMarkedText() else { return }
        let element: ScreenplayElement
        if textView.selectedRange().location == textView.string.utf16.count,
           let type = textView.typingAttributes[.screenplayElement] as? String {
            element = ScreenplayElement(rawValue: type) ?? .action
        } else {
            element = ScreenplayTextCodec.element(in: textView.attributedString(), at: textView.selectedRange().location)
        }
        if activeElement != element { activeElement = element }
    }

    func format(_ element: ScreenplayElement) {
        guard let textView, textView.isEditable, !textView.hasMarkedText() else { return }
        textView.window?.makeFirstResponder(textView)
        let selection = textView.selectedRange()
        let range = (textView.string as NSString).paragraphRange(for: selection)
        if range.length > 0, element != .sceneHeading,
           textView.attributedString().attribute(NSAttributedString.Key("FrontstageSceneHeading"), at: range.location, effectiveRange: nil) != nil {
            var attributes = ScreenplayTypography.attributes(element, width: contentWidth, settings: typography)
            if let owner = textView.attributedString().attribute(NSAttributedString.Key("FrontstageBeatOwner"), at: range.location, effectiveRange: nil) { attributes[NSAttributedString.Key("FrontstageBeatOwner")] = owner }
            textView.insertText(NSAttributedString(string: "\n", attributes: attributes), replacementRange: NSRange(location: NSMaxRange(range), length: 0))
            textView.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0)); textView.typingAttributes = attributes; activeElement = element; return
        }
        if range.length > 0 {
            let replacement = NSMutableAttributedString(attributedString: textView.attributedString().attributedSubstring(from: range))
            ScreenplayTypography.apply(element, to: replacement,
                range: NSRange(location: 0, length: replacement.length), width: contentWidth, settings: typography)
            // NSTextView's insertion API participates in native undo, unlike direct storage mutations.
            textView.insertText(replacement, replacementRange: range)
            textView.setSelectedRange(selection)
        }
        var typing = ScreenplayTypography.attributes(element, width: contentWidth, settings: typography)
        let source = textView.attributedString()
        if source.length > 0, let owner = source.attribute(ScriptHeadingEditing.owner, at: min(selection.location, source.length - 1), effectiveRange: nil) { typing[ScriptHeadingEditing.owner] = owner }
        textView.typingAttributes = typing
        activeElement = element
    }

    func insertCue(_ value: String, element: ScreenplayElement) {
        guard let textView, textView.isEditable, !textView.hasMarkedText() else { return }
        textView.window?.makeFirstResponder(textView)
        let source = textView.string as NSString
        var range = source.paragraphRange(for: textView.selectedRange())
        let line = source.substring(with: range)
        let same = ScreenplayTextCodec.element(in: textView.attributedString(), at: range.location) == element
        var prefix = ""
        if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !same {
            range = NSRange(location: NSMaxRange(range), length: 0)
            if range.location > 0 && source.substring(with: NSRange(location: range.location - 1, length: 1)) != "\n" { prefix = "\n" }
        }
        let suffix = (range.length > 0 && line.hasSuffix("\n")) || (range.length == 0 && range.location < source.length) ? "\n" : ""
        let attributes = ScreenplayTypography.attributes(element, width: contentWidth, settings: typography)
        textView.insertText(NSAttributedString(string: prefix + value + suffix, attributes: attributes), replacementRange: range)
        textView.setSelectedRange(NSRange(location: range.location + (prefix + value).utf16.count, length: 0))
        textView.typingAttributes = attributes; activeElement = element
    }

    @discardableResult
    func handleCommand(_ selector: Selector, in textView: NSTextView) -> Bool {
        guard textView.isEditable, !textView.hasMarkedText() else { return false }
        let key: String
        switch selector {
        case #selector(NSResponder.insertTab(_:)): key = "Tab"
        case #selector(NSResponder.insertBacktab(_:)): key = "Backtab"
        case #selector(NSResponder.insertNewline(_:)): key = "Enter"
        default: return false
        }
        selectionChanged()
        let selected = textView.selectedRange()
        let source = textView.attributedString(), string = source.string as NSString
        let paragraph = string.paragraphRange(for: NSRange(location: selected.location, length: 0))
        let empty = string.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let decision = ScreenplayCommand.resolve(element: activeElement, key: key, empty: empty, selection: selected.length > 0)
        if decision.placement == .suggestions { completionRequest?(); return true }
        textView.undoManager?.beginUndoGrouping(); defer { textView.undoManager?.endUndoGrouping() }
        if decision.placement == .inPlace { format(decision.element); return true }
        let next = decision.element
        var attributes = ScreenplayTypography.attributes(next, width: contentWidth, settings: typography)
        let owner = source.length > 0 ? source.attribute(ScriptHeadingEditing.owner, at: min(paragraph.location, source.length - 1), effectiveRange: nil) : nil
        if let owner { attributes[ScriptHeadingEditing.owner] = owner }
        let end = NSMaxRange(paragraph)
        if decision.placement == .body || decision.placement == .afterParagraph {
            if end < source.length {
                let following = string.paragraphRange(for: NSRange(location: end, length: 0))
                let sameOwner = (source.attribute(ScriptHeadingEditing.owner, at: end, effectiveRange: nil) as? String) == (owner as? String)
                if sameOwner, decision.placement == .body || (string.substring(with: following).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && source.attribute(ScriptHeadingEditing.heading, at: end, effectiveRange: nil) == nil) {
                    textView.setSelectedRange(NSRange(location: end, length: 0))
                    if decision.placement == .body { textView.typingAttributes = source.attributes(at: end, effectiveRange: nil); selectionChanged() }
                    else { format(next) }
                    return true
                }
            }
            let terminated = paragraph.length > 0 && string.substring(with: paragraph).hasSuffix("\n")
            textView.insertText(NSAttributedString(string: "\n", attributes: attributes), replacementRange: NSRange(location: end, length: 0))
            textView.setSelectedRange(NSRange(location: terminated ? end : end + 1, length: 0))
        } else {
            textView.insertText(NSAttributedString(string: "\n", attributes: attributes), replacementRange: selected)
            let caret = textView.selectedRange()
            format(next); textView.setSelectedRange(caret)
        }
        textView.typingAttributes = attributes
        activeElement = next
        return true
    }
}

class ScreenplayTextView: NSTextView {
    weak var screenplayController: ScreenplayEditorController?
    var splitScene: (() -> Void)?
    var continuationSeed: String?
    var continuationFlags: [String: [Bool]]?
    var continuationTokens = [DialoguePresentationToken]()
    override func draw(_ dirtyRect: NSRect) { super.draw(dirtyRect); DialoguePresentation.draw(in: self, dirty: dirtyRect) }
    private var splitCaret: NSRange?
    override func rightMouseDown(with event: NSEvent) {
        if splitScene != nil, selectedRange().length == 0 { splitCaret = selectedRange() }
        super.rightMouseDown(with: event)
        splitCaret = nil
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let styles = NSMenuItem(title: "Paragraph Style", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for element in ScreenplayElement.editable {
            let item = NSMenuItem(title: element.label, action: #selector(applyParagraph(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = element.rawValue; item.isEnabled = isEditable; submenu.addItem(item)
        }
        styles.submenu = submenu; menu.addItem(.separator()); menu.addItem(styles)
        if splitScene != nil {
            let split = NSMenuItem(title: "Split scene at cursor", action: #selector(splitWriteScene), keyEquivalent: "")
            split.target = self; split.isEnabled = isEditable; menu.addItem(split)
        }
        return menu
    }
    @objc private func splitWriteScene() { if let splitCaret { setSelectedRange(splitCaret) }; splitScene?() }
    @objc private func applyParagraph(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let element = ScreenplayElement(rawValue: value) { screenplayController?.format(element) }
    }
    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        if flag && movement == NSReturnTextMovement && screenplayController?.activeElement == .character {
            screenplayController?.handleCommand(#selector(NSResponder.insertNewline(_:)), in: self)
        }
    }
    var leadingAdjustment: CGFloat = 0
    override var textContainerOrigin: NSPoint {
        var origin = super.textContainerOrigin
        origin.x += leadingAdjustment
        return origin
    }
}

struct ScreenplayEditor: NSViewRepresentable {
    @Binding var html: String
    @ObservedObject var controller: ScreenplayEditorController
    var width: CGFloat = 432
    var typography = ScriptLayoutSettings()
    var onError: (String) -> Void
    var editable = true
    var paper = false
    var paperTopInset: CGFloat = 72
    var continuous = false
    var suggestions: [ScreenplayElement: [String]] = [:]
    var continuationSeed: String?
    var explicitCharacters = [String]()

    func makeCoordinator() -> Coordinator { Coordinator(html: $html, controller: controller, onError: onError) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = !continuous
        let text = ScreenplayTextView(frame: NSRect(x: 0, y: 0, width: width + (paper ? 180 : continuous ? 0 : 48), height: 80))
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        scroll.documentView = text
        text.isRichText = true
        text.isEditable = editable
        text.importsGraphics = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticTextCompletionEnabled = false
        text.textContainerInset = NSSize(width: paper ? 90 : continuous ? 0 : 24, height: paper ? paperTopInset : continuous ? 0 : 24)
        text.leadingAdjustment = paper ? 18 : 0
        if continuous {
            scroll.appearance = NSAppearance(named: .aqua)
            text.backgroundColor = .white
        }
        if paper {
            scroll.appearance = NSAppearance(named: .aqua)
            text.backgroundColor = .white
            text.minSize = NSSize(width: 612, height: 792)
            text.setFrameSize(NSSize(width: 612, height: 792))
        }
        text.isHorizontallyResizable = true
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        text.textContainer?.lineFragmentPadding = 0
        context.coordinator.suggestions = suggestions
        context.coordinator.explicitCharacters = explicitCharacters
        text.continuationSeed = continuationSeed
        text.screenplayController = controller
        text.delegate = context.coordinator
        controller.textView = text
        controller.minimumHeight = continuous ? typography.lineHeight : 48
        controller.contentWidth = width
        controller.typography = typography
        controller.completionRequest = { [weak coordinator = context.coordinator, weak text] in if let text { coordinator?.showSuggestions(text) } }
        context.coordinator.load(html, into: text)
        controller.measure()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.suggestions = suggestions
        context.coordinator.explicitCharacters = explicitCharacters
        context.coordinator.html = $html
        context.coordinator.onError = onError
        guard let text = scroll.documentView as? NSTextView else { return }
        text.isEditable = editable
        (text as? ScreenplayTextView)?.continuationSeed = continuationSeed
        controller.textView = text
        if controller.contentWidth != width || controller.typography != typography {
            controller.minimumHeight = continuous ? typography.lineHeight : 48
        controller.contentWidth = width
            controller.typography = typography
            text.textContainer?.containerSize.width = width
            context.coordinator.load(html, into: text)
        } else if context.coordinator.lastHTML != html { context.coordinator.load(html, into: text) }
        if let text = text as? ScreenplayTextView { DialoguePresentation.refresh(text) }
        controller.measure()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var html: Binding<String>
        let controller: ScreenplayEditorController
        var onError: (String) -> Void
        private(set) var lastHTML: String?
        var suggestions: [ScreenplayElement: [String]] = [:]
        private var completing = false
        private var loading = false
        private var pendingElement: ScreenplayElement?
        let completionPanel = HeadingSuggestionPanel()
        var registeredNames = Set<String>()
        var explicitCharacters = [String]()
        var offerCompletions = false
        init(html: Binding<String>, controller: ScreenplayEditorController, onError: @escaping (String) -> Void) {
            self.html = html
            self.controller = controller
            self.onError = onError
        }
        func showSuggestions(_ text: NSTextView) {
            let location = min(text.selectedRange().location, max(0, text.attributedString().length - 1))
            let excluded = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            registeredNames.formUnion(ScriptCueNames.committed(in: text.attributedString(), excluding: excluded))
            completionPanel.show(in: text, headings: (suggestions[.sceneHeading] ?? []).map { SceneHeading(inline: $0) }, names: registeredNames.union(explicitCharacters).sorted(), choices: suggestions)
        }

        func load(_ source: String, into text: NSTextView) {
            loading = true
            defer {
                loading = false
                // View updates may call load; publish the new format after that update completes.
                DispatchQueue.main.async { [weak controller = controller, weak text] in
                    guard let controller, controller.textView === text else { return }
                    controller.selectionChanged()
                }
            }
            do {
                let attributed = try ScreenplayTextCodec.decode(source, width: controller.contentWidth, settings: controller.typography)
                if lastHTML == nil { registeredNames.formUnion(suggestions[.character] ?? []) }
                text.textStorage?.setAttributedString(attributed)
                if let text = text as? ScreenplayTextView { DialoguePresentation.refresh(text) }
                text.setSelectedRange(NSRange(location: 0, length: 0))
                text.typingAttributes = ScreenplayTypography.attributes(
                    ScreenplayTextCodec.element(in: attributed, at: 0), width: controller.contentWidth, settings: controller.typography)
                lastHTML = source
                controller.measure()
            } catch {
                // Show the original source as a recoverable fallback; never silently blank an import.
                text.string = source
                lastHTML = source
                DispatchQueue.main.async { [onError] in onError("This scene could not be rendered as screenplay text: \(error.localizedDescription)") }
            }
        }

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange range: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let source = textView.string as NSString
            let paragraph = source.paragraphRange(for: range)
            let prefix = source.substring(with: NSRange(location: paragraph.location, length: NSMaxRange(range) - paragraph.location))
            let before = source.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location))
            index?.pointee = -1
            guard !prefix.isEmpty else { return [] }
            let choices = controller.activeElement == .sceneHeading
                ? SceneHeading.completions(for: prefix, headings: (suggestions[.sceneHeading] ?? []).map { SceneHeading(inline: $0) })
                : (suggestions[controller.activeElement] ?? []).filter { $0.lowercased().hasPrefix(prefix.lowercased()) && $0.lowercased() != prefix.lowercased() }
            if controller.activeElement == .sceneHeading, !choices.isEmpty { index?.pointee = 0 }
            return choices.map { String($0.dropFirst(before.count)) }
        }

        func textDidChange(_ notification: Notification) {
            guard !loading, let text = notification.object as? NSTextView, !text.hasMarkedText() else { return }
            // Rich clipboard data lacks our paragraph metadata. Keep the destination element
            // instead of turning pasted dialogue into action or retaining arbitrary clipboard sizes.
            if let storage = text.textStorage {
                loading = true
                var location = 0
                while location < storage.length {
                    let range = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
                    if storage.attribute(.screenplayElement, at: location, effectiveRange: nil) == nil {
                        ScreenplayTypography.apply(pendingElement ?? controller.activeElement, to: storage,
                            range: range, width: controller.contentWidth, settings: controller.typography)
                    }
                    location = NSMaxRange(range)
                }
                loading = false
            }
            pendingElement = nil
            loading = true; ScriptCueNames.capitalize(in: text); loading = false
            let result = ScreenplayTextCodec.encode(text.attributedString())
            lastHTML = result
            html.wrappedValue = result
            controller.selectionChanged()
            if let text = text as? ScreenplayTextView { DialoguePresentation.refresh(text) }
            controller.measure()
            text.scrollRangeToVisible(text.selectedRange())
            if offerCompletions, !completing { showSuggestions(text) } else { completionPanel.close() }
            offerCompletions = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if !loading { completionPanel.close(); controller.selectionChanged(); if let text = notification.object as? NSTextView, text.window?.firstResponder === text { text.scrollRangeToVisible(text.selectedRange()) } }
        }
        func textDidEndEditing(_ notification: Notification) { completionPanel.close() }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            if !loading { pendingElement = controller.activeElement; offerCompletions = replacementString?.isEmpty == false && replacementString?.contains("\n") != true }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if !textView.hasMarkedText(), completionPanel.handle(commandSelector) { return true }
            return controller.handleCommand(commandSelector, in: textView)
        }
    }
}
#endif
