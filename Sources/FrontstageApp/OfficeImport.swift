#if os(macOS)
import Foundation
import AppKit
import UniformTypeIdentifiers
import FrontstageCore

enum OfficeZIP {
    /// Read only a named Office XML member; never extract paths supplied by an archive.
    static func member(_ name: String, from url: URL, required: Bool = true) throws -> Data {
        guard ["word/document.xml", "xl/sharedStrings.xml", "xl/worksheets/sheet1.xml"].contains(name) else { throw ProjectError.invalidProject("unsupported archive member") }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, name]; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
            guard data.count + chunk.count <= 32 * 1024 * 1024 else { process.terminate(); process.waitUntilExit(); throw ProjectError.invalidProject("decompressed document exceeds the 32 MB import limit") }
            data.append(chunk)
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 && required { throw ProjectError.invalidProject("the Office archive has no supported document or first worksheet") }
        return data
    }
}

final class WordStylesParser: NSObject, XMLParserDelegate {
    var styles: [ScreenplayElement] = []
    private var current = ScreenplayElement.action
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "w:p" { current = .action }
        if name == "w:pStyle", let raw = attributes["w:val"] { current = ScreenplayElement(rawValue: raw) ?? .action }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { if name == "w:p" { styles.append(current) } }
}

final class SheetParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    var rows: [[String]] = []
    var shared: [String] = []
    private var stack: [String] = []
    private var value = "", sharedString = "", cellType = "", cellReference = ""
    private var row: [String] = []
    private var invalid = false
    private var totalCells = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append(name)
        if name == "si" { sharedString = "" }
        if name == "row" { row = [] }
        if name == "c" { value = ""; cellType = attributes["t"] ?? ""; cellReference = attributes["r"] ?? "" }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        if stack.last == "t" && stack.contains("si") { sharedString += text }
        if (stack.last == "v" || stack.last == "t") && stack.contains("c") { value += text }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "si" { strings.append(sharedString); if strings.count > 1_000_000 { invalid = true; parser.abortParsing(); return } }
        if name == "c" {
            var column = 0
            for character in cellReference.uppercased().unicodeScalars where (65...90).contains(character.value) {
                column = column * 26 + Int(character.value - 64)
                if column > 16384 { invalid = true; parser.abortParsing(); return }
            }
            column = column == 0 ? row.count : column - 1
            if column >= 16384 || totalCells + column + 1 > 1_000_000 { invalid = true; parser.abortParsing(); return }
            while row.count <= column { row.append("") }
            if cellType == "s", let index = Int(value), shared.indices.contains(index) { row[column] = shared[index] }
            else { row[column] = value }
        }
        if name == "row" {
            rows.append(row)
            totalCells += row.count
            if rows.count > 100000 { invalid = true; parser.abortParsing(); return }
        }
        _ = stack.popLast()
    }
    func parse(_ data: Data) throws {
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = self
        guard parser.parse(), !invalid else { throw ProjectError.invalidProject("unsupported or oversized worksheet XML") }
    }
}

@MainActor
enum OfficeImport {
    static func docx(_ url: URL) throws -> NSAttributedString {
        let source = try OfficeZIP.member("word/document.xml", from: url)
        let styles = WordStylesParser(), parser = XMLParser(data: source)
        parser.shouldResolveExternalEntities = false; parser.delegate = styles
        guard parser.parse() else { throw ProjectError.invalidProject("invalid DOCX document XML") }
        let text = NSMutableAttributedString(attributedString: try NSAttributedString(url: url, options: [:], documentAttributes: nil))
        let string = text.string as NSString
        var offset = 0, paragraphs: [NSRange] = []
        while offset < string.length { let range = string.paragraphRange(for: NSRange(location: offset, length: 0)); paragraphs.append(range); offset = NSMaxRange(range) }
        if paragraphs.count == styles.styles.count {
            for (range, type) in zip(paragraphs, styles.styles) { ScreenplayTypography.apply(type, to: text, range: range, width: 432) }
        }
        return text
    }
    static func spreadsheet(_ url: URL) throws -> [[String]] {
        if url.pathExtension.lowercased() == "csv" { return try OfficeArchive.parseCSV(String(contentsOf: url, encoding: .utf8)) }
        let shared = SheetParser(), data = try OfficeZIP.member("xl/sharedStrings.xml", from: url, required: false)
        if !data.isEmpty { try shared.parse(data) }
        let sheet = SheetParser(); sheet.shared = shared.strings
        try sheet.parse(OfficeZIP.member("xl/worksheets/sheet1.xml", from: url))
        return sheet.rows
    }
}

extension Workspace {
    func importSpreadsheet() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText, UTType(filenameExtension: "xlsx") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            guard (size?.intValue ?? Int.max) <= 10 * 1024 * 1024 else { throw ProjectError.invalidProject("spreadsheet exceeds the 10 MB attachment limit") }
            let rows = try OfficeImport.spreadsheet(url), source = try Data(contentsOf: url)
            var created: String?
            edit("Import Spreadsheet") { project in
                let id = try project.addStudioRecord(kind: .research, title: url.deletingPathExtension().lastPathComponent); created = id
                try project.updateStudioRecord(id) { $0.body = ProductionCSV.encode(rows); $0.fields["Category"] = "Imported spreadsheet (first worksheet)" }
                _ = try project.attachStudioAsset(to: id, filename: url.lastPathComponent, data: source)
            }
            selectedResearchID = created; mode = .studio
        } catch { errorMessage = error.localizedDescription }
    }
}
#endif
