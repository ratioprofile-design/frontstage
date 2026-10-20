import Foundation

/// Small deterministic ZIP writer for Office Open XML exports. Entries are stored without compression.
public enum OfficeArchive {
    public static func zip(_ files: [String: Data]) throws -> Data {
        guard files.count <= 10000, files.values.reduce(0, { $0 + $1.count }) <= 64 * 1024 * 1024,
              files.keys.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") && $0.utf8.count <= 65535 }) else { throw ProjectError.invalidProject("invalid office archive") }
        var output = Data(), central = Data()
        for name in files.keys.sorted() {
            let bytes = files[name]!, filename = Data(name.utf8), checksum = crc32(bytes), offset = UInt32(output.count)
            output.le32(0x04034b50); output.le16(20); output.le16(0x800); output.le16(0)
            output.le16(0); output.le16(33); output.le32(checksum); output.le32(UInt32(bytes.count)); output.le32(UInt32(bytes.count))
            output.le16(UInt16(filename.count)); output.le16(0); output.append(filename); output.append(bytes)
            central.le32(0x02014b50); central.le16(20); central.le16(20); central.le16(0x800); central.le16(0)
            central.le16(0); central.le16(33); central.le32(checksum); central.le32(UInt32(bytes.count)); central.le32(UInt32(bytes.count))
            central.le16(UInt16(filename.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0); central.le32(0); central.le32(offset); central.append(filename)
        }
        let centralOffset = UInt32(output.count); output.append(central)
        output.le32(0x06054b50); output.le16(0); output.le16(0); output.le16(UInt16(files.count)); output.le16(UInt16(files.count))
        output.le32(UInt32(central.count)); output.le32(centralOffset); output.le16(0)
        return output
    }

    public static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    public static func spreadsheet(rows: [[String]]) throws -> Data {
        guard rows.count <= 100000, rows.allSatisfy({ $0.count <= 16384 }) else { throw ProjectError.invalidProject("spreadsheet exceeds worksheet dimensions") }
        var sheet = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
        for (index, row) in rows.enumerated() {
            sheet += "<row r=\"\(index + 1)\">"
            for (column, value) in row.enumerated() {
                var n = column + 1, letters = ""
                while n > 0 { n -= 1; letters = String(UnicodeScalar(65 + n % 26)!) + letters; n /= 26 }
                // All values are strings, including text beginning with spreadsheet formula markers.
                sheet += "<c r=\"\(letters)\(index + 1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
            }
            sheet += "</row>"
        }
        sheet += "</sheetData></worksheet>"
        let types = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"
        return try zip([
            "[Content_Types].xml": Data(types.utf8),
            "_rels/.rels": Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>".utf8),
            "xl/workbook.xml": Data("<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Frontstage\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>".utf8),
            "xl/_rels/workbook.xml.rels": Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>".utf8),
            "xl/worksheets/sheet1.xml": Data(sheet.utf8)
        ])
    }

    public static func parseCSV(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false
        let characters = Array(text); var i = 0
        while i < characters.count {
            let c = characters[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < characters.count && characters[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "\"" {
                guard field.isEmpty && !closed else { throw ProjectError.invalidProject("unexpected quote in CSV") }; quoted = true
            } else if c == "," { row.append(field); field = ""; closed = false }
            else if c == "\n" || c == "\r" || c == "\r\n" {
                if c == "\r" && i + 1 < characters.count && characters[i + 1] == "\n" { i += 1 }
                row.append(field); rows.append(row); row = []; field = ""; closed = false
            } else {
                guard !closed || c == " " || c == "\t" else { throw ProjectError.invalidProject("characters after quoted CSV cell") }
                if !closed { field.append(c) }
            }
            i += 1
        }
        guard !quoted else { throw ProjectError.invalidProject("unterminated quoted CSV cell") }
        if !field.isEmpty || !row.isEmpty || closed { row.append(field); rows.append(row) }
        return rows
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xffffffff
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 0 ? 0 : 0xedb88320) }
        }
        return value ^ 0xffffffff
    }

    public static func save(_ data: Data, to url: URL, extension required: String) throws {
        let resolved = url.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == required, resolved.pathExtension.lowercased() == required else { throw ProjectError.legacyDestination }
        try data.write(to: resolved, options: .atomic)
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) { append(UInt8(value & 255)); append(UInt8((value >> 8) & 255)) }
    mutating func le32(_ value: UInt32) { le16(UInt16(value & 65535)); le16(UInt16((value >> 16) & 65535)) }
}
