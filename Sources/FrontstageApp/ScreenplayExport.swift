#if os(macOS)
import AppKit
import FrontstageCore
import UniformTypeIdentifiers

@MainActor
enum ScreenplayInterchangeDocument {
    static func paragraphs(_ project: Project) throws -> [ScreenplayExportParagraph] {
        var paragraphs = [ScreenplayExportParagraph]()
        for segment in try project.orderedScript() {
            paragraphs.append(.init(element: .sceneHeading, runs: [.init(segment.scene.heading.text + (segment.isContinuation ? " (CONTINUED)" : ""))], number: segment.number))
            let body = DialoguePresentation.materialized(try ScreenplayTextCodec.decode(segment.scene.html, settings: project.scriptLayout))
            let source = body.string as NSString; var offset = 0
            while offset < body.length {
                let range = source.paragraphRange(for: NSRange(location: offset, length: 0))
                var end = NSMaxRange(range)
                while end > range.location && [10,13,0x2028,0x2029].contains(source.character(at: end - 1)) { end -= 1 }
                var runs = [ScreenplayExportRun]()
                body.enumerateAttributes(in: NSRange(location: offset, length: end - offset)) { attributes, run, _ in
                    let traits = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
                    runs.append(.init(source.substring(with: run), bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask), underline: (attributes[.underlineStyle] as? Int ?? 0) != 0))
                }
                paragraphs.append(.init(element: ScreenplayTextCodec.element(in: body, at: offset), runs: runs, dualPair: body.attribute(.screenplayDualPair, at: offset, effectiveRange: nil) as? String, dualSide: body.attribute(.screenplayDualDialogue, at: offset, effectiveRange: nil) as? String))
                offset = NSMaxRange(range)
            }
        }
        return paragraphs
    }
}
extension Workspace {
    func exportFDX() { exportInterchange(fountain: false) }
    func exportFountain() { exportInterchange(fountain: true) }
    private func exportInterchange(fountain: Bool) {
        do {
            endScriptTypingGroup()
            let paragraphs = try ScreenplayInterchangeDocument.paragraphs(project)
            let content = try (fountain ? ScreenplayInterchange.fountain(paragraphs) : ScreenplayInterchange.fdx(paragraphs))
            let ext = fountain ? "fountain" : "fdx"
            let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? (fountain ? .plainText : .xml)]
            panel.nameFieldStringValue = project.name.replacingOccurrences(of: "/", with: "-") + "." + ext
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try Data(content.utf8).write(to: url, options: .atomic)
        } catch { errorMessage = error.localizedDescription }
    }
}
#endif
