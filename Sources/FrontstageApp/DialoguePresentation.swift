#if os(macOS)
import AppKit
import FrontstageCore

struct DialoguePresentationToken {
    let range: NSRange
    let width: CGFloat
}

/// Inline presentation tokens live outside NSTextStorage's characters. Text input,
/// selection offsets, clipboard names, native undo, and saved HTML stay authored-only.
@MainActor
enum DialoguePresentation {
    private static let reservation = NSAttributedString.Key("FrontstageContinuationReservation")
    struct CachedBeat { let html: String; let lines: [(ScreenplayElement, String)] }
    static func projectFlags(_ project: Project, cache: inout [String: CachedBeat]) -> [String: [Bool]] {
        guard let board = try? project.whiteboard() else { return [:] }
        let beats = Dictionary(uniqueKeysWithValues: board.beats.map { ($0.id, $0) })
        cache = cache.filter { beats[$0.key] != nil }
        var flags = [String: [Bool]]()
        for segment in (try? project.orderedScript()) ?? [] {
            var tracker = DialogueContinuation()
            for id in segment.beatIDs {
                guard let beat = beats[id] else { continue }
                if cache[id]?.html != beat.html, let text = try? ScreenplayTextCodec.decode(beat.html) {
                    var location = 0, lines = [(ScreenplayElement, String)]()
                    while location < text.length {
                        let range = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
                        lines.append((ScreenplayTextCodec.element(in: text, at: location), (text.string as NSString).substring(with: range)))
                        location = NSMaxRange(range)
                    }
                    cache[id] = CachedBeat(html: beat.html, lines: lines)
                }
                for (kind, value) in cache[id]?.lines ?? [] {
                    let generated = tracker.observe(kind, text: value)
                    if kind == .character { flags[id, default: []].append(generated) }
                }
            }
        }
        return flags
    }
    static func ranges(in text: NSAttributedString, seed: String? = nil, byOwner flags: [String: [Bool]]? = nil) -> [NSRange] {
        var tracker = DialogueContinuation(lastSpeaker: seed), ranges = [NSRange](), location = 0
        var ordinals = [String: Int]()
        let string = text.string as NSString
        while location < text.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            let value = string.substring(with: paragraph).trimmingCharacters(in: .newlines)
            let kind = ScreenplayTextCodec.element(in: text, at: location)
            var generated = tracker.observe(kind, text: value)
            if kind == .character, let id = text.attribute(ScriptHeadingEditing.owner, at: location, effectiveRange: nil) as? String {
                let ordinal = ordinals[id, default: 0]; ordinals[id] = ordinal + 1
                if let owned = flags?[id], owned.indices.contains(ordinal) { generated = owned[ordinal] }
            }
            if generated {
                ranges.append(NSRange(location: location, length: value.utf16.count))
            }
            location = NSMaxRange(paragraph)
        }
        return ranges
    }
    static func refresh(_ text: ScreenplayTextView) {
        guard !text.hasMarkedText(), let storage = text.textStorage else { return }
        let generated = Dictionary(uniqueKeysWithValues: ranges(in: storage, seed: text.continuationSeed, byOwner: text.continuationFlags).map { ($0.location, $0) })
        var location = 0, tokens = [DialoguePresentationToken]()
        storage.beginEditing()
        while location < storage.length {
            let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            let kind = ScreenplayTextCodec.element(in: storage, at: location)
            let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
            let width = ceil((" (CONT'D)" as NSString).size(withAttributes: [.font: font]).width)
            let reserved = generated[location] != nil
            if kind == .character || storage.attribute(reservation, at: location, effectiveRange: nil) != nil {
                let style = (storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                let tail = reserved ? -width : kind == .dialogue ? -(text.screenplayController?.contentWidth ?? 432) * WorkspaceDesign.dialogueIndent / 100 : kind == .parenthetical ? -(text.screenplayController?.contentWidth ?? 432) * WorkspaceDesign.parentheticalRight / 100 : 0
                if style.tailIndent != tail { style.tailIndent = tail; storage.addAttribute(.paragraphStyle, value: style, range: paragraph) }
                if reserved { storage.addAttribute(reservation, value: true, range: paragraph) }
                else { storage.removeAttribute(reservation, range: paragraph) }
            }
            if let range = generated[location], range.length > 0 { tokens.append(DialoguePresentationToken(range: range, width: width)) }
            location = NSMaxRange(paragraph)
        }
        storage.endEditing()
        text.continuationTokens = tokens; text.needsDisplay = true
    }
    static func tokenRect(_ token: DialoguePresentationToken, in text: ScreenplayTextView) -> NSRect? {
        guard let manager = text.layoutManager, let container = text.textContainer, NSMaxRange(token.range) <= text.string.utf16.count else { return nil }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: NSMaxRange(token.range) - 1, length: 1), actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let glyph = manager.boundingRect(forGlyphRange: glyphs, in: container), line = manager.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        return NSRect(x: text.textContainerOrigin.x + glyph.maxX, y: text.textContainerOrigin.y + line.minY, width: token.width, height: line.height)
    }
    static func draw(in text: ScreenplayTextView, dirty: NSRect) {
        for token in text.continuationTokens {
            guard let rect = tokenRect(token, in: text), rect.intersects(dirty) else { continue }
            let font = text.attributedString().attribute(.font, at: token.range.location, effectiveRange: nil) as? NSFont ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
            (" (CONT'D)" as NSString).draw(at: rect.origin, withAttributes: [.font: font, .foregroundColor: text.textColor ?? .textColor])
        }
    }
    static func materialized(_ original: NSAttributedString, seed: String? = nil) -> NSMutableAttributedString {
        let output = NSMutableAttributedString(attributedString: original)
        for range in ranges(in: original, seed: seed).reversed() {
            var attributes = original.attributes(at: range.location, effectiveRange: nil)
            if let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle { style.tailIndent = 0; attributes[.paragraphStyle] = style }
            if let style = attributes[.paragraphStyle] { output.addAttribute(.paragraphStyle, value: style, range: (original.string as NSString).paragraphRange(for: range)) }
            output.insert(NSAttributedString(string: " (CONT'D)", attributes: attributes), at: NSMaxRange(range))
        }
        return output
    }
    static func seed(project: Project, beatID: String) -> String? {
        for segment in (try? project.orderedScript()) ?? [] {
            var tracker = DialogueContinuation()
            for id in segment.beatIDs {
                if id == beatID { return tracker.lastSpeaker }
                guard let beat = try? project.whiteboard().beats.first(where: { $0.id == id }), let text = try? ScreenplayTextCodec.decode(beat.html) else { continue }
                var location = 0
                while location < text.length {
                    let range = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
                    tracker.observe(ScreenplayTextCodec.element(in: text, at: location), text: (text.string as NSString).substring(with: range))
                    location = NSMaxRange(range)
                }
            }
        }
        return nil
    }
}
#endif
