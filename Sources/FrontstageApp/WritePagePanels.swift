#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

struct WritePagePanels<Content: View>: View {
    @ObservedObject var workspace: Workspace
    let navigate: (Decimal, String?) -> Void
    @ViewBuilder let content: () -> Content
    @AppStorage("write-left-width") private var leftWidth = 280.0
    @AppStorage("write-right-width") private var rightWidth = 320.0
    @AppStorage("write-left-visible") private var leftVisible = true
    @AppStorage("write-right-visible") private var rightVisible = true
    @State private var drawer: String?
    @State private var dragLeft: Double?
    @State private var dragRight: Double?
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Button("Scenes / Locations") { if geometry.size.width < 900 { drawer = drawer == "left" ? nil : "left" } else { leftVisible.toggle() } }
                    Button("Notes / Breakdown / History") { if geometry.size.width < 1180 { drawer = drawer == "right" ? nil : "right" } else { rightVisible.toggle() } }
                    Spacer()
                }.padding(6)
                HStack(spacing: 0) {
                    WriteScenePanel(workspace: workspace, navigate: navigate)
                        .frame(width: leftWidth).frame(width: geometry.size.width >= 900 && leftVisible ? leftWidth : 0).clipped()
                    if geometry.size.width >= 900 && leftVisible { divider(left: true) }
                    content().frame(maxWidth: .infinity, maxHeight: .infinity)
                    if geometry.size.width >= 1180 && rightVisible { divider(left: false) }
                    WriteInspector(workspace: workspace)
                        .frame(width: rightWidth).frame(width: geometry.size.width >= 1180 && rightVisible ? rightWidth : 0).clipped()
                }
                .overlay(alignment: .leading) { if geometry.size.width < 900 && drawer == "left" { WriteScenePanel(workspace: workspace, navigate: navigate).frame(width: min(leftWidth, geometry.size.width * 0.85)).background(.background).shadow(radius: 8) } }
                .overlay(alignment: .trailing) { if geometry.size.width < 1180 && drawer == "right" { WriteInspector(workspace: workspace).frame(width: min(rightWidth, geometry.size.width * 0.85)).background(.background).shadow(radius: 8) } }
            }
        }
    }
    private func divider(left: Bool) -> some View {
        Rectangle().fill(.secondary.opacity(0.4)).frame(width: 5)
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture().onChanged { value in
                if left { if dragLeft == nil { dragLeft = leftWidth }; leftWidth = min(480, max(220, (dragLeft ?? 280) + value.translation.width)) }
                else { if dragRight == nil { dragRight = rightWidth }; rightWidth = min(480, max(260, (dragRight ?? 320) - value.translation.width)) }
            }.onEnded { _ in dragLeft = nil; dragRight = nil })
            .accessibilityLabel(left ? "Resize left panel" : "Resize right panel")
    }
}

struct WriteScenePanel: View {
    @ObservedObject var workspace: Workspace
    let navigate: (Decimal, String?) -> Void
    @AppStorage("write-left-tab") private var tab = "Scenes"
    @State private var search = ""
    @State private var expanded: Set<Decimal> = []
    @State private var expandedSummary: Set<Decimal> = []
    private var cards: [SceneCard] { ((try? workspace.project.sceneCards()) ?? []).filter { search.isEmpty || [$0.number, $0.scene.heading.text, $0.scene.title, $0.scene.summary].joined(separator: " ").localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack {
            Picker("Navigation", selection: $tab) { Text("Scenes").tag("Scenes"); Text("Locations").tag("Locations") }.pickerStyle(.segmented)
            TextField("Search scenes", text: $search)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if tab == "Locations" {
                        let groups = Dictionary(grouping: cards) { $0.scene.heading.location.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                        ForEach(groups.keys.sorted(), id: \.self) { key in
                            DisclosureGroup("\(key.isEmpty ? "Unspecified" : key) (\(groups[key]?.count ?? 0))") { ForEach(groups[key] ?? []) { card in sceneCard(card) } }
                        }
                    } else { ForEach(cards) { card in sceneCard(card) } }
                }
            }
        }.padding(10).frame(maxHeight: .infinity)
    }
    private func sceneCard(_ card: SceneCard) -> some View {
        let id = card.id
        return VStack(alignment: .leading, spacing: 8) {
            Button("\(card.number) · \(card.scene.heading.text)") { navigate(id, card.beats.first?.id) }.buttonStyle(.plain)
            Text(card.scene.title).bold()
            Text("\(card.scene.isTextLocked ? "Locked" : workspace.project.sceneReadiness(id)) · \(card.beats.count) beats · \(card.versionCount) versions").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding(get: { workspace.project.scenes.first { $0.id == id }?.summary ?? "" }, set: { value in workspace.edit("Scene Summary", key: "summary-\(id)") { try $0.updateSceneSummary(id, summary: value) } }))
                .frame(height: expandedSummary.contains(id) ? 240 : 76).disabled(card.scene.isTextLocked).accessibilityLabel("Scene summary")
            Button("Expand / collapse summary") { if !expandedSummary.insert(id).inserted { expandedSummary.remove(id) } }.font(.caption)
            Text(Array(Set(card.beats.flatMap(\.characters))).sorted().joined(separator: " · ")).font(.caption)
            DisclosureGroup("Beats (\(card.beats.count))", isExpanded: Binding(get: { expanded.contains(id) }, set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } })) {
                ForEach(card.beats) { beat in Button(beat.title) { navigate(id, beat.id) }.buttonStyle(.plain).padding(4) }
            }
        }.padding(10).background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(workspace.selectedSceneID == id ? Color.accentColor : .gray.opacity(0.4)))
            .onDrag { NSItemProvider(object: "frontstage-scene:\(id)" as NSString) }
            .dropDestination(for: String.self) { values, _ in
                guard let raw = values.first, raw.hasPrefix("frontstage-scene:"), let source = Decimal(string: String(raw.dropFirst(17))), source != id else { return false }
                workspace.edit("Reorder Scene") { try $0.reorderSceneCard(source, before: id) }; return true
            }
    }
}

struct WriteInspector: View {
    @ObservedObject var workspace: Workspace
    @AppStorage("write-right-tab") private var tab = "Notes"
    @AppStorage("write-note-scope") private var scope = "Scene"
    private var scene: FrontstageCore.Scene? { workspace.project.scenes.first { $0.id == workspace.selectedSceneID } }
    var body: some View {
        VStack(alignment: .leading) {
            Picker("Inspector", selection: $tab) { ForEach(["Notes", "Breakdown", "History"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            if tab == "Notes" {
                Picker("Note scope", selection: $scope) { Text("Scene").tag("Scene"); Text("Project").tag("Project") }.pickerStyle(.segmented)
                if scope == "Project" { WriteNotesPanel(workspace: workspace, sceneID: nil, title: "Project notes").id("project-notes") }
                else if let scene { WriteNotesPanel(workspace: workspace, sceneID: scene.id, title: scene.title).id("scene-notes-\(scene.id)") }
            } else if let scene {
                if tab == "Breakdown" { WriteBreakdownPanel(workspace: workspace, sceneID: scene.id).id(scene.id) }
                else { WriteHistoryPanel(workspace: workspace, sceneID: scene.id).id(scene.id) }
            } else { Text("Select a scene") }
        }.padding(10).frame(maxHeight: .infinity, alignment: .top)
    }
}
struct WriteNotesPanel: View {
    @ObservedObject var workspace: Workspace
    let sceneID: Decimal?
    let title: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                Button("Add Note") { workspace.edit("Add Note") { try $0.addWritingNote(sceneID: sceneID) } }
                if let scratchpad = workspace.project.legacyScratchpad(sceneID: sceneID) { DisclosureGroup("Legacy scratchpad (preserved)") { Text(scratchpad).textSelection(.enabled) } }
                ForEach(workspace.project.writingNotes(sceneID: sceneID)) { note in
                    WriteNoteCard(workspace: workspace, sceneID: sceneID, note: note)
                }
            }
        }
    }
}
struct WriteNoteCard: View {
    @ObservedObject var workspace: Workspace
    let sceneID: Decimal?
    let note: WritingNote
    var body: some View {
        VStack(alignment: .leading) {
            if note.editable {
                NoteRichEditor(html: Binding(get: { workspace.project.writingNotes(sceneID: sceneID).first { $0.id == note.id }?.content ?? note.content }, set: { value in workspace.edit("Note Text", key: "note-\(note.id)") { try $0.updateWritingNote(sceneID: sceneID, id: note.id, content: value) } }))
                    .frame(height: 150).accessibilityLabel("Note text")
                Picker("Note color", selection: Binding(get: { note.color }, set: { color in workspace.edit("Note Color") { try $0.updateWritingNote(sceneID: sceneID, id: note.id, color: color) } })) {
                    ForEach(["#fff4bc", "#d9edff", "#e1f4dc", "#f8dce7", "#ffffff"], id: \.self) { Text($0) }
                }
                HStack {
                    Button("↑") { workspace.edit("Move Note") { try $0.moveWritingNote(sceneID: sceneID, id: note.id, offset: -1) } }.accessibilityLabel("Move Note Up")
                    Button("↓") { workspace.edit("Move Note") { try $0.moveWritingNote(sceneID: sceneID, id: note.id, offset: 1) } }.accessibilityLabel("Move Note Down")
                    Button("Delete Note") { workspace.edit("Delete Note") { try $0.removeWritingNote(sceneID: sceneID, id: note.id) } }
                }
            } else { Text("Imported note · preserved read-only"); Text(note.content.localizedCaseInsensitiveContains("<audio") ? "Audio recording retained in the project" : note.content).textSelection(.enabled) }
        }.padding(8).background(Color(boardHex: note.color).opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
// A separate rich text view keeps note formatting and input focus independent of screenplay controllers.
struct NoteRichEditor: NSViewRepresentable {
    @Binding var html: String
    func makeCoordinator() -> Coordinator { Coordinator($html) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(), text = NSTextView()
        text.isRichText = true; text.allowsUndo = true; text.isAutomaticQuoteSubstitutionEnabled = false
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.delegate = context.coordinator; scroll.documentView = text; scroll.hasVerticalScroller = true
        context.coordinator.load(html, text); return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.binding = $html
        if let text = view.documentView as? NSTextView, context.coordinator.last != html, !text.hasMarkedText() { context.coordinator.load(html, text) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var binding: Binding<String>; var last = ""
        init(_ binding: Binding<String>) { self.binding = binding }
        func load(_ html: String, _ text: NSTextView) {
            last = html
            if let decoded = try? ScreenplayTextCodec.decode(safeHTML(html), width: 260, settings: ScriptLayoutSettings()) { text.textStorage?.setAttributedString(decoded) }
        }
        private func safeHTML(_ html: String) -> String {
            let allowed: Set<String> = ["p", "div", "br", "b", "strong", "i", "em", "u", "s", "ul", "ol", "li", "blockquote"]
            guard let regex = try? NSRegularExpression(pattern: "<[^>]*>") else { return "" }
            var result = html
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let tag = String(result[range]), name = tag.dropFirst().drop(while: { $0 == "/" || $0.isWhitespace }).prefix(while: { $0.isLetter }).lowercased()
                result.replaceSubrange(range, with: allowed.contains(name) ? "<" + (tag.hasPrefix("</") ? "/" : "") + name + ">" : "")
            }
            return result
        }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView, !text.hasMarkedText() else { return }
            last = ScreenplayTextCodec.encode(text.attributedString()); binding.wrappedValue = last
        }
    }
}

struct WriteBreakdownPanel: View {
    @ObservedObject var workspace: Workspace
    let sceneID: Decimal
    @State private var search = ""
    @State private var category = BreakdownCategory.props
    @State private var name = ""
    @State private var description = ""
    @State private var quantity = 1
    private var entries: [BreakdownEntry] { workspace.project.breakdownItems(for: sceneID) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Breakdown · \(workspace.project.scenes.first { $0.id == sceneID }?.title ?? "")").font(.headline)
                TextField("Search breakdown", text: $search)
                Picker("Category", selection: $category) { ForEach(BreakdownCategory.allCases, id: \.self) { Text($0.label).tag($0) } }
                TextField("Item name", text: $name); TextField("Description", text: $description)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...100_000)
                Button("Add Requirement") { workspace.edit("Add Requirement") { try $0.addBreakdownItem(sceneID: sceneID, category: category, name: name, count: quantity, notes: description) } }
                Button("Add Selected Script Text") { addSelection() }
                ForEach(BreakdownCategory.allCases, id: \.self) { category in categoryView(category.rawValue, label: category.label) }
                ForEach(Array(Set(entries.map(\.category))).filter { BreakdownCategory(rawValue: $0) == nil }.sorted(), id: \.self) { category in categoryView(category, label: "Imported · " + category) }
            }
        }
    }
    private func addSelection() {
        guard let selection = workspace.writingSelectedQuote, selection.sceneID == sceneID, !selection.text.isEmpty else { workspace.errorMessage = "Select screenplay text in this scene first."; return }
        let quote = selection.text
        workspace.edit("Tag Script Selection") { try $0.addBreakdownItem(sceneID: sceneID, category: category, name: quote, sourceQuote: quote) }
    }
    private func categoryView(_ category: String, label: String) -> some View {
        let items = entries.filter { $0.category == category }
        return DisclosureGroup("\(label) (\(items.count))") {
            ForEach(items.filter { search.isEmpty || ($0.name + " " + $0.notes).localizedCaseInsensitiveContains(search) }) { item in
                VStack(alignment: .leading) {
                    TextField("Requirement name", text: Binding(get: { item.name }, set: { value in workspace.edit("Requirement Name", key: item.id) { try $0.updateBreakdownItem(sceneID: sceneID, itemID: item.id, name: value) } }))
                    TextField("Description", text: Binding(get: { item.notes }, set: { value in workspace.edit("Requirement Description", key: item.id) { try $0.updateBreakdownItem(sceneID: sceneID, itemID: item.id, notes: value) } }))
                    Stepper("Quantity: \(item.count)", value: Binding(get: { item.count }, set: { value in workspace.edit("Requirement Quantity") { try $0.updateBreakdownItem(sceneID: sceneID, itemID: item.id, count: value) } }), in: 1...100_000)
                    Menu("Move to category") { ForEach(BreakdownCategory.allCases, id: \.self) { target in Button(target.label) { workspace.edit("Move Requirement") { try $0.moveBreakdownItem(sceneID: sceneID, itemID: item.id, category: target) } } } }
                    Button("Delete Requirement") { workspace.edit("Delete Requirement") { try $0.removeBreakdownItem(sceneID: sceneID, itemID: item.id) } }
                }.padding(6)
            }
        }
    }
}
struct WriteHistoryPanel: View {
    @ObservedObject var workspace: Workspace
    let sceneID: Decimal
    @State private var label = ""
    @State private var restore: SceneRevision?
    private func readable(_ html: String) -> String { (try? ScreenplayTextCodec.decode(html).string) ?? html }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Scene History").font(.headline)
                TextField("Snapshot label", text: $label)
                Button("Capture Snapshot") { guard !workspace.whiteboard.beats.filter({ $0.sceneID == sceneID }).contains(where: { workspace.scriptController($0.id).textView?.hasMarkedText() == true }) else { workspace.errorMessage = "Finish the current text composition before taking a snapshot."; return }; workspace.edit("Capture Snapshot") { try $0.saveRevision(sceneID: sceneID, label: label) } }
                ForEach(workspace.project.revisions(for: sceneID)) { revision in
                    DisclosureGroup(revision.label) {
                        Text(revision.date, style: .date); Text(revision.date, style: .time)
                        Text(revision.summary).font(.caption)
                        ForEach(RevisionDiffLine.compare(before: readable(revision.html), after: readable(workspace.project.scenes.first { $0.id == sceneID }?.html ?? ""))) { line in
                            Text((line.kind == .added ? "+ " : line.kind == .removed ? "− " : "  ") + line.text).font(.caption.monospaced()).foregroundStyle(line.kind == .removed ? .red : line.kind == .added ? .green : .primary).textSelection(.enabled)
                        }
                        Button("Restore This Snapshot") { restore = revision }
                    }
                }
            }
        }.confirmationDialog("Restore this scene? A backup will be created. Notes and breakdown stay unchanged.", isPresented: Binding(get: { restore != nil }, set: { if !$0 { restore = nil } })) {
            Button("Restore") { if let revision = restore { workspace.edit("Restore Snapshot") { try $0.restoreRevision(sceneID: sceneID, revisionID: revision.id) } }; restore = nil }
            Button("Cancel", role: .cancel) { restore = nil }
        }
    }
}
#endif
