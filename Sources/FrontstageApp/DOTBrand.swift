#if os(macOS)
import AppKit
import SwiftUI

/// Product presentation is independent of the stable bundle/storage/project identities.
enum DOTTheme {
    static var accent: Color { Color(nsColor: .controlAccentColor) }
    static func iconResource(for appearance: NSAppearance) -> String {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dot-app-dark" : "dot-app-light"
    }
}
@MainActor
final class DOTBrandController {
    private var observation: NSKeyValueObservation?
    func start() {
        refresh()
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    func refresh() {
        let resource = DOTTheme.iconResource(for: NSApp.effectiveAppearance)
        if let url = Bundle.main.url(forResource: resource, withExtension: "png"), let image = NSImage(contentsOf: url) { NSApp.applicationIconImage = image }
    }
}
struct DOTWordmark: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        if let url = Bundle.main.url(forResource: colorScheme == .dark ? "wordmark-dark" : "wordmark-light", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 80, height: 24).accessibilityLabel("DOT")
        } else { Text("DOT").bold().accessibilityLabel("DOT") }
    }
}
#endif
