#if os(macOS)
import AppKit
import CoreText
import PDFKit
import SwiftUI
import FrontstageCore

enum ScreenplayPDFError: Error, LocalizedError {
    case noScenes, cannotLayOut, cannotCreatePDF, invalidDestination
    var errorDescription: String? {
        switch self {
        case .noScenes: return "Add an active scene before previewing or printing the screenplay."
        case .cannotLayOut: return "A screenplay paragraph could not fit on the selected paper."
        case .cannotCreatePDF: return "The screenplay PDF could not be created."
        case .invalidDestination: return "Choose a .pdf destination that does not point to a project file."
        }
    }
}

@MainActor
struct RenderedScreenplay {
    let data: Data
    let text: NSAttributedString
    let pageRanges: [NSRange]
    let paper: ScreenplayPaper
    let pages: [ScreenplayPageLayout]

    func save(to url: URL) throws {
        let resolved = url.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "pdf", resolved.pathExtension.lowercased() == "pdf" else {
            throw ScreenplayPDFError.invalidDestination
        }
        try data.write(to: resolved, options: .atomic)
    }
}

struct ScreenplayPageLayout {
    let range: NSRange
    let rect: CGRect
    let continuedCharacter: String?
    let continuesCharacter: String?
    var sourceRanges: [NSRange] = []
}

@MainActor
enum ScreenplayPDF {
    private static let explicitPageStart = NSAttributedString.Key("design.ratioprofile.frontstage.pageStart")
    static func render(project: Project, paper: ScreenplayPaper) throws -> RenderedScreenplay {
        _ = try ScreenplayInterchange.fdx(ScreenplayInterchangeDocument.paragraphs(project))
        let active = try project.orderedScript()
        guard !active.isEmpty else { throw ScreenplayPDFError.noScenes }
        let text = NSMutableAttributedString(string: "")
        for segment in active {
            let scene = segment.scene, number = segment.number
            let headingStart = text.length
            text.append(NSAttributedString(string: "\(number)  \(scene.heading.text)\(segment.isContinuation ? " (CONTINUED)" : "")\(project.productionSceneChanged(scene.id) ? " *" : "")\n",
                attributes: ScreenplayTypography.attributes(.sceneHeading, width: paper.contentWidth, printing: true, settings: project.scriptLayout)))
            if scene.startsNewPage { text.addAttribute(explicitPageStart, value: true, range: NSRange(location: headingStart, length: 1)) }
            let body = try ScreenplayTextCodec.decode(scene.html, width: paper.contentWidth, printing: true, settings: project.scriptLayout)
            if body.length > 0 { body.addAttribute(NSAttributedString.Key("FrontstageBeatOwner"), value: "pdf-scene-\(text.length)", range: NSRange(location: 0, length: body.length)) }
            text.append(body)
            if !text.string.hasSuffix("\n") {
                text.append(NSAttributedString(string: "\n", attributes:
                    ScreenplayTypography.attributes(.action, width: paper.contentWidth, printing: true)))
            }
        }
        return try renderText(text, title: project.name, paper: paper, revisionHeader: project.currentRevision?.headerString)
    }

    static func renderText(_ text: NSAttributedString, title: String, paper: ScreenplayPaper, revisionHeader: String? = nil) throws -> RenderedScreenplay {
        let text = DialoguePresentation.materialized(text)
        guard text.length > 0 else { throw ScreenplayPDFError.cannotLayOut }
        if text.length > 0, text.containsAttribute(.screenplayDualPair) {
            return try renderDualText(text, title: title, paper: paper, revisionHeader: revisionHeader)
        }
        let pages = try layoutPages(text, paper: paper)
        let output = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: output) else { throw ScreenplayPDFError.cannotCreatePDF }
        var bounds = CGRect(x: 0, y: 0, width: paper.width, height: paper.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &bounds,
            [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "DOT"] as CFDictionary) else {
            throw ScreenplayPDFError.cannotCreatePDF
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        for (index, page) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(bounds)
            context.textMatrix = .identity
            let path = CGPath(rect: page.rect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: page.range.location, length: page.range.length), path, nil)
            CTFrameDraw(frame, context)
            if let character = page.continuedCharacter {
                drawMarker("\(character) (CONT'D)", x: paper.leftMargin + paper.contentWidth * WorkspaceDesign.characterIndent / 100,
                    y: paper.height - paper.topMargin - 12, in: context, paper: paper)
            }
            if page.continuesCharacter != nil {
                drawMarker("(MORE)", x: paper.leftMargin + paper.contentWidth * WorkspaceDesign.characterIndent / 100,
                    y: paper.bottomMargin + 2, in: context, paper: paper)
            }
            if let revisionHeader { drawMarker(revisionHeader, x: paper.leftMargin, y: paper.height - 42, in: context, paper: paper) }
            if index > 0 {
                let label = NSAttributedString(string: "\(index + 1).", attributes:
                    ScreenplayTypography.attributes(.action, width: paper.contentWidth, printing: true))
                let line = CTLineCreateWithAttributedString(label as CFAttributedString)
                let labelWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
                context.textPosition = CGPoint(x: paper.width - paper.rightMargin - labelWidth, y: paper.height - 42)
                CTLineDraw(line, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return RenderedScreenplay(data: output as Data, text: text, pageRanges: pages.map(\.range), paper: paper, pages: pages)
    }

    private struct FlowFragment { let range: NSRange; let rect: CGRect }
    private struct FlowMarker { let cue: String; let value: String; let x: CGFloat; let header: Bool; let width: CGFloat? }
    private struct FlowPage {
        var fragments = [FlowFragment]()
        var markers = [FlowMarker]()
        var used: CGFloat = 0
        var range: NSRange {
            guard let first = fragments.map(\.range.location).min(), let end = fragments.map({ NSMaxRange($0.range) }).max() else { return NSRange(location: 0, length: 0) }
            return NSRange(location: first, length: end - first)
        }
    }
    private struct FlowUnit { let range: NSRange; let right: Int?; let forced: Bool }
    private static func dualFlow(_ original: NSAttributedString, paper: ScreenplayPaper) throws -> (text: NSMutableAttributedString, pages: [FlowPage]) {
        let text = NSMutableAttributedString(attributedString: original), source = text.string as NSString
        let columnWidth = (paper.contentWidth - 24) / 2
        var units = [FlowUnit](), offset = 0
        while offset < text.length {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            let pair = text.attribute(.screenplayDualPair, at: offset, effectiveRange: nil) as? String
            let owner = text.attribute(NSAttributedString.Key("FrontstageBeatOwner"), at: offset, effectiveRange: nil) as? String
            let forced = text.attribute(explicitPageStart, at: offset, effectiveRange: nil) as? Bool == true
            if let pair {
                var end = offset, right: Int?
                while end < text.length, text.attribute(.screenplayDualPair, at: end, effectiveRange: nil) as? String == pair,
                      (text.attribute(NSAttributedString.Key("FrontstageBeatOwner"), at: end, effectiveRange: nil) as? String) == owner {
                    let range = source.paragraphRange(for: NSRange(location: end, length: 0))
                    if text.attribute(.screenplayDualDialogue, at: end, effectiveRange: nil) as? String == "right", right == nil { right = end }
                    let element = ScreenplayTextCodec.element(in: text, at: end)
                    let style = (text.attribute(.paragraphStyle, at: end, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    let geometry = ScreenplayTypography.attributes(element, width: columnWidth)[.paragraphStyle] as! NSParagraphStyle
                    style.headIndent = geometry.headIndent; style.firstLineHeadIndent = geometry.firstLineHeadIndent; style.tailIndent = geometry.tailIndent; style.textBlocks = []
                    text.addAttribute(.paragraphStyle, value: style, range: range)
                    end = NSMaxRange(range)
                }
                guard let right, right > offset, right < end else { throw ScreenplayPDFError.cannotLayOut }
                units.append(FlowUnit(range: NSRange(location: offset, length: end - offset), right: right, forced: forced)); offset = end
            } else {
                if let previous = units.last, previous.right == nil, !forced {
                    units[units.count - 1] = FlowUnit(range: NSRange(location: previous.range.location, length: NSMaxRange(paragraph) - previous.range.location), right: nil, forced: previous.forced)
                } else { units.append(FlowUnit(range: paragraph, right: nil, forced: forced)) }
                offset = NSMaxRange(paragraph)
            }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        var pages = [FlowPage]()
        var page = FlowPage()
        func nextPage() { if !page.fragments.isEmpty { pages.append(page) }; page = FlowPage() }
        func fit(_ range: NSRange, x: CGFloat, width: CGFloat, used: CGFloat, keep: Bool = true) -> (fragment: FlowFragment?, consumed: CGFloat) {
            let height = paper.contentHeight - used - 14
            guard range.length > 0, height > 0 else { return (nil, 0) }
            let rect = CGRect(x: x, y: paper.height - paper.topMargin - used - height, width: width, height: height)
            var end = range.location
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: range.location, length: range.length), CGPath(rect: rect, transform: nil), nil)
            end += min(range.length, CTFrameGetVisibleStringRange(frame).length)
            guard end > range.location else { return (nil, 0) }
            if keep, end < NSMaxRange(range) {
                while end > range.location {
                    let last = source.paragraphRange(for: NSRange(location: end - 1, length: 0))
                    guard ScreenplayTextCodec.element(in: text, at: last.location).keepsWithNext else { break }
                    end = last.location
                }
                if end <= range.location { return (nil, 0) }
            }
            let fitted = NSRange(location: range.location, length: end - range.location)
            let measured = CTFramesetterCreateFrame(framesetter, CFRange(location: fitted.location, length: fitted.length), CGPath(rect: rect, transform: nil), nil)
            let lines = CTFrameGetLines(measured) as! [CTLine]
            guard let last = lines.last else { return (nil, 0) }
            var origins = Array(repeating: CGPoint.zero, count: lines.count)
            CTFrameGetLineOrigins(measured, CFRange(location: 0, length: 0), &origins)
            var descent: CGFloat = 0
            _ = CTLineGetTypographicBounds(last, nil, &descent, nil)
            let paragraph = source.paragraphRange(for: NSRange(location: end - 1, length: 0))
            let spacing = NSMaxRange(paragraph) == end ? (text.attribute(.paragraphStyle, at: end - 1, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing ?? 0 : 0
            return (FlowFragment(range: fitted, rect: rect), min(height, max(1, height - origins[origins.count - 1].y + descent + spacing)))
        }
        func marker(_ cue: String, x: CGFloat, header: Bool, width: CGFloat? = nil) { page.markers.append(FlowMarker(cue: cue, value: header ? cue + " (CONT'D)" : "(MORE)", x: x, header: header, width: width)) }
        func startingSpeechHeight(_ start: Int, end: Int) -> CGFloat {
            var position = start, height: CGFloat = 0
            while position < end {
                let range = source.paragraphRange(for: NSRange(location: position, length: 0))
                let element = ScreenplayTextCodec.element(in: text, at: position)
                if element.keepsWithNext {
                    height += CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: position, length: min(range.length, end - position)), nil, CGSize(width: columnWidth, height: .greatestFiniteMagnitude), nil).height
                } else {
                    let style = text.attribute(.paragraphStyle, at: position, effectiveRange: nil) as? NSParagraphStyle
                    height += max(14, style?.minimumLineHeight ?? 14); break
                }
                position = NSMaxRange(range)
            }
            return height + 14
        }
        for (unitIndex, unit) in units.enumerated() {
            if unit.forced && !page.fragments.isEmpty { nextPage() }
            if let right = unit.right {
                let starts = [unit.range.location, right], ends = [right, NSMaxRange(unit.range)]
                let cues = starts.map { CharacterCue(source.substring(with: source.paragraphRange(for: NSRange(location: $0, length: 0)))).withoutContinuation }
                var cursors = starts
                while cursors[0] < ends[0] || cursors[1] < ends[1] {
                    let continued = (0...1).filter { cursors[$0] > starts[$0] && cursors[$0] < ends[$0] }
                    if page.fragments.isEmpty && !continued.isEmpty { page.used = 28 }
                    let fits = (0...1).map { index in fit(NSRange(location: cursors[index], length: ends[index] - cursors[index]), x: paper.leftMargin + CGFloat(index) * (columnWidth + 24), width: columnWidth, used: page.used) }
                    let stalled = (0...1).contains { cursors[$0] < ends[$0] && fits[$0].fragment == nil }
                    if stalled {
                        if !page.fragments.isEmpty { nextPage(); continue }
                        throw ScreenplayPDFError.cannotLayOut
                    }
                    for index in continued { marker(cues[index], x: paper.leftMargin + CGFloat(index) * (columnWidth + 24) + columnWidth * WorkspaceDesign.characterIndent / 100, header: true, width: columnWidth * (1 - WorkspaceDesign.characterIndent / 100)) }
                    for index in 0...1 {
                        if let fragment = fits[index].fragment { page.fragments.append(fragment); cursors[index] = NSMaxRange(fragment.range) }
                    }
                    page.used += max(fits[0].consumed, fits[1].consumed)
                    if cursors[0] < ends[0] || cursors[1] < ends[1] {
                        for index in 0...1 where cursors[index] < ends[index] { marker(cues[index], x: paper.leftMargin + CGFloat(index) * (columnWidth + 24) + columnWidth * WorkspaceDesign.characterIndent / 100, header: false, width: columnWidth * (1 - WorkspaceDesign.characterIndent / 100)) }
                        nextPage()
                    }
                }
            } else {
                var cursor = unit.range.location
                while cursor < NSMaxRange(unit.range) {
                    if page.fragments.isEmpty, let cue = continuingCharacter(in: text, at: cursor) {
                        page.used = 28; marker(cue, x: paper.leftMargin + paper.contentWidth * WorkspaceDesign.characterIndent / 100, header: true)
                    }
                    var result = fit(NSRange(location: cursor, length: NSMaxRange(unit.range) - cursor), x: paper.leftMargin, width: paper.contentWidth, used: page.used)
                    guard var fragment = result.fragment else {
                        if !page.fragments.isEmpty { nextPage(); continue }
                        throw ScreenplayPDFError.cannotLayOut
                    }
                    if NSMaxRange(fragment.range) == NSMaxRange(unit.range), unitIndex + 1 < units.count, units[unitIndex + 1].right != nil,
                       paper.contentHeight - page.used - result.consumed < max(startingSpeechHeight(units[unitIndex + 1].range.location, end: units[unitIndex + 1].right!), startingSpeechHeight(units[unitIndex + 1].right!, end: NSMaxRange(units[unitIndex + 1].range))) {
                        let last = source.paragraphRange(for: NSRange(location: NSMaxRange(fragment.range) - 1, length: 0))
                        if ScreenplayTextCodec.element(in: text, at: last.location).keepsWithNext {
                            if last.location == cursor { if !page.fragments.isEmpty { nextPage(); continue } }
                            else {
                                result = fit(NSRange(location: cursor, length: last.location - cursor), x: paper.leftMargin, width: paper.contentWidth, used: page.used)
                                if let shortened = result.fragment { fragment = shortened }
                            }
                        }
                    }
                    page.fragments.append(fragment); page.used += result.consumed; cursor = NSMaxRange(fragment.range)
                    if cursor < NSMaxRange(unit.range) {
                        if let cue = continuingCharacter(in: text, at: cursor) { marker(cue, x: paper.leftMargin + paper.contentWidth * WorkspaceDesign.characterIndent / 100, header: false) }
                        nextPage()
                    }
                }
            }
        }
        nextPage()
        return (text, pages)
    }
    private static func renderDualText(_ original: NSAttributedString, title: String, paper: ScreenplayPaper, revisionHeader: String?) throws -> RenderedScreenplay {
        let flow = try dualFlow(original, paper: paper)
        let output = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: output) else { throw ScreenplayPDFError.cannotCreatePDF }
        var bounds = CGRect(x: 0, y: 0, width: paper.width, height: paper.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &bounds, [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "DOT"] as CFDictionary) else { throw ScreenplayPDFError.cannotCreatePDF }
        let framesetter = CTFramesetterCreateWithAttributedString(flow.text as CFAttributedString)
        for (index, page) in flow.pages.enumerated() {
            context.beginPDFPage(nil); context.setFillColor(NSColor.white.cgColor); context.fill(bounds); context.textMatrix = .identity
            for fragment in page.fragments { CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: fragment.range.location, length: fragment.range.length), CGPath(rect: fragment.rect, transform: nil), nil), context) }
            for marker in page.markers { drawMarker(marker.value, x: marker.x, y: marker.header ? paper.height - paper.topMargin - 12 : paper.bottomMargin + 2, in: context, paper: paper, maxWidth: marker.width) }
            if let revisionHeader { drawMarker(revisionHeader, x: paper.leftMargin, y: paper.height - 42, in: context, paper: paper, maxWidth: paper.contentWidth - 36) }
            if index > 0 { drawMarker("\(index + 1).", x: paper.width - paper.rightMargin - 24, y: paper.height - 42, in: context, paper: paper) }
            context.endPDFPage()
        }
        context.closePDF()
        let pages = flow.pages.map { ScreenplayPageLayout(range: $0.range, rect: contentRect(paper), continuedCharacter: $0.markers.first(where: \.header)?.cue, continuesCharacter: $0.markers.first(where: { !$0.header })?.cue, sourceRanges: $0.fragments.map(\.range)) }
        return RenderedScreenplay(data: output as Data, text: flow.text, pageRanges: pages.map(\.range), paper: paper, pages: pages)
    }

    static func paginate(_ text: NSAttributedString, paper: ScreenplayPaper) throws -> [NSRange] {
        try layoutPages(text, paper: paper).map(\.range)
    }

    static func layoutPages(_ text: NSAttributedString, paper: ScreenplayPaper) throws -> [ScreenplayPageLayout] {
        if text.containsAttribute(.screenplayDualPair) {
            return try dualFlow(text, paper: paper).pages.map { ScreenplayPageLayout(range: $0.range, rect: contentRect(paper), continuedCharacter: nil, continuesCharacter: nil, sourceRanges: $0.fragments.map(\.range)) }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let source = text.string as NSString
        var forcedStarts: [Int] = []
        text.enumerateAttribute(explicitPageStart, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value as? Bool == true { forcedStarts.append(range.location) }
        }
        var pages: [ScreenplayPageLayout] = []
        var offset = 0
        while offset < text.length {
            let header = offset > 0 ? continuingCharacter(in: text, at: offset) : nil
            var reserveFooter = false
            var rect = contentRect(paper)
            var end = offset
            for _ in 0..<2 {
                rect = contentRect(paper)
                if header != nil { rect.size.height -= 28 }
                if reserveFooter { rect.origin.y += 14; rect.size.height -= 14 }
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0),
                    CGPath(rect: rect, transform: nil), nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { throw ScreenplayPDFError.cannotLayOut }
                end = min(text.length, offset + visible.length)
                if let forced = forcedStarts.first(where: { $0 > offset && $0 < end }) { end = forced }
                if end < text.length {
                // Avoid stranding a scene heading, character cue or parenthetical at the bottom.
                // A chain (heading -> character -> parenthetical) moves together when necessary.
                    var candidate = end
                    while candidate > offset {
                        let last = source.paragraphRange(for: NSRange(location: candidate - 1, length: 0))
                        if last.location <= offset || !ScreenplayTextCodec.element(in: text, at: last.location).keepsWithNext { break }
                        candidate = last.location
                    }
                    if candidate > offset { end = candidate }
                }
                if end < text.length, continuingCharacter(in: text, at: end) != nil, !reserveFooter {
                    reserveFooter = true
                    continue
                }
                break
            }
            guard end > offset else { throw ScreenplayPDFError.cannotLayOut }
            pages.append(ScreenplayPageLayout(range: NSRange(location: offset, length: end - offset), rect: rect,
                continuedCharacter: header, continuesCharacter: end < text.length ? continuingCharacter(in: text, at: end) : nil))
            offset = end
        }
        return pages
    }

    private static func continuingCharacter(in text: NSAttributedString, at offset: Int) -> String? {
        guard offset < text.length,
              [.dialogue, .parenthetical].contains(ScreenplayTextCodec.element(in: text, at: offset)) else { return nil }
        let source = text.string as NSString
        var location = source.paragraphRange(for: NSRange(location: offset, length: 0)).location
        while location > 0 {
            let previous = source.paragraphRange(for: NSRange(location: location - 1, length: 0))
            let type = ScreenplayTextCodec.element(in: text, at: previous.location)
            if type == .character {
                return CharacterCue(source.substring(with: previous)).withoutContinuation.uppercased()
            }
            if type != .dialogue && type != .parenthetical { return nil }
            location = previous.location
        }
        return nil
    }

    private static func drawMarker(_ value: String, x: CGFloat, y: CGFloat, in context: CGContext, paper: ScreenplayPaper, maxWidth: CGFloat? = nil) {
        let label = NSAttributedString(string: value, attributes:
            ScreenplayTypography.attributes(.character, width: paper.contentWidth, printing: true))
        let line = CTLineCreateWithAttributedString(label as CFAttributedString)
        let width = min(maxWidth ?? .greatestFiniteMagnitude, paper.width - paper.rightMargin - x)
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes:
            ScreenplayTypography.attributes(.character, width: paper.contentWidth, printing: true)) as CFAttributedString)
        let fitted = CTLineCreateTruncatedLine(line, width, .end, ellipsis) ?? line
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(fitted, context)
    }

    private static func contentRect(_ paper: ScreenplayPaper) -> CGRect {
        CGRect(x: paper.leftMargin, y: paper.bottomMargin, width: paper.contentWidth, height: paper.contentHeight)
    }
}

struct ScreenplayPDFView: NSViewRepresentable {
    let document: PDFDocument
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = document
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
#endif

#if os(macOS)
private extension NSAttributedString {
    func containsAttribute(_ key: NSAttributedString.Key) -> Bool {
        var found = false
        enumerateAttribute(key, in: NSRange(location: 0, length: length)) { value, _, stop in if value != nil { found = true; stop.pointee = true } }
        return found
    }
}
#endif
