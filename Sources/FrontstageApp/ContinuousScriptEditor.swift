#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore
private let ownerKey = NSAttributedString.Key("FrontstageBeatOwner")
private let headingKey = NSAttributedString.Key("FrontstageSceneHeading")
struct ContinuousScriptEditor: NSViewRepresentable {
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: ScreenplayEditorController
    var width: CGFloat
    var zoom: Double
    func makeCoordinator() -> Coordinator { Coordinator(workspace, controller) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(), text = ScreenplayTextView()
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        text.isRichText = true; text.importsGraphics = false; text.allowsUndo = true; text.isAutomaticQuoteSubstitutionEnabled = false
        text.backgroundColor = .white; text.textColor = .black; text.isVerticallyResizable = true; text.isHorizontallyResizable = true
        text.textContainerInset = NSSize(width: 60, height: 60); text.textContainer?.widthTracksTextView = false
        text.screenplayController = controller; text.delegate = context.coordinator; controller.textView = text
        configure(text); context.coordinator.load(text); return scroll
    }
    private func configure(_ text: NSTextView) {
        controller.contentWidth = width * zoom
        var typography = workspace.project.scriptLayout; typography.fontSize *= zoom; typography.lineHeight *= zoom; typography.paragraphSpacing *= zoom; controller.typography = typography
        text.textContainer?.containerSize = NSSize(width: width * zoom, height: .greatestFiniteMagnitude)
        text.minSize = NSSize(width: width * zoom + 120, height: 792 * zoom); text.setFrameSize(NSSize(width: width * zoom + 120, height: max(text.frame.height, 792 * zoom)))
        text.isEditable = workspace.sharedProjects.linked?.access != "reader"
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let text = view.documentView as? NSTextView else { return }
        configure(text)
        let signature = context.coordinator.signature()
        if !context.coordinator.committing && !text.hasMarkedText() && signature != context.coordinator.lastSignature { context.coordinator.load(text) }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let workspace: Workspace; let controller: ScreenplayEditorController
        var committing = false, loading = false, completing = false, lastSignature = ""
        var visible = Set<String>()
        var pendingPullouts = Set<String>()
        init(_ workspace: Workspace, _ controller: ScreenplayEditorController) { self.workspace = workspace; self.controller = controller }
        func signature() -> String {
            String(describing: controller.typography) + String(describing: controller.contentWidth) + workspace.whiteboard.orderedBeats.filter { !$0.omitted && !workspace.whiteboard.isUnused($0) && workspace.reader.filters.matches($0, board: workspace.whiteboard, scenes: workspace.project.scenes) }.map { beat in beat.id + beat.html + (workspace.project.scenes.first { $0.id == beat.sceneID }?.heading.text ?? "") }.joined(separator: "\u{1f}")
        }
        func load(_ text: NSTextView) {
            loading = true; defer { loading = false }; visible.removeAll()
            let result = NSMutableAttributedString(string: "")
            for segment in (try? workspace.project.orderedScript()) ?? [] {
                let beats = segment.beatIDs.compactMap { id in workspace.whiteboard.beats.first { $0.id == id } }.filter { workspace.reader.filters.matches($0, board: workspace.whiteboard, scenes: workspace.project.scenes) }
                guard let first = beats.first else { continue }
                var attributes = ScreenplayTypography.attributes(.sceneHeading, width: controller.contentWidth, settings: controller.typography)
                attributes[ownerKey] = first.id; attributes[headingKey] = NSDecimalNumber(decimal: segment.scene.id).stringValue; attributes[.foregroundColor] = NSColor.black
                result.append(NSAttributedString(string: segment.scene.heading.text + "\n", attributes: attributes))
                for beat in beats {
                    visible.insert(beat.id)
                    let body = (try? ScreenplayTextCodec.decode(beat.html.isEmpty ? "<p class='sc-action'><br></p>" : beat.html, width: controller.contentWidth, printing: true, settings: controller.typography)) ?? NSMutableAttributedString(string: "\n")
                    if !body.string.hasSuffix("\n") { body.append(NSAttributedString(string: "\n", attributes: ScreenplayTypography.attributes(.action, width: controller.contentWidth, settings: controller.typography))) }
                    body.addAttribute(ownerKey, value: beat.id, range: NSRange(location: 0, length: body.length)); result.append(body)
                }
            }
            let selection = text.selectedRange(); text.textStorage?.setAttributedString(result)
            text.setSelectedRange(NSRange(location: min(selection.location, result.length), length: 0)); lastSignature = signature()
        }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView, !loading, !committing, !text.hasMarkedText() else { return }
            committing = true; defer { committing = false }
            loading = true; ScriptCueNames.capitalize(in: text); loading = false
            let source = text.attributedString(), string = source.string as NSString
            var html = Dictionary(uniqueKeysWithValues: visible.map { ($0, "") }), headings = [ScriptHeadingEdit](), owner: String?
            var location = 0
            while location < source.length {
                let range = string.paragraphRange(for: NSRange(location: location, length: 0)), attributes = source.attributes(at: location, effectiveRange: nil)
                owner = attributes[ownerKey] as? String ?? owner
                guard let id = owner else { location = NSMaxRange(range); continue }
                let line = string.substring(with: range).trimmingCharacters(in: .newlines)
                let kind = ScreenplayElement(rawValue: attributes[.screenplayElement] as? String ?? "action") ?? .action
                if let scene = attributes[headingKey] as? String, let sceneID = Decimal(string: scene), kind == .sceneHeading {
                    headings.append(ScriptHeadingEdit(sceneID: sceneID, text: line))
                } else if kind == .sceneHeading && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    let afterRange = NSRange(location: NSMaxRange(range), length: source.length - NSMaxRange(range))
                    let after = NSMutableAttributedString(string: "")
                    if afterRange.length > 0 { source.enumerateAttribute(ownerKey, in: afterRange) { value, run, stop in if value as? String == id { after.append(source.attributedSubstring(from: run)) } else if value != nil { stop.pointee = true } } }
                    workspace.edit("Insert Scene") { project in _ = try project.insertScriptScene(afterSplitting: id, beforeHTML: html[id] ?? "", afterHTML: ScreenplayTextCodec.encode(after), heading: line) }
                    load(text); return
                } else {
                    html[id, default: ""] += ScreenplayTextCodec.encode(source.attributedSubstring(from: range))
                    text.textStorage?.addAttribute(ownerKey, value: id, range: range)
                }
                location = NSMaxRange(range)
            }
            for id in pendingPullouts { html.removeValue(forKey: id) }
            workspace.edit("Screenplay", key: "continuous-script") { project in try project.applyScriptDocument(beatHTML: html, headings: headings); if !pendingPullouts.isEmpty { try project.pullOutBeats(pendingPullouts) } }
            visible.subtract(pendingPullouts); pendingPullouts.removeAll()
            lastSignature = signature(); controller.selectionChanged(); text.scrollRangeToVisible(text.selectedRange())
            if !completing, !(completionChoices[controller.activeElement] ?? []).isEmpty {
                completing = true; text.complete(nil); completing = false
            }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !loading, let text = notification.object as? NSTextView, !text.hasMarkedText() else { return }
            controller.selectionChanged()
            let index = min(text.selectedRange().location, max(0, text.attributedString().length - 1))
            if text.attributedString().length > 0, let id = text.attributedString().attribute(ownerKey, at: index, effectiveRange: nil) as? String {
                workspace.selectBoardBeat(id)
                if text.selectedRange().length > 0, let beat = workspace.whiteboard.beats.first(where: { $0.id == id }) { workspace.writingSelectedQuote = (beat.sceneID, (text.string as NSString).substring(with: text.selectedRange())) }
            }
        }
        var completionChoices: [ScreenplayElement: [String]] {
            var choices = workspace.screenplayCompletions
            choices[.sceneHeading] = Array(Set(workspace.project.scenes.map { $0.heading.text } + ["INT.", "EXT.", "INT./EXT."])).sorted()
            return choices
        }
        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange range: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let source = textView.string as NSString, paragraph = source.paragraphRange(for: range)
            let prefix = source.substring(with: NSRange(location: paragraph.location, length: NSMaxRange(range) - paragraph.location))
            let before = source.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location))
            index?.pointee = -1
            guard !prefix.isEmpty else { return [] }
            return (completionChoices[controller.activeElement] ?? []).filter { $0.lowercased().hasPrefix(prefix.lowercased()) && $0.lowercased() != prefix.lowercased() }.map { String($0.dropFirst(before.count)) }
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool { controller.handleCommand(commandSelector, in: textView) }
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            pendingPullouts.removeAll()
            let source = textView.attributedString(); guard source.length > 0 else { return true }
            var allowed = true
            let checked = NSRange(location: min(range.location, source.length - 1), length: max(1, min(range.length, source.length - min(range.location, source.length - 1))))
            source.enumerateAttribute(ownerKey, in: checked) { value, _, _ in
                if let id = value as? String, let beat = workspace.whiteboard.beats.first(where: { $0.id == id }), workspace.whiteboard.isLocked(beat) || workspace.project.scenes.first(where: { $0.id == beat.sceneID })?.isTextLocked == true { allowed = false }
            }
            if allowed, replacementString == "", range.length > 0 {
                var sceneRanges = [Decimal: NSRange]()
                source.enumerateAttribute(ownerKey, in: NSRange(location: 0, length: source.length)) { value, run, _ in
                    guard let id = value as? String, let beat = workspace.whiteboard.beats.first(where: { $0.id == id }) else { return }
                    sceneRanges[beat.sceneID] = sceneRanges[beat.sceneID].map { NSUnionRange($0, run) } ?? run
                }
                for (sceneID, sceneRange) in sceneRanges where range.location <= sceneRange.location && NSMaxRange(range) >= NSMaxRange(sceneRange) {
                    let owned = workspace.whiteboard.beats.filter { $0.sceneID == sceneID && !$0.omitted && !workspace.whiteboard.isUnused($0) }
                    if owned.allSatisfy({ visible.contains($0.id) }) { pendingPullouts.formUnion(owned.map(\.id)) }
                }
            }
            if !allowed { workspace.errorMessage = "This selection contains locked text." }; return allowed
        }
    }
}
#endif
