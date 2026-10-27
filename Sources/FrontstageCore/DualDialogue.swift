import Foundation

/// Lossless document operations for two simultaneous speeches. The additive HTML
/// representation is shared with the browser; it does not change project identity.
public enum DualDialogue {
    public struct Pair: Equatable, Sendable {
        public let left: String
        public let right: String
        public var html: String {
            "<div class=\"sc-dual\"><div class=\"sc-dual-column sc-dual-left\">\(left)</div><div class=\"sc-dual-column sc-dual-right\">\(right)</div></div>"
        }
    }

    /// Cue indices count top-level paragraphs, not text nodes or inline emphasis.
    /// Both speeches must be adjacent and contained in the same beat.
    public static func pair(in html: String, firstCue: Int, secondCue: Int) throws -> String {
        let nodes = try roots(html)
        guard firstCue >= 0, secondCue > firstCue, secondCue < nodes.count else { throw invalidSelection }
        var end = secondCue + 1
        while end < nodes.count, [.dialogue, .parenthetical].contains(nodes[end].element) { end += 1 }
        let source = html as NSString
        let leftRange = NSRange(location: nodes[firstCue].range.location,
                                length: nodes[secondCue].range.location - nodes[firstCue].range.location)
        let rightRange = NSRange(location: nodes[secondCue].range.location,
                                 length: NSMaxRange(nodes[end - 1].range) - nodes[secondCue].range.location)
        let left = source.substring(with: leftRange), right = source.substring(with: rightRange)
        try validateColumn(left); try validateColumn(right)
        let pair = Pair(left: left, right: right)
        return source.replacingCharacters(in: NSRange(location: leftRange.location, length: NSMaxRange(rightRange) - leftRange.location), with: pair.html)
    }

    public static func remove(in html: String, at index: Int) throws -> String {
        let nodes = try roots(html)
        guard nodes.indices.contains(index), try readPair(nodes[index], in: html) != nil else { throw invalidSelection }
        let body = (html as NSString).substring(with: nodes[index].content)
        let columns = try roots(body)
        let unwrapped = NSMutableString(string: body)
        // Keep comments and whitespace between columns, including imported content.
        for column in columns.reversed() {
            unwrapped.replaceCharacters(in: column.range, with: (body as NSString).substring(with: column.content))
        }
        return (html as NSString).replacingCharacters(in: nodes[index].range, with: unwrapped as String)
    }

    /// Returns each pair for renderers/exporters without rewriting surrounding HTML.
    /// Malformed marked pairs are rejected, never silently flattened.
    public static func pairs(in html: String) throws -> [Pair] {
        try roots(html).compactMap { try readPair($0, in: html) }
    }

    private static let invalidSelection = ProjectError.invalidProject("Select two adjacent character/dialogue passages in one beat. Each speech must contain dialogue.")
    private static func validateColumn(_ html: String) throws {
        let nodes = try roots(html)
        guard nodes.first?.element == .character,
              nodes.dropFirst().allSatisfy({ [.dialogue, .parenthetical].contains($0.element) }),
              hasText(nodes[0], in: html),
              nodes.dropFirst().contains(where: { $0.element == .dialogue && hasText($0, in: html) }) else { throw invalidSelection }
    }
    private static func hasText(_ node: Node, in html: String) -> Bool {
        let content = (html as NSString).substring(with: node.content)
            .replacingOccurrences(of: #"<!--[\s\S]*?-->|<(?:"[^"]*"|'[^']*'|[^'">])*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private static func readPair(_ node: Node, in html: String) throws -> Pair? {
        guard node.classes.contains("sc-dual") else { return nil }
        let body = (html as NSString).substring(with: node.content)
        let columns = try roots(body)
        guard node.tag == "div", columns.count == 2,
              columns[0].classes.isSuperset(of: ["sc-dual-column", "sc-dual-left"]),
              columns[1].classes.isSuperset(of: ["sc-dual-column", "sc-dual-right"]),
              !columns[0].classes.contains("sc-dual-right"), !columns[1].classes.contains("sc-dual-left"),
              columns.allSatisfy({ $0.tag == "div" }) else { throw invalidSelection }
        let source = body as NSString
        let left = source.substring(with: columns[0].content), right = source.substring(with: columns[1].content)
        try validateColumn(left); try validateColumn(right)
        return Pair(left: left, right: right)
    }

    private struct Node {
        var range: NSRange
        var content: NSRange
        var tag: String
        var classes: Set<String>
        var element: ScreenplayElement? {
            guard ["p", "div"].contains(tag), classes.isDisjoint(with: ["sc-dual", "sc-dual-column"]) else { return nil }
            let matches = ScreenplayElement.allCases.filter { classes.contains("sc-" + $0.rawValue) }
            return matches.count == 1 ? matches[0] : nil
        }
    }

    /// A bounded, strict scanner for this operation, not an HTML sanitizer. Existing
    /// documents remain readable even when their legacy markup cannot be paired.
    private static func roots(_ html: String) throws -> [Node] {
        let tags = try NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<(?:"[^"]*"|'[^']*'|[^'">])*>"#)
        let names = try NSRegularExpression(pattern: #"^<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)"#)
        let classes = try NSRegularExpression(pattern: #"\sclass\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#, options: .caseInsensitive)
        let source = html as NSString
        let voids: Set<String> = ["br", "hr", "img", "input", "meta", "link", "wbr", "source", "area", "base", "embed", "param", "col", "track"]
        var stack: [String] = [], output: [Node] = [], current: Node?, cursor = 0
        for match in tags.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            if stack.isEmpty, !source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw invalidSelection }
            cursor = NSMaxRange(match.range)
            let raw = source.substring(with: match.range), tag = raw as NSString
            if raw.hasPrefix("<!--") { continue }
            guard let name = names.firstMatch(in: raw, range: NSRange(location: 0, length: tag.length)) else { throw invalidSelection }
            let key = tag.substring(with: name.range(at: 2)).lowercased()
            if name.range(at: 1).length > 0 {
                guard stack.last == key else { throw invalidSelection }
                stack.removeLast()
                if stack.isEmpty, var node = current {
                    node.content.length = match.range.location - node.content.location
                    node.range.length = NSMaxRange(match.range) - node.range.location
                    output.append(node); current = nil
                }
            } else {
                if stack.isEmpty {
                    guard ["p", "div"].contains(key) else { throw invalidSelection }
                    var values = Set<String>()
                    if let value = classes.firstMatch(in: raw, range: NSRange(location: 0, length: tag.length)) {
                        for index in 1...3 where value.range(at: index).location != NSNotFound {
                            values.formUnion(tag.substring(with: value.range(at: index)).split(whereSeparator: { $0.isWhitespace }).map(String.init))
                        }
                    }
                    current = Node(range: match.range, content: NSRange(location: NSMaxRange(match.range), length: 0), tag: key, classes: values)
                } else if ["p", "div", "table", "ul", "ol", "li", "blockquote"].contains(key), current?.classes.isDisjoint(with: ["sc-dual", "sc-dual-column"]) != false {
                    // Pairing a paragraph containing nested block content is ambiguous.
                    throw invalidSelection
                }
                if !voids.contains(key) {
                    guard !raw.hasSuffix("/>"), stack.count < 64 else { throw invalidSelection }
                    stack.append(key)
                }
            }
        }
        guard stack.isEmpty, source.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalidSelection }
        return output
    }
}

extension Project {
    public mutating func pairDialogue(in beatID: String, firstCue: Int, secondCue: Int) throws {
        guard let beat = try whiteboard().beats.first(where: { $0.id == beatID }) else { throw ProjectError.sceneNotFound }
        let html = try DualDialogue.pair(in: beat.html, firstCue: firstCue, secondCue: secondCue)
        try applyScriptDocument(beatHTML: [beatID: html], headings: [])
    }
    public mutating func removeDualDialogue(in beatID: String, at index: Int) throws {
        guard let beat = try whiteboard().beats.first(where: { $0.id == beatID }) else { throw ProjectError.sceneNotFound }
        let html = try DualDialogue.remove(in: beat.html, at: index)
        try applyScriptDocument(beatHTML: [beatID: html], headings: [])
    }
}
