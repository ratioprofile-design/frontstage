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

    func save(to url: URL) throws {
        let resolved = url.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "pdf", resolved.pathExtension.lowercased() == "pdf" else {
            throw ScreenplayPDFError.invalidDestination
        }
        try data.write(to: resolved, options: .atomic)
    }
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
                attributes: ScreenplayTypography.attributes(.sceneHeading, width: paper.contentWidth, printing: true)))
            let body = try ScreenplayTextCodec.decode(scene.html, width: paper.contentWidth, printing: true)
            text.append(body)
            if !text.string.hasSuffix("\n") {
                text.append(NSAttributedString(string: "\n", attributes:
                    ScreenplayTypography.attributes(.action, width: paper.contentWidth, printing: true)))
            }
        }
        let ranges = try paginate(text, paper: paper)
        let output = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: output) else { throw ScreenplayPDFError.cannotCreatePDF }
        var bounds = CGRect(x: 0, y: 0, width: paper.width, height: paper.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &bounds,
            [kCGPDFContextTitle as String: project.name, kCGPDFContextCreator as String: "Frontstage"] as CFDictionary) else {
            throw ScreenplayPDFError.cannotCreatePDF
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        for (index, range) in ranges.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(bounds)
            context.textMatrix = .identity
            let path = CGPath(rect: contentRect(paper), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: range.location, length: range.length), path, nil)
            CTFrameDraw(frame, context)
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
        return RenderedScreenplay(data: output as Data, text: text, pageRanges: ranges, paper: paper)
    }

    static func paginate(_ text: NSAttributedString, paper: ScreenplayPaper) throws -> [NSRange] {
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let path = CGPath(rect: contentRect(paper), transform: nil)
        let source = text.string as NSString
        var pages: [NSRange] = []
        var offset = 0
        while offset < text.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw ScreenplayPDFError.cannotLayOut }
            var end = min(text.length, offset + visible.length)
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
            guard end > offset else { throw ScreenplayPDFError.cannotLayOut }
            pages.append(NSRange(location: offset, length: end - offset))
            offset = end
        }
        return pages
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
