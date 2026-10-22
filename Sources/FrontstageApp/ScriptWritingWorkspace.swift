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
            ScreenplayEditor(html: html, controller: controller, width: compact ? 520 : workspace.paper.contentWidth,
                typography: workspace.project.scriptLayout, onError: { workspace.errorMessage = $0 }, editable: scene?.isTextLocked != true, continuous: true)
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

struct SideScriptBeat: View {
    @ObservedObject var workspace: Workspace
    let beat: BoardBeat
    @State private var expanded = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle(); workspace.selectBoardBeat(beat.id) } label: {
                Text((expanded ? "▼ " : "▶ ") + beat.title).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading).padding(9)
            }.buttonStyle(.plain).background(Color(boardHex: beat.color).opacity(0.2))
            if !beat.characters.isEmpty || !beat.tags.isEmpty { BeatReferenceChips(characters: beat.characters, tags: beat.tags).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.94)) }
            if expanded { ContinuousSnippet(workspace: workspace, sceneID: beat.sceneID, beatID: beat.id, controller: workspace.scriptController(beat.id), compact: true).padding(10) }
        }.background(Color.white).foregroundStyle(.black).environment(\.colorScheme, .light)
            .overlay(Rectangle().stroke(workspace.selectedBoardBeatID == beat.id ? Color.accentColor : .clear, lineWidth: 2))
            .onTapGesture(count: 2) { workspace.popup.open(beat.id, workspace: workspace) }
            .onChange(of: workspace.selectedBoardBeatID) { id in if id == beat.id { expanded = true } }
    }
}

struct ScriptSidePaper: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(workspace.project.name).font(.system(size: 17)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(14).background(Color(boardHex: "#078827"))
                    ForEach(Array(((try? workspace.project.orderedScript()) ?? []).enumerated()), id: \.offset) { _, segment in
                        HStack {
                            Text(segment.scene.heading.text + (segment.isContinuation ? " (CONTINUED)" : "")); Spacer(); Text(segment.number)
                        }.font(.custom("Courier", size: 14).bold()).foregroundStyle(.black).padding(10).background(Color.white)
                        ForEach(segment.beatIDs, id: \.self) { id in
                            if let beat = workspace.whiteboard.beats.first(where: { $0.id == id }) { SideScriptBeat(workspace: workspace, beat: beat).id(id) }
                        }
                        if segment.beatIDs.isEmpty { ContinuousSnippet(workspace: workspace, sceneID: segment.scene.id, beatID: nil, controller: workspace.scriptController("scene-\(segment.scene.id)"), compact: true).padding(10).background(Color.white) }
                    }
                }.frame(width: 540, alignment: .leading).padding(8)
            }.background(Color(white: 0.42))
            .onChange(of: workspace.selectedBoardBeatID) { id in if let id { proxy.scrollTo(id, anchor: .center) } }
        }
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
