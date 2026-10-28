import Foundation

public enum ScriptAnnotations {
    public static let highlights = ["Yellow": "#fff0a6", "Green": "#bde9bf", "Blue": "#b9dcff", "Pink": "#f7c3dd", "Orange": "#ffd2a1", "Purple": "#d9c5f7"]
    public static let categoryColors: [String: String] = Dictionary(uniqueKeysWithValues: zip(["CAST","EXTRAS","STUNTS","VEHICLES","PROPS","SFX","WARDROBE","MAKEUP","ANIMALS","SOUND","SET_DRESSING","GREENERY","SPECIAL_EQUIPMENT","LIGHTING_GRIP","SAFETY"], (0..<15).map { ["#fff0a6","#bde9bf","#b9dcff","#f7c3dd","#ffd2a1","#d9c5f7"][$0 % 6] }))
    public static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["']([A-Za-z0-9_-]{1,120})["']"#, options: .caseInsensitive), let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)), let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }
    public static func ids(in html: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\bdata-dot-breakdown\s*=\s*["']([A-Za-z0-9_-]{1,120})["']"#) else { return [] }
        let source = html as NSString
        return Set(regex.matches(in: html, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range(at: 1)) })
    }
    public static func remap(_ html: String, ids: [String: String]) -> String {
        var result = html
        for (old, new) in ids where old != new {
            for quote in ["\"", "'"] { result = result.replacingOccurrences(of: "data-dot-breakdown=\(quote)\(old)\(quote)", with: "data-dot-breakdown=\(quote)\(new)\(quote)") }
        }
        return result
    }
    public static func normalize(_ html: String, categories: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<span\b[^>]*>"#, options: .caseInsensitive) else { return html }
        let result = NSMutableString(string: html)
        for match in regex.matches(in: html, range: NSRange(location: 0, length: result.length)).reversed() {
            var tag = result.substring(with: match.range)
            guard let id = attribute("data-dot-breakdown", in: tag) else { continue }
            tag = tag.replacingOccurrences(of: #"\sdata-dot-category\s*=\s*["'][^"']*["']"#, with: "", options: .regularExpression)
            if let category = categories[id] { let safe = category.range(of: #"^[A-Za-z0-9_-]{1,120}$"#, options: .regularExpression) != nil ? category : "IMPORTED"; tag = String(tag.dropLast()) + " data-dot-category=\"\(safe)\">" }
            else { tag = tag.replacingOccurrences(of: #"\sdata-dot-breakdown\s*=\s*["'][^"']*["']"#, with: "", options: .regularExpression) }
            result.replaceCharacters(in: match.range, with: tag)
        }
        return result as String
    }
}

extension Project {
    public func hasBreakdownSource(_ id: String, sceneID: Decimal) -> Bool {
        let board = (state["frontstageWhiteboard"]?.object?["beats"]?.array ?? []).filter { $0.object?["sceneID"]?.decimal == sceneID }
        let archived = (state["frontstagePullouts"]?.array ?? []).compactMap { $0.object?["beat"] }.filter { $0.object?["sceneID"]?.decimal == sceneID }
        return (board + archived).contains { ScriptAnnotations.ids(in: $0.object?["html"]?.string ?? "").contains(id) } || ScriptAnnotations.ids(in: headingMarkup(sceneID) ?? "").contains(id)
    }
    public func headingMarkup(_ sceneID: Decimal) -> String? { (state["beats"]?.array ?? []).first(where: { $0.object?["id"]?.decimal == sceneID })?.object?["frontstageHeadingMarkup"]?.string }
    public mutating func setHeadingMarkup(_ sceneID: Decimal, html: String?) {
        guard var scenes = state["beats"]?.array, let index = scenes.firstIndex(where: { $0.object?["id"]?.decimal == sceneID }), var fields = scenes[index].object else { return }
        fields["frontstageHeadingMarkup"] = html.map(JSONValue.string); scenes[index] = .object(fields); state["beats"] = .array(scenes)
    }
    /// Run inside an editing transaction, never on open. Requirements follow sources across splits.
    public mutating func reconcileScriptAnnotations() {
        guard var scenes = state["beats"]?.array else { return }
        let boardValues: [JSONValue] = state["frontstageWhiteboard"]?.object?["beats"]?.array ?? []
        let pullouts: [JSONValue] = state["frontstagePullouts"]?.array ?? []
        var rawHTML: [String] = boardValues.compactMap { $0.object?["html"]?.string }
        rawHTML += pullouts.compactMap { $0.object?["beat"]?.object?["html"]?.string }
        for scene in scenes { rawHTML.append(scene.object?["content"]?.string ?? ""); rawHTML.append(scene.object?["frontstageHeadingMarkup"]?.string ?? "") }
        guard rawHTML.contains(where: { $0.contains("data-dot-") }) else { return }
        struct Entry { var scene: Int; var storage: String; var bucket: String; var record: [String: JSONValue] }
        func catalog(_ scenes: [JSONValue]) -> [String: Entry] {
            var result = [String: Entry]()
            for (index, scene) in scenes.enumerated() { for storage in ["breakdown", "breakdownData"] { for (bucket, values) in scene.object?[storage]?.object ?? [:] { for value in values.array ?? [] { if let record = value.object, let id = record["id"]?.string { result[id] = Entry(scene: index, storage: storage, bucket: bucket, record: record) } } } } }
            return result
        }
        var board = state["frontstageWhiteboard"]?.object
        var beats = board?["beats"]?.array ?? []
        var archive = state["frontstagePullouts"]?.array ?? []
        let activeCount = beats.count
        beats += archive.compactMap { $0.object?["beat"] }
        var entries = catalog(scenes), owners = [String: Set<Decimal>]()
        for scene in scenes { if let sceneID = scene.object?["id"]?.decimal { for id in ScriptAnnotations.ids(in: scene.object?["frontstageHeadingMarkup"]?.string ?? "") { owners[id, default: []].insert(sceneID) } } }
        for beat in beats { if let sceneID = beat.object?["sceneID"]?.decimal { for id in ScriptAnnotations.ids(in: beat.object?["html"]?.string ?? "") { owners[id, default: []].insert(sceneID) } } }
        for index in beats.indices {
            guard var fields = beats[index].object, let sceneID = fields["sceneID"]?.decimal, let destination = scenes.firstIndex(where: { $0.object?["id"]?.decimal == sceneID }) else { continue }
            var html = fields["html"]?.string ?? "", mappings = [String: String]()
            for id in ScriptAnnotations.ids(in: html) {
                guard let entry = entries[id], entry.scene != destination else { continue }
                let sourceID = scenes[entry.scene].object?["id"]?.decimal
                guard scenes[destination].object?["frontstageTextLocked"] != .bool(true) else { continue }
                let moving = (sourceID.map { owners[id]?.contains($0) != true } ?? false) && scenes[entry.scene].object?["frontstageTextLocked"] != .bool(true)
                var record = entry.record
                let newID = moving ? id : UUID().uuidString
                record["id"] = .string(newID)
                if !moving { record["frontstageSourceID"] = .string(id) }
                guard scenes[destination].object?[entry.storage] == nil || scenes[destination].object?[entry.storage]?.object != nil else { continue }
                var target = scenes[destination].object!, storage = target[entry.storage]?.object ?? [:], values = storage[entry.bucket]?.array ?? []
                values.append(.object(record)); storage[entry.bucket] = .array(values); target[entry.storage] = .object(storage); scenes[destination] = .object(target)
                if moving { var source = scenes[entry.scene].object!, fields = source[entry.storage]?.object ?? [:]; fields[entry.bucket] = .array((fields[entry.bucket]?.array ?? []).filter { $0.object?["id"]?.string != id }); source[entry.storage] = .object(fields); scenes[entry.scene] = .object(source) }
                mappings[id] = newID; entries[newID] = Entry(scene: destination, storage: entry.storage, bucket: entry.bucket, record: record)
            }
            html = ScriptAnnotations.remap(html, ids: mappings); fields["html"] = .string(html); beats[index] = .object(fields)
        }
        let categories = catalog(scenes).mapValues { $0.record["category"]?.string ?? $0.bucket }
        for index in beats.indices { if var fields = beats[index].object { fields["html"] = .string(ScriptAnnotations.normalize(fields["html"]?.string ?? "", categories: categories)); beats[index] = .object(fields) } }
        if board != nil { board?["beats"] = .array(Array(beats.prefix(activeCount))); state["frontstageWhiteboard"] = board.map(JSONValue.object) }
        for index in archive.indices { if var item = archive[index].object, activeCount + index < beats.count { item["beat"] = beats[activeCount + index]; archive[index] = .object(item) } }
        if state["frontstagePullouts"] != nil { state["frontstagePullouts"] = .array(archive) }
        for index in scenes.indices { if var fields = scenes[index].object { for key in ["content", "frontstageHeadingMarkup"] { if let html = fields[key]?.string { fields[key] = .string(ScriptAnnotations.normalize(html, categories: categories)) } }; scenes[index] = .object(fields) } }
        state["beats"] = .array(scenes)
    }
}
