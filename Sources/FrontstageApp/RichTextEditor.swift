#if os(macOS)
import AppKit
import SwiftUI

/// Native TextKit editing. Untouched imported HTML remains byte-for-byte in the model;
/// editing reserializes the scene's rich text through AppKit, not a browser or JavaScript.
struct RichTextEditor: NSViewRepresentable {
    @Binding var html: String

    func makeCoordinator() -> Coordinator { Coordinator(html: $html) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let text = scroll.documentView as? NSTextView else { return scroll }
        text.isRichText = true
        text.importsGraphics = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.textContainerInset = NSSize(width: 24, height: 24)
        text.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        text.delegate = context.coordinator
        context.coordinator.load(html, into: text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.html = $html
        guard let text = scroll.documentView as? NSTextView,
              context.coordinator.lastHTML != html else { return }
        context.coordinator.load(html, into: text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var html: Binding<String>
        var lastHTML: String?
        private var loading = false
        init(html: Binding<String>) { self.html = html }

        func load(_ source: String, into text: NSTextView) {
            loading = true
            defer { loading = false }
            lastHTML = source
            if let data = source.data(using: .utf8),
               let attributed = try? NSAttributedString(data: data, options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
               ], documentAttributes: nil) {
                text.textStorage?.setAttributedString(attributed)
            } else {
                text.string = source
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !loading, let text = notification.object as? NSTextView,
                  let storage = text.textStorage,
                  let data = try? storage.data(from: NSRange(location: 0, length: storage.length),
                      documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
                  let result = String(data: data, encoding: .utf8) else { return }
            lastHTML = result
            html.wrappedValue = result
        }
    }
}
#endif
