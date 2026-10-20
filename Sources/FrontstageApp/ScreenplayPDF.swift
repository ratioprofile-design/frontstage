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
}

@MainActor
enum ScreenplayPDF {
    static func render(project: Project, paper: ScreenplayPaper) throws -> RenderedScreenplay {
        let active = project.scenes.filter { !$0.isDisabled }
        guard !active.isEmpty else { throw ScreenplayPDFError.noScenes }
        let text = NSMutableAttributedString(string: "")
        for (index, scene) in active.enumerated() {
            let number = scene.sceneNumber.isEmpty ? String(index + 1) : scene.sceneNumber
            text.append(NSAttributedString(string: "\(number)  \(scene.heading.text)\n",
                attributes: ScreenplayTypography.attributes(.sceneHeading, width: paper.contentWidth, printing: true, settings: project.scriptLayout)))
            let body = try ScreenplayTextCodec.decode(scene.html, width: paper.contentWidth, printing: true, settings: project.scriptLayout)
            text.append(body)
            if !text.string.hasSuffix("\n") {
                text.append(NSAttributedString(string: "\n", attributes:
                    ScreenplayTypography.attributes(.action, width: paper.contentWidth, printing: true)))
            }
        }
        return try renderText(text, title: project.name, paper: paper)
    }

    static func renderText(_ text: NSAttributedString, title: String, paper: ScreenplayPaper) throws -> RenderedScreenplay {
        guard text.length > 0 else { throw ScreenplayPDFError.cannotLayOut }
        let pages = try layoutPages(text, paper: paper)
        let output = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: output) else { throw ScreenplayPDFError.cannotCreatePDF }
        var bounds = CGRect(x: 0, y: 0, width: paper.width, height: paper.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &bounds,
            [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Frontstage"] as CFDictionary) else {
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
                drawMarker("\(character) (CONT'D)", x: paper.leftMargin + paper.contentWidth * 0.37,
                    y: paper.height - paper.topMargin - 12, in: context, paper: paper)
            }
            if page.continuesCharacter != nil {
                drawMarker("(MORE)", x: paper.leftMargin + paper.contentWidth * 0.37,
                    y: paper.bottomMargin + 2, in: context, paper: paper)
            }
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

    static func paginate(_ text: NSAttributedString, paper: ScreenplayPaper) throws -> [NSRange] {
        try layoutPages(text, paper: paper).map(\.range)
    }

    static func layoutPages(_ text: NSAttributedString, paper: ScreenplayPaper) throws -> [ScreenplayPageLayout] {
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let source = text.string as NSString
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
                return source.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " (CONT'D)", with: "").uppercased()
            }
            if type != .dialogue && type != .parenthetical { return nil }
            location = previous.location
        }
        return nil
    }

    private static func drawMarker(_ value: String, x: CGFloat, y: CGFloat, in context: CGContext, paper: ScreenplayPaper) {
        let label = NSAttributedString(string: value, attributes:
            ScreenplayTypography.attributes(.character, width: paper.contentWidth, printing: true))
        let line = CTLineCreateWithAttributedString(label as CFAttributedString)
        let width = paper.width - paper.rightMargin - x
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
