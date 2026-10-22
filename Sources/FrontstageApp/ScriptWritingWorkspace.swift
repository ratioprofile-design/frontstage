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
                }.frame(width: 180)
                InlineFormatButtons(controller: controller)
                Spacer()
            }.font(.caption).disabled(scene?.isTextLocked == true) }
            ScreenplayEditor(html: html, controller: controller, width: compact ? 252 : workspace.paper.contentWidth,
                typography: workspace.project.scriptLayout, onError: { workspace.errorMessage = $0 }, editable: scene?.isTextLocked != true, continuous: true)
                .frame(height: controller.layoutHeight)
        }
    }
}
struct ScriptSidePaper: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        VStack(spacing: 0) {
            Text("SCRIPT").font(.caption).padding(8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(((try? workspace.project.orderedScript()) ?? []).enumerated()), id: \.offset) { _, segment in
                        Text("\(segment.number)  \(segment.scene.heading.text)\(segment.isContinuation ? " (CONTINUED)" : "")")
                            .font(.custom("Courier", size: 12).bold()).foregroundStyle(.black).padding(.top, 14)
                        if segment.beatIDs.isEmpty {
                            ContinuousSnippet(workspace: workspace, sceneID: segment.scene.id, beatID: nil,
                                controller: workspace.scriptController("scene-\(segment.scene.id)"), compact: true)
                        }
                        ForEach(segment.beatIDs, id: \.self) { id in
                            ContinuousSnippet(workspace: workspace, sceneID: segment.scene.id, beatID: id,
                                controller: workspace.scriptController(id), compact: true)
                                .onTapGesture { workspace.selectBoardBeat(id) }
                        }
                    }
                    Spacer(minLength: 72)
                }.frame(width: 252, alignment: .leading).padding(24).frame(minHeight: 792, alignment: .topLeading)
                    .background(Color.white).environment(\.colorScheme, .light).shadow(radius: 2).padding(10)
            }
        }.background(Color(white: 0.47))
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
