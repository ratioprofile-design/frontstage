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
    var historyBoundary: (() -> Void)?
    private var commandDepth = 0
    func command<T>(_ action: () -> T) -> T {
        let outer = commandDepth == 0
        if outer { historyBoundary?() }
        commandDepth += 1
        defer { commandDepth -= 1; if outer { historyBoundary?() } }
        return action()
    }
    var newScene: ((NSTextView) -> Void)?
    var dismissCompletions: (() -> Void)?
    private var acceptedCue: (range: NSRange, value: String, caret: NSRange)?
    func clearAcceptedCue() { acceptedCue = nil }
    func acceptCharacterSuggestion(in text: NSTextView) {
        let paragraph = (text.string as NSString).paragraphRange(for: text.selectedRange())
        let value = (text.string as NSString).substring(with: paragraph)
        acceptedCue = (paragraph, value, text.selectedRange())
    }
    var projectUndo: (() -> Void)?
    var projectRedo: (() -> Void)?
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
        if let accepted = acceptedCue {
            let source = textView.string as NSString
            if textView.selectedRange() != accepted.caret || NSMaxRange(accepted.range) > source.length || source.substring(with: accepted.range) != accepted.value { clearAcceptedCue() }
        }
        let element: ScreenplayElement
        if textView.selectedRange().location == textView.string.utf16.count,
           let type = textView.typingAttributes[.screenplayElement] as? String {
            element = ScreenplayElement(rawValue: type) ?? .action
        } else {
            element = ScreenplayTextCodec.element(in: textView.attributedString(), at: textView.selectedRange().location)
        }
        if activeElement != element { activeElement = element }
        TamilInputManager.update(for: textView, enabled: typography.isTamil(for: element))
    }

    func format(_ element: ScreenplayElement) { command { formatParagraph(element) } }
    private func formatParagraph(_ element: ScreenplayElement) {
        clearAcceptedCue()
        guard let textView, textView.isEditable, !textView.hasMarkedText() else { return }
        textView.window?.makeFirstResponder(textView)
        var selection = textView.selectedRange()
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
            if element == .parenthetical {
                let value = replacement.string.trimmingCharacters(in: .newlines), empty = value.trimmingCharacters(in: .whitespaces).isEmpty
                let attributes = replacement.attributes(at: 0, effectiveRange: nil)
                if empty {
                    replacement.replaceCharacters(in: NSRange(location: 0, length: value.utf16.count), with: NSAttributedString(string: "()", attributes: attributes))
                    selection = NSRange(location: range.location + 1, length: 0)
                } else {
                    if !value.hasSuffix(")") { replacement.insert(NSAttributedString(string: ")", attributes: attributes), at: value.utf16.count) }
                    if !value.hasPrefix("(") { replacement.insert(NSAttributedString(string: "(", attributes: attributes), at: 0); selection.location += 1 }
                }
            }
            // NSTextView's insertion API participates in native undo, unlike direct storage mutations.
            textView.insertText(replacement, replacementRange: range)
            textView.setSelectedRange(selection)
        }
        var typing = ScreenplayTypography.attributes(element, width: contentWidth, settings: typography)
        let source = textView.attributedString()
        if source.length > 0, let owner = source.attribute(ScriptHeadingEditing.owner, at: min(selection.location, source.length - 1), effectiveRange: nil) { typing[ScriptHeadingEditing.owner] = owner }
        textView.typingAttributes = typing
        activeElement = element
        if range.length == 0, element == .parenthetical { textView.insertText(NSAttributedString(string: "()", attributes: typing), replacementRange: selection); textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0)) }
    }

    func handleParentheticalInput(_ value: String?, range: NSRange, in text: NSTextView) -> Bool {
        guard text.isEditable, !text.hasMarkedText(), range.length == 0 else { return false }
        let source = text.string as NSString, paragraph = source.paragraphRange(for: range)
        selectionChanged()
        if activeElement == .parenthetical, source.substring(with: paragraph).trimmingCharacters(in: .newlines) == "()", range.location == paragraph.location + 1, let value, value.hasPrefix("(") {
            if value != "(" { let wrapped = ScreenplayParenthetical.wrapped(value); text.insertText(wrapped, replacementRange: NSRange(location: paragraph.location, length: 2)); text.setSelectedRange(NSRange(location: paragraph.location + wrapped.utf16.count - 1, length: 0)) }
            return true
        }
        if value == "(", activeElement == .dialogue, source.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { format(.parenthetical); return true }
        if value == ")", activeElement == .parenthetical, range.location < source.length, source.character(at: range.location) == 41 { text.setSelectedRange(NSRange(location: range.location + 1, length: 0)); return true }
        return false
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
    func handleCommand(_ selector: Selector, in textView: NSTextView, forcedKey: String? = nil) -> Bool {
        command { resolveCommand(selector, in: textView, forcedKey: forcedKey) }
    }
    private func resolveCommand(_ selector: Selector, in textView: NSTextView, forcedKey: String? = nil) -> Bool {
        guard textView.isEditable, !textView.hasMarkedText() else { return false }
        selectionChanged()
        if selector == #selector(NSResponder.deleteBackward(_:)), activeElement == .parenthetical {
            let selection = textView.selectedRange(), paragraph = (textView.string as NSString).paragraphRange(for: selection)
            if selection.length == 0, selection.location == paragraph.location + 1,
               (textView.string as NSString).substring(with: paragraph).trimmingCharacters(in: .newlines) == "()" {
                textView.insertText("", replacementRange: NSRange(location: paragraph.location, length: 2)); format(.dialogue); return true
            }
        }
        let key: String
        if let forcedKey { key = forcedKey } else { switch selector {
        case #selector(NSResponder.insertTab(_:)): key = "Tab"
        case #selector(NSResponder.insertBacktab(_:)): key = "Backtab"
        case #selector(NSResponder.insertNewline(_:)): key = "Enter"
        default: return false
        } }
        selectionChanged()
        if key == "Tab", activeElement == .character, acceptedCue != nil {
            let range = (textView.string as NSString).paragraphRange(for: textView.selectedRange())
            let value = (textView.string as NSString).substring(with: range).trimmingCharacters(in: .newlines)
            clearAcceptedCue()
            textView.undoManager?.beginUndoGrouping(); defer { textView.undoManager?.endUndoGrouping() }
            textView.insertText("", replacementRange: NSRange(location: range.location, length: value.utf16.count))
            format(.transition); return true
        }
        clearAcceptedCue()
        if ["Enter", "ForceAction", "Tab"].contains(key), activeElement == .parenthetical {
            let line = (textView.string as NSString).paragraphRange(for: textView.selectedRange())
            let value = (textView.string as NSString).substring(with: line).trimmingCharacters(in: .newlines)
            if !ScreenplayParenthetical.isEmpty(value), ScreenplayParenthetical.wrapped(value) != value { format(.parenthetical) }
        }
        let selected = textView.selectedRange()
        let source = textView.attributedString(), string = source.string as NSString
        let paragraph = string.paragraphRange(for: NSRange(location: selected.location, length: 0))
        let value = string.substring(with: paragraph).trimmingCharacters(in: .newlines)
        let empty = activeElement == .parenthetical ? ScreenplayParenthetical.isEmpty(value) : value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let decision = ScreenplayCommand.resolve(element: activeElement, key: key, empty: empty, selection: selected.length > 0)
        if decision.placement == .newScene { dismissCompletions?(); if let newScene { newScene(textView) } else { textView.insertText("\n", replacementRange: NSRange(location: NSMaxRange(paragraph), length: 0)); format(.sceneHeading) }; return true }
        if decision.placement == .suggestions { completionRequest?(); return true }
        textView.undoManager?.beginUndoGrouping(); defer { textView.undoManager?.endUndoGrouping() }
        if decision.placement == .inPlace {
            if activeElement == .parenthetical, empty, decision.element != .parenthetical {
                textView.insertText("", replacementRange: NSRange(location: paragraph.location, length: value.utf16.count))
                textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
            }
            format(decision.element); return true
        }
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
        if next == .parenthetical { format(.parenthetical) }
        return true
    }
}

class ScreenplayTextView: NSTextView {
    weak var screenplayController: ScreenplayEditorController?
    var splitScene: (() -> Void)?
    var duplicateBeat: (() -> Void)?
    var openBeat: (() -> Void)?
    private func historyKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z", !hasMarkedText(), let controller = screenplayController else { return false }
        let action = event.modifierFlags.contains(.shift) ? controller.projectRedo : controller.projectUndo
        guard let action else { return false }; controller.clearAcceptedCue(); controller.dismissCompletions?(); action(); return true
    }
    private func screenplayKey(_ event: NSEvent) -> Bool {
        guard !hasMarkedText(), isEditable, let controller = screenplayController else { return false }
        let modified = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
        if modified, event.keyCode == 36, !event.modifierFlags.contains(.shift) {
            controller.dismissCompletions?(); controller.clearAcceptedCue()
            return controller.handleCommand(#selector(NSResponder.insertNewline(_:)), in: self, forcedKey: "ForceAction")
        }
        if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers, let index = Int(key), (1...8).contains(index) {
            controller.dismissCompletions?(); controller.clearAcceptedCue(); controller.format(ScreenplayElement.editable[index - 1]); return true
        }
        if event.charactersIgnoringModifiers != "\t" { controller.clearAcceptedCue() }
        return false
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { historyKey(event) || screenplayKey(event) || super.performKeyEquivalent(with: event) }
    override func keyDown(with event: NSEvent) { if !historyKey(event) && !screenplayKey(event) { super.keyDown(with: event) } }
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
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned && !hasMarkedText() { TamilInputManager.restoreStandardInput() }
        return resigned
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if screenplayController?.projectUndo != nil {
            let undo = NSMenuItem(title: "Undo", action: #selector(undoProjectContext), keyEquivalent: ""); undo.target = self; menu.addItem(undo)
            let redo = NSMenuItem(title: "Redo", action: #selector(redoProjectContext), keyEquivalent: ""); redo.target = self; menu.addItem(redo)
        }
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
        if duplicateBeat != nil { let item = NSMenuItem(title: "Duplicate Beat", action: #selector(duplicateWriteBeat), keyEquivalent: ""); item.target = self; item.isEnabled = isEditable; menu.addItem(item) }
        if openBeat != nil { let item = NSMenuItem(title: "Open Beat Editor", action: #selector(openWriteBeat), keyEquivalent: ""); item.target = self; menu.addItem(item) }
        return menu
    }
    @objc private func undoProjectContext() { screenplayController?.projectUndo?() }
    @objc private func redoProjectContext() { screenplayController?.projectRedo?() }
    @objc private func duplicateWriteBeat() { duplicateBeat?() }
    @objc private func openWriteBeat() { openBeat?() }
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
        controller.dismissCompletions = { [weak coordinator = context.coordinator] in coordinator?.completionPanel.close() }
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
            loading = true; ScriptCueNames.capitalize(in: text, settings: controller.typography); loading = false
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
        func textDidEndEditing(_ notification: Notification) { completionPanel.close(); controller.clearAcceptedCue() }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            if !loading { controller.clearAcceptedCue() }
            if !loading, controller.handleParentheticalInput(replacementString, range: affectedCharRange, in: textView) { return false }
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
