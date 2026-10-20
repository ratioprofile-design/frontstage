#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

@MainActor
final class ScreenplayEditorController: ObservableObject {
    @Published private(set) var activeElement = ScreenplayElement.action
    weak var textView: NSTextView?
    var contentWidth: CGFloat = 432
    var typography = ScriptLayoutSettings()

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
        guard let textView, !textView.hasMarkedText() else { return }
        textView.window?.makeFirstResponder(textView)
        let selection = textView.selectedRange()
        let range = (textView.string as NSString).paragraphRange(for: selection)
        if range.length > 0 {
            let replacement = NSMutableAttributedString(attributedString: textView.attributedString().attributedSubstring(from: range))
            ScreenplayTypography.apply(element, to: replacement,
                range: NSRange(location: 0, length: replacement.length), width: contentWidth, settings: typography)
            // NSTextView's insertion API participates in native undo, unlike direct storage mutations.
            textView.insertText(replacement, replacementRange: range)
            textView.setSelectedRange(selection)
        }
        textView.typingAttributes = ScreenplayTypography.attributes(element, width: contentWidth, settings: typography)
        activeElement = element
    }

    @discardableResult
    func handleCommand(_ selector: Selector, in textView: NSTextView) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)) {
            format(activeElement.cycled(backward: selector == #selector(NSResponder.insertBacktab(_:))))
            return true
        }
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let selected = textView.selectedRange()
        let paragraph = (textView.string as NSString).paragraphRange(for: selected)
        let line = (textView.string as NSString).substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
        let next = activeElement.afterReturn(isEmpty: line.isEmpty)
        if line.isEmpty, activeElement != .action {
            format(.action)
            return true
        }
        // A literal insertion bypasses command dispatch and leaves IME composition to TextKit.
        let attributes = ScreenplayTypography.attributes(next, width: contentWidth, settings: typography)
        textView.insertText(NSAttributedString(string: "\n", attributes: attributes), replacementRange: selected)
        let caret = textView.selectedRange()
        let nextRange = (textView.string as NSString).paragraphRange(for: caret)
        if nextRange.length > 0 {
            let replacement = NSMutableAttributedString(attributedString: textView.attributedString().attributedSubstring(from: nextRange))
            ScreenplayTypography.apply(next, to: replacement,
                range: NSRange(location: 0, length: replacement.length), width: contentWidth, settings: typography)
            textView.insertText(replacement, replacementRange: nextRange)
            textView.setSelectedRange(caret)
        }
        textView.typingAttributes = attributes
        activeElement = next
        return true
    }
}

struct ScreenplayEditor: NSViewRepresentable {
    @Binding var html: String
    @ObservedObject var controller: ScreenplayEditorController
    var width: CGFloat = 432
    var typography = ScriptLayoutSettings()
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(html: $html, controller: controller, onError: onError) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let text = scroll.documentView as? NSTextView else { return scroll }
        text.isRichText = true
        text.importsGraphics = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.textContainerInset = NSSize(width: 24, height: 24)
        text.isHorizontallyResizable = true
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        text.textContainer?.lineFragmentPadding = 0
        text.delegate = context.coordinator
        controller.textView = text
        controller.contentWidth = width
        controller.typography = typography
        context.coordinator.load(html, into: text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.html = $html
        context.coordinator.onError = onError
        guard let text = scroll.documentView as? NSTextView else { return }
        controller.textView = text
        if controller.contentWidth != width || controller.typography != typography {
            controller.contentWidth = width
            controller.typography = typography
            text.textContainer?.containerSize.width = width
            context.coordinator.load(html, into: text)
        } else if context.coordinator.lastHTML != html { context.coordinator.load(html, into: text) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var html: Binding<String>
        let controller: ScreenplayEditorController
        var onError: (String) -> Void
        private(set) var lastHTML: String?
        private var loading = false
        private var pendingElement: ScreenplayElement?
        init(html: Binding<String>, controller: ScreenplayEditorController, onError: @escaping (String) -> Void) {
            self.html = html
            self.controller = controller
            self.onError = onError
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
                text.textStorage?.setAttributedString(attributed)
                text.setSelectedRange(NSRange(location: 0, length: 0))
                text.typingAttributes = ScreenplayTypography.attributes(
                    ScreenplayTextCodec.element(in: attributed, at: 0), width: controller.contentWidth, settings: controller.typography)
                lastHTML = source
            } catch {
                // Show the original source as a recoverable fallback; never silently blank an import.
                text.string = source
                lastHTML = source
                DispatchQueue.main.async { [onError] in onError("This scene could not be rendered as screenplay text: \(error.localizedDescription)") }
            }
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
            let result = ScreenplayTextCodec.encode(text.attributedString())
            lastHTML = result
            html.wrappedValue = result
            controller.selectionChanged()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if !loading { controller.selectionChanged() }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            if !loading { pendingElement = controller.activeElement }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            controller.handleCommand(commandSelector, in: textView)
        }
    }
}
#endif
