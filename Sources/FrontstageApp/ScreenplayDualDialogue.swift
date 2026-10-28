#if os(macOS)
import AppKit
import FrontstageCore

@MainActor
enum ScreenplayDualDialogue {
    static func toggle(_ controller: ScreenplayEditorController) {
        guard let text = controller.textView, text.isEditable, !text.hasMarkedText(), let storage = text.textStorage, storage.length > 0 else { return }
        let selected = text.selectedRange(), caret = min(selected.location, storage.length - 1)
        var ranges = [NSRange](), lines = [DualDialogueLine](), offset = 0
        while offset < storage.length {
            let range = (storage.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
            let scene = storage.attribute(NSAttributedString.Key("FrontstageBeatOwner"), at: offset, effectiveRange: nil) as? String ?? "popup"
            ranges.append(range); lines.append(.init(element: ScreenplayTextCodec.element(in: storage, at: offset), text: (storage.string as NSString).substring(with: range), scene: scene)); offset = NSMaxRange(range)
        }
        do {
            let affected: NSRange
            let replacement = NSMutableAttributedString(attributedString: storage)
            if let pair = storage.attribute(.screenplayDualPair, at: caret, effectiveRange: nil) as? String {
                let matching = ranges.filter { storage.attribute(.screenplayDualPair, at: $0.location, effectiveRange: nil) as? String == pair }
                guard let first = matching.first, let last = matching.last else { return }
                affected = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
                replacement.removeAttribute(.screenplayDualPair, range: affected); replacement.removeAttribute(.screenplayDualDialogue, range: affected)
            } else {
                let index = ranges.firstIndex { NSLocationInRange(caret, $0) } ?? 0
                let plan = try DualDialogueRules.pair(in: lines, at: index)
                let first = ranges[plan.left.lowerBound], last = ranges[plan.right.upperBound - 1]
                affected = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
                for i in plan.left.lowerBound..<plan.right.upperBound {
                    guard storage.attribute(.screenplayDualDialogue, at: ranges[i].location, effectiveRange: nil) == nil else { throw ProjectError.invalidProject("Unpair the existing dialogue before pairing another block") }
                }
                let pair = UUID().uuidString
                for (indices, side) in [(plan.left, "left"), (plan.right, "right")] {
                    for i in indices { replacement.addAttributes([.screenplayDualPair: pair, .screenplayDualDialogue: side], range: ranges[i]) }
                }
            }
            guard text.shouldChangeText(in: affected, replacementString: nil) else { return }
            controller.command {
                storage.replaceCharacters(in: affected, with: replacement.attributedSubstring(from: affected))
                layout(storage, width: controller.contentWidth, settings: controller.typography)
                text.setSelectedRange(selected); text.didChangeText()
            }
        } catch { let alert = NSAlert(); alert.messageText = "Cannot pair dialogue"; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
    /// One TextKit table row per speech pair gives both cells a common top and max-height row.
    /// Table styles are derived presentation; the codec writes only pair identity and side.
    static func layout(_ text: NSMutableAttributedString, width: CGFloat, settings: ScriptLayoutSettings) {
        guard text.length > 0 else { return }
        var tables = [String: NSTextTable](), cells = [String: NSTextTableBlock](), offset = 0
        while offset < text.length {
            let range = (text.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
            let element = ScreenplayTextCodec.element(in: text, at: offset)
            let pair = text.attribute(.screenplayDualPair, at: offset, effectiveRange: nil) as? String
            let side = text.attribute(.screenplayDualDialogue, at: offset, effectiveRange: nil) as? String
            if let pair, let side, ["left", "right"].contains(side) {
                let table: NSTextTable
                if let existing = tables[pair] { table = existing } else {
                    table = NSTextTable(); table.numberOfColumns = 2; table.layoutAlgorithm = .fixedLayoutAlgorithm; table.collapsesBorders = true
                    table.setValue(width, type: .absoluteValueType, for: .width); tables[pair] = table
                }
                let cellKey = pair + ":" + side
                let block: NSTextTableBlock
                if let existing = cells[cellKey] { block = existing } else {
                    block = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: side == "left" ? 0 : 1, columnSpan: 1)
                    block.setValue(width / 2, type: .absoluteValueType, for: .width)
                    block.setWidth(6, type: .absoluteValueType, for: .padding)
                    cells[cellKey] = block
                }
                let attrs = ScreenplayTypography.attributes(element, width: max(1, width / 2 - 12), settings: settings)
                let paragraph = (attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
                paragraph.textBlocks = [block]
                text.addAttribute(.paragraphStyle, value: paragraph, range: range)
            } else if let current = text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle, !current.textBlocks.isEmpty {
                text.addAttribute(.paragraphStyle, value: ScreenplayTypography.attributes(element, width: width, settings: settings)[.paragraphStyle]!, range: range)
            }
            offset = NSMaxRange(range)
        }
    }
}
#endif
