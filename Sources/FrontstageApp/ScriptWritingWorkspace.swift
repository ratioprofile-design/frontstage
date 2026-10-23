#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

struct ScriptWritingWorkspace: View {
    @ObservedObject var workspace: Workspace
    private var segments: [ScriptSegment] { (try? workspace.project.orderedScript()) ?? [] }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Write").font(.title2.weight(.semibold))
                Text("Continuous screenplay · linked to your whiteboard").foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, WorkspaceDesign.padding).padding(.vertical, 16)
            if let scene = workspace.selectedScene {
                VStack(spacing: 8) {
                    HStack {
                        TextField("Scene title", text: Binding(get: { workspace.selectedScene?.title ?? "" }, set: { workspace.updateScene(id: scene.id, title: $0) }))
                        TextField("Synopsis", text: Binding(get: { workspace.selectedScene?.summary ?? "" }, set: { workspace.updateScene(id: scene.id, summary: $0) }))
                    }
                    SceneHeadingFields(scene: scene, workspace: workspace)
                }.textFieldStyle(.roundedBorder).padding(.horizontal, WorkspaceDesign.padding).padding(.bottom, 12)
            }
            ScrollView([.vertical, .horizontal]) {
                if segments.isEmpty {
                    ContentUnavailableView("Your next story starts here", systemImage: "doc.richtext", description: Text("Add a scene or a beat to begin."))
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            VStack(alignment: .leading, spacing: 12) {
                                Text("\(segment.number)  \(segment.scene.heading.text)\(segment.isContinuation ? " (CONTINUED)" : "")")
                                    .font(.custom(workspace.project.scriptLayout.fontName, size: workspace.project.scriptLayout.fontSize).weight(.bold))
                                    .foregroundStyle(.black)
                                if segment.beatIDs.isEmpty {
                                    ContinuousSnippet(workspace: workspace, sceneID: segment.scene.id, beatID: nil,
                                        controller: workspace.scriptController("scene-\(segment.scene.id)"))
                                } else {
                                    ForEach(segment.beatIDs, id: \.self) { id in
                                        ContinuousSnippet(workspace: workspace, sceneID: segment.scene.id, beatID: id,
                                            controller: workspace.scriptController(id))
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 24)
                    }
                    .frame(width: workspace.paper.contentWidth, alignment: .leading)
                    .padding(.leading, workspace.paper.leftMargin).padding(.trailing, workspace.paper.rightMargin)
                    .padding(.vertical, workspace.paper.topMargin)
                    .frame(minHeight: workspace.paper.height, alignment: .topLeading)
                    .background(Color.white).environment(\.colorScheme, .light)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3).padding(24)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.47))
        }
    }
}

struct ContinuousSnippet: View {
    @ObservedObject var workspace: Workspace
    let sceneID: Decimal
    let beatID: String?
    @ObservedObject var controller: ScreenplayEditorController
    var compact = false
    var readerWidth: CGFloat = 520
    var readerZoom: Double = 1
    private var displayTypography: ScriptLayoutSettings { var value = workspace.project.scriptLayout; if compact { value.fontSize = max(14, value.fontSize) * readerZoom; value.lineHeight = max(value.lineHeight * readerZoom, value.fontSize * 1.35) }; return value }
    private var beat: BoardBeat? { workspace.whiteboard.beats.first { $0.id == beatID } }
    private var scene: FrontstageCore.Scene? { workspace.project.scenes.first { $0.id == sceneID } }
    private var html: Binding<String> {
        Binding(get: { beatID == nil ? scene?.html ?? "" : beat?.html ?? "" }, set: { value in
            if let beatID { workspace.edit("Snippet Text", key: "script-\(beatID)") { try $0.updateBoardBeat(beatID) { $0.html = value } } }
            else { workspace.updateScene(id: sceneID, html: value) }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !compact, let beatID, let beat {
                Button(beat.title) { workspace.selectBoardBeat(beatID); workspace.popup.open(beatID, workspace: workspace) }
                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading).buttonStyle(.plain)
                    .padding(4).background(Color(white: 0.93))
            }
            if !compact { HStack {
                Picker("Element", selection: Binding(get: { controller.activeElement }, set: { controller.format($0) })) {
                    ForEach(ScreenplayElement.editable, id: \.self) { Text($0.label).tag($0) }
                }.frame(width: compact ? 120 : 180)
                InlineFormatButtons(controller: controller)
                Spacer()
            }.font(.caption).disabled(scene?.isTextLocked == true)
            ScreenplaySuggestions(workspace: workspace, controller: controller).disabled(scene?.isTextLocked == true)
            }
            ScreenplayEditor(html: html, controller: controller, width: compact ? readerWidth : workspace.paper.contentWidth,
                typography: displayTypography, onError: { workspace.errorMessage = $0 }, editable: scene?.isTextLocked != true, continuous: true, suggestions: workspace.screenplayCompletions)
                .frame(height: controller.layoutHeight)
        }
    }
}
struct BeatReferenceChips: View {
    let characters: [String]
    let tags: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !characters.isEmpty { LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading) {
                ForEach(characters, id: \.self) { name in
                    HStack(spacing: 4) {
                        Circle().fill(Color(boardHex: ["#11106b","#5de5bb","#a30e3f","#d6ae1c","#467e96"][name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 5])).frame(width: 18, height: 18)
                        Text(name).font(.system(size: 12))
                    }
                }
            } }
            if !tags.isEmpty { LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading) {
                ForEach(tags, id: \.self) { tag in Text(tag).font(.system(size: 11)).foregroundStyle(.white).padding(4).background(Color(boardHex: "#ca53df")) }
            } }
        }
    }
}

struct ScriptReaderSettings {
    var display = "Expand All"
    var characters = true
    var tags = true
    var synopsis = false
    var boundaries = false
    var margins = "Compact Margins"
    var zoom = 1.0
    var filter = ""
    var followSelection = false
    var revision = 0
    var inset: CGFloat { margins == "Full Margins" ? 48 : margins == "Compact Margins" ? 16 : margins == "Squeezed" ? 8 : 3 }
}

struct SideScriptBeat: View {
    @ObservedObject var workspace: Workspace
    let beat: BoardBeat
    let width: CGFloat
    @State private var expanded = true
    private var settings: ScriptReaderSettings { workspace.reader }
    private var plain: Bool { ["Content Only", "Final Script"].contains(settings.display) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !plain {
                Button { expanded.toggle(); workspace.selectBoardBeat(beat.id) } label: {
                    Text((expanded ? "▼ " : "▶ ") + beat.title).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading).padding(9)
                }.buttonStyle(.plain).background(Color(boardHex: beat.color).opacity(0.2))
                if (settings.characters && !beat.characters.isEmpty) || (settings.tags && !beat.tags.isEmpty) {
                    BeatReferenceChips(characters: settings.characters ? beat.characters : [], tags: settings.tags ? beat.tags : []).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.94))
                }
                if settings.synopsis || settings.display == "Index Cards" { Text(beat.synopsis).padding(8) }
            }
            if plain || (expanded && settings.display != "Index Cards") {
                if beat.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write this beat’s screenplay here…").font(.custom("Courier", size: 14)).foregroundStyle(.secondary).padding(.horizontal, settings.inset).padding(.top, 10)
                }
                ContinuousSnippet(workspace: workspace, sceneID: beat.sceneID, beatID: beat.id, controller: workspace.scriptController("reader-" + beat.id), compact: true, readerWidth: max(180, width - settings.inset * 2), readerZoom: settings.zoom)
                    .padding(.horizontal, settings.inset).padding(.vertical, 12)
            }
        }.background(Color.white).foregroundStyle(.black).environment(\.colorScheme, .light)
            .overlay(Rectangle().stroke(workspace.selectedBoardBeatID == beat.id ? Color.accentColor : .clear, lineWidth: 2))
            .onTapGesture(count: 2) { workspace.popup.open(beat.id, workspace: workspace) }
            .onAppear { expanded = settings.display != "Collapse All" }
            .onChange(of: settings.revision) { _ in expanded = settings.display != "Collapse All" }
    }
}

struct ScriptSidePaper: View {
    @ObservedObject var workspace: Workspace
    private func display(_ mode: String) { workspace.reader.display = mode; workspace.reader.revision += 1 }
    private var segments: [ScriptSegment] { (try? workspace.project.orderedScript()) ?? [] }
    private func matches(_ beat: BoardBeat) -> Bool {
        let query = workspace.reader.filter
        return query.isEmpty || ([beat.title, beat.synopsis, beat.html] + beat.characters + beat.tags).joined(separator: " ").localizedCaseInsensitiveContains(query)
    }
    private var tools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
            Menu {
                Section("Beat Display") { ForEach(["Expand All", "Index Cards", "Collapse All", "Content Only", "Final Script"], id: \.self) { mode in Button(mode) { display(mode) } } }
                Section("Beat Details") {
                    Toggle("Show Characters", isOn: $workspace.reader.characters)
                    Toggle("Show Tags", isOn: $workspace.reader.tags)
                    Toggle("Show Synopsis Field", isOn: $workspace.reader.synopsis)
                    Toggle("Show Block/Group Beginnings", isOn: $workspace.reader.boundaries)
                }
                Section("Display Margins") { Picker("Margins", selection: $workspace.reader.margins) { ForEach(["Full Margins", "Compact Margins", "Squeezed", "Super Squeezed"], id: \.self) { Text($0) } } }
            } label: { Label("Display", systemImage: "rectangle.split.3x1") }
            Menu {
                Button("Zoom In") { workspace.reader.zoom = min(2, workspace.reader.zoom + 0.1) }
                Button("Zoom Out") { workspace.reader.zoom = max(0.7, workspace.reader.zoom - 0.1) }
                Button("100%") { workspace.reader.zoom = 1 }
            } label: { Label("Styling", systemImage: "textformat") }
            Menu {
                Button("All Beats") { workspace.reader.filter = "" }
                ForEach(workspace.project.characters, id: \.id) { character in Button(character.name) { workspace.reader.filter = character.name } }
            } label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }
            Menu {
                Button("Story Review") { workspace.reader = ScriptReaderSettings() }
                Button("Reading") { display("Final Script"); workspace.reader.zoom = 1.1 }
                Button("Index Cards") { display("Index Cards"); workspace.reader.synopsis = true }
            } label: { Label("Presets", systemImage: "eye") }
            Menu {
                Toggle("Follow Selected Beat", isOn: $workspace.reader.followSelection)
                Button("Full Screen") { NSApp.keyWindow?.toggleFullScreen(nil) }
            } label: { Label("Options", systemImage: "gearshape") }
        }.labelStyle(.titleAndIcon).font(.system(size: 11)).fixedSize(horizontal: true, vertical: false).padding(8)
        }.frame(height: 44).background(Color(white: 0.2)).accessibilityIdentifier("script-reader-tools")
    }
    var body: some View {
        VStack(spacing: 0) {
            tools.frame(maxWidth: .infinity, alignment: .leading)
            TextField("Filter script, characters or tags", text: $workspace.reader.filter).textFieldStyle(.roundedBorder).padding(6)
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(workspace.project.name).font(.system(size: 17)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(14).background(Color(boardHex: "#078827"))
                            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                                let beats = segment.beatIDs.compactMap { id in workspace.whiteboard.beats.first { $0.id == id } }.filter(matches)
                                if !beats.isEmpty || (segment.beatIDs.isEmpty && workspace.reader.filter.isEmpty) {
                                    HStack { Text(segment.scene.heading.text + (segment.isContinuation ? " (CONTINUED)" : "")); Spacer(); Text(segment.number) }
                                        .font(.custom("Courier", size: 14 * workspace.reader.zoom).bold()).foregroundStyle(.black).padding(10).background(Color.white)
                                    ForEach(beats, id: \.id) { beat in
                                        if workspace.reader.boundaries, let owner = workspace.whiteboard.blocks.first(where: { $0.id == beat.blockID }), owner.standalone != true,
                                           workspace.whiteboard.orderedBeats.first(where: { $0.blockID == owner.id })?.id == beat.id {
                                            Text(owner.name).font(.caption).padding(5).background(Color.black)
                                        }
                                        SideScriptBeat(workspace: workspace, beat: beat, width: max(200, geometry.size.width - 16)).id(beat.id)
                                    }
                                    if segment.beatIDs.isEmpty { ContinuousSnippet(workspace: workspace, sceneID: segment.scene.id, beatID: nil, controller: workspace.scriptController("reader-scene-\(segment.scene.id)"), compact: true, readerWidth: max(180, geometry.size.width - 36), readerZoom: workspace.reader.zoom).padding(10).background(Color.white) }
                                }
                            }
                        }.padding(8).frame(width: geometry.size.width, alignment: .topLeading).frame(minHeight: geometry.size.height, alignment: .topLeading)
                    }.onChange(of: workspace.selectedBoardBeatID) { id in if workspace.reader.followSelection, let id { proxy.scrollTo(id, anchor: .top) } }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(white: 0.42))
    }
}

struct InlineFormatButtons: View {
    @ObservedObject var controller: ScreenplayEditorController
    var body: some View {
        HStack(spacing: 6) {
            Button("B") { controller.toggleInlineStyle("bold") }.fontWeight(.bold).accessibilityLabel("Bold")
            Button("I") { controller.toggleInlineStyle("italic") }.italic().accessibilityLabel("Italic")
            Button("U") { controller.toggleInlineStyle("underline") }.accessibilityLabel("Underline")
        }
    }
}
#endif
