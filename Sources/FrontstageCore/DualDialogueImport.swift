import Foundation

public enum DualDialogueImport {
    public static func duplicatedPairIDs(_ html: String) -> String {
        guard let pattern = try? NSRegularExpression(pattern: #"(?i)\bdata-dual-pair\s*=\s*["']([^"']+)["']"#) else { return html }
        let source = html as NSString, output = NSMutableString(string: html)
        var replacements = [String: String]()
        let matches = pattern.matches(in: html, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let id = source.substring(with: match.range(at: 1))
            let next = replacements[id] ?? UUID().uuidString; replacements[id] = next
            output.replaceCharacters(in: match.range(at: 1), with: next)
        }
        return output as String
    }

    /// Insert pair identifiers in the original HTML. Inline formatting and unrecognized fields stay byte-for-byte intact.
    public static func normalize(_ html: String) throws -> (html: String, pairs: Int) {
        struct Block { let start: NSRange; let contentStart: Int; var end: Int; let element: ScreenplayElement; let side: String?; let pair: String?; var child: Bool }
        let source = html as NSString
        let tags = try NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<(?:"[^"]*"|'[^']*'|[^'">])*>"#)
        let names = try NSRegularExpression(pattern: #"^<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)"#)
        let classes = try NSRegularExpression(pattern: #"(?i)\sclass\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
        let pairs = try NSRegularExpression(pattern: #"(?i)\sdata-dual-pair\s*=\s*["']([^"']+)["']"#)
        var stack = [(name: String, index: Int)](), blocks = [Block]()
        for token in tags.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let tag = source.substring(with: token.range) as NSString
            guard let name = names.firstMatch(in: tag as String, range: NSRange(location: 0, length: tag.length)) else { continue }
            let value = tag.substring(with: name.range(at: 2)).lowercased()
            guard ["p", "div", "li", "blockquote", "h1", "h2", "h3"].contains(value) else { continue }
            if name.range(at: 1).length > 0 {
                if let i = stack.lastIndex(where: { $0.name == value }) {
                    blocks[stack[i].index].end = token.range.location; stack.removeSubrange(i...)
                }
                continue
            }
            if let parent = stack.last { blocks[parent.index].child = true }
            var words = [String]()
            if let match = classes.firstMatch(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let capture = (1...3).first { match.range(at: $0).location != NSNotFound } ?? 1
                words = tag.substring(with: match.range(at: capture)).split(whereSeparator: \.isWhitespace).map(String.init)
            }
            let element = words.compactMap { $0.hasPrefix("sc-") ? ScreenplayElement(rawValue: String($0.dropFirst(3))) : nil }.first ?? .action
            let pair = pairs.firstMatch(in: tag as String, range: NSRange(location: 0, length: tag.length)).map { tag.substring(with: $0.range(at: 1)) }
            let side = words.contains("sc-dual-left") ? "left" : words.contains("sc-dual-right") ? "right" : nil
            stack.append((value, blocks.count)); blocks.append(Block(start: token.range, contentStart: NSMaxRange(token.range), end: source.length, element: element, side: side, pair: pair, child: false))
        }
        let leaves = blocks.filter { !$0.child }
        let lines = leaves.map { block in DualDialogueLine(element: block.element, text: ScriptFilters.plain(source.substring(with: NSRange(location: block.contentStart, length: max(0, block.end - block.contentStart)))), scene: "scene") }
        var covered = Set<Int>(), insertions = [(Int, String)](), count = 0
        for i in leaves.indices where leaves[i].side == "right" && leaves[i].pair == nil && leaves[i].element == .character && !covered.contains(i) {
            let plan = try DualDialogueRules.pair(in: lines, at: i)
            let id = UUID().uuidString
            for (range, side) in [(plan.left, "left"), (plan.right, "right")] {
                for j in range {
                    guard leaves[j].side == side, leaves[j].pair == nil else { throw ProjectError.invalidProject("Legacy dual dialogue contains ambiguous annotations; the original is preserved") }
                    insertions.append((NSMaxRange(leaves[j].start) - 1, " data-dual-pair=\"\(id)\"")); covered.insert(j)
                }
            }
            count += 1
        }
        guard leaves.indices.allSatisfy({ leaves[$0].side == nil || leaves[$0].pair != nil || covered.contains($0) }) else { throw ProjectError.invalidProject("Legacy dual dialogue is incomplete; review the speech blocks before conversion") }
        let output = NSMutableString(string: html)
        for (position, value) in insertions.sorted(by: { $0.0 > $1.0 }) { output.insert(value, at: position) }
        return (output as String, count)
    }
}
extension Project {
    public func reviewingLegacyDualDialogue() throws -> (project: Project, pairs: Int) {
        var candidate = self, count = 0
        if state["frontstageWhiteboard"] != nil {
            var board = try whiteboard()
            for i in board.beats.indices {
                let result = try DualDialogueImport.normalize(board.beats[i].html)
                board.beats[i].html = result.html; count += result.pairs
            }
            try candidate.editWhiteboard { $0 = board }
        } else {
            for scene in scenes {
                let result = try DualDialogueImport.normalize(scene.html)
                if result.pairs > 0 { try candidate.updateScene(id: scene.id, html: result.html) }
                count += result.pairs
            }
        }
        if var archive = candidate.state["frontstagePullouts"]?.array {
            for i in archive.indices {
                guard var record = archive[i].object, var beat = record["beat"]?.object, let html = beat["html"]?.string else { continue }
                let result = try DualDialogueImport.normalize(html); count += result.pairs; beat["html"] = .string(result.html); record["beat"] = .object(beat); archive[i] = .object(record)
            }
            candidate.state["frontstagePullouts"] = .array(archive)
        }
        try candidate.validateSceneModel()
        return (candidate, count)
    }
}
