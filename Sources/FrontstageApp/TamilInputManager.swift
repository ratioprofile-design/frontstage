#if os(macOS)
import Foundation
import Carbon
import AppKit

@MainActor
enum TamilInputManager {
    private static weak var trackedText: NSTextView?
    private static var previousInputSource: TISInputSource?
    private static var isTamilActive = false

    /// Checks if a given input source represents Tamil
    static func isTamilSource(_ source: TISInputSource) -> Bool {
        let id = inputSourceID(source)
        let name = inputSourceName(source)
        if id.localizedCaseInsensitiveContains("tamil") || name.localizedCaseInsensitiveContains("tamil") {
            return true
        }
        if id.hasSuffix(".ta") || id.contains(".ta.") || id.contains("TransliterationIM.ta") {
            return true
        }
        return false
    }

    /// Changes only a focused, composing-free editor, and only when the user opted in.
    static func update(for text: NSTextView, enabled: Bool) {
        guard text.window?.firstResponder === text else { return }
        guard !text.hasMarkedText(), trackedText?.hasMarkedText() != true else { return }
        trackedText = text
        if text.isEditable && enabled && UserDefaults.standard.bool(forKey: "dot_switch_tamil_input") { activateTamilInput() } else { restoreStandardInput() }
    }
    static func compositionEnded(in text: NSTextView) {
        guard trackedText === text, !text.hasMarkedText() else { return }
        if !NSApp.isActive || text.window?.firstResponder !== text { restoreStandardInput() }
    }
    static func activateTamilInput() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              !isTamilSource(current), let tamil = findTamilInputSource() else { return }
        // Preserve the previous source only after a successful switch.
        if TISSelectInputSource(tamil) == noErr { previousInputSource = current; isTamilActive = true }
    }
    static func restoreStandardInput() {
        guard trackedText?.hasMarkedText() != true else { return }
        guard let previous = previousInputSource else { return }
        defer { previousInputSource = nil; isTamilActive = false; trackedText = nil }
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), isTamilSource(current) else { return }
        TISSelectInputSource(previous)
    }

    private static func findTamilInputSource() -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        for source in list {
            let isSelectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)
            let isSelectable = isSelectablePtr != nil && (Unmanaged<CFBoolean>.fromOpaque(isSelectablePtr!).takeUnretainedValue() == kCFBooleanTrue)
            guard isSelectable else { continue }

            if isTamilSource(source) {
                return source
            }
        }
        return nil
    }

    private static func inputSourceID(_ source: TISInputSource) -> String {
        let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        return idPtr != nil ? (Unmanaged<CFString>.fromOpaque(idPtr!).takeUnretainedValue() as String) : ""
    }

    private static func inputSourceName(_ source: TISInputSource) -> String {
        let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
        return namePtr != nil ? (Unmanaged<CFString>.fromOpaque(namePtr!).takeUnretainedValue() as String) : ""
    }
}
#endif
