#if os(macOS)
import SwiftUI
import FrontstageCore

struct StoryBoardView: View {
    @ObservedObject var workspace: Workspace
    @State private var boardID = 0
    @State private var from: Decimal?
    @State private var to: Decimal?
    @State private var linkLabel = ""
    @State private var zoom = 1.0

    private var graph: StoryGraph { workspace.project.storyGraph }
    private var nodes: [StoryNode] { graph.nodes.filter { $0.boardID == boardID } }
    private var links: [StoryLink] {
        let ids = Set(nodes.map(\.id))
        return graph.links.filter { ids.contains($0.from) && ids.contains($0.to) }
    }
    private var origin: CGPoint {
        CGPoint(x: min(0, nodes.map(\.x).min() ?? 0) - 70, y: min(0, nodes.map(\.y).min() ?? 0) - 70)
    }
    private var canvasSize: CGSize {
        CGSize(width: max(1400, (nodes.map(\.x).max() ?? 0) - origin.x + 350),
               height: max(900, (nodes.map(\.y).max() ?? 0) - origin.y + 300))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Board", selection: $boardID) {
                    ForEach(graph.boardIDs.isEmpty ? [0] : graph.boardIDs, id: \.self) { Text("Board \($0 + 1)").tag($0) }
                }.frame(width: 160)
                Button("Arrange Cards") { workspace.edit("Arrange Board") { try $0.arrangeStoryBoard(boardID) } }
                Spacer()
                Text("Zoom").font(.caption)
                Slider(value: $zoom, in: 0.5...1.5).frame(width: 120)
            }
            HStack {
                scenePicker("From", selection: $from)
                scenePicker("To", selection: $to)
                TextField("Connection label", text: $linkLabel).textFieldStyle(.roundedBorder)
                Button("Connect") {
                    guard let from, let to else { return }
                    workspace.edit("Connect Scenes") { try $0.connectScenes(from: from, to: to, label: linkLabel) }
                }.disabled(from == nil || to == nil || from == to)
            }
            if graph.hasCycle { Text("An imported connection cycle exists. Remove a connection below to resolve it.").foregroundStyle(.orange) }
            if graph.danglingConnections > 0 { Text("\(graph.danglingConnections) imported links refer to missing scenes and are not drawn.").font(.caption).foregroundStyle(.secondary) }
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for link in links {
                            guard let a = nodes.first(where: { $0.id == link.from }),
                                  let b = nodes.first(where: { $0.id == link.to }) else { continue }
                            let start = CGPoint(x: a.x - origin.x + 220, y: a.y - origin.y + 60)
                            let end = CGPoint(x: b.x - origin.x, y: b.y - origin.y + 60)
                            var path = Path()
                            path.move(to: start)
                            path.addCurve(to: end, control1: CGPoint(x: start.x + 70, y: start.y), control2: CGPoint(x: end.x - 70, y: end.y))
                            context.stroke(path, with: .color(.accentColor.opacity(0.75)), lineWidth: 2)
                            var arrow = Path()
                            arrow.move(to: CGPoint(x: end.x - 8, y: end.y - 5)); arrow.addLine(to: end)
                            arrow.addLine(to: CGPoint(x: end.x - 8, y: end.y + 5))
                            context.stroke(arrow, with: .color(.accentColor), lineWidth: 2)
                        }
                    }.frame(width: canvasSize.width, height: canvasSize.height)
                    ForEach(nodes) { node in
                        StoryCard(node: node, origin: origin, workspace: workspace)
                    }
                }.frame(width: canvasSize.width, height: canvasSize.height)
                    .coordinateSpace(name: "storyCanvas")
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(width: canvasSize.width * zoom, height: canvasSize.height * zoom, alignment: .topLeading)
            }.background(Color(nsColor: .underPageBackgroundColor))
            if !links.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(links) { link in
                            HStack {
                                Text("\(nodes.first { $0.id == link.from }?.title ?? "Scene") → \(nodes.first { $0.id == link.to }?.title ?? "Scene") \(link.label)")
                                Button { workspace.edit("Disconnect Scenes") { $0.disconnectScenes(from: link.from, to: link.to) } }
                                    label: { Image(systemName: "xmark.circle") }
                            }.font(.caption).padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }.frame(height: 40)
            }
            Text("Drag cards to move them. Double-click to write. Use a card's context menu to omit or reorder a scene.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).onAppear { if !graph.boardIDs.contains(boardID) { boardID = graph.boardIDs.first ?? 0 } }
    }

    private func scenePicker(_ title: String, selection: Binding<Decimal?>) -> some View {
        Picker(title, selection: selection) {
            Text("Choose scene").tag(Optional<Decimal>.none)
            ForEach(nodes) { Text($0.title).tag(Optional($0.id)) }
        }.frame(maxWidth: 190)
    }
}

private struct StoryCard: View {
    let node: StoryNode
    let origin: CGPoint
    @ObservedObject var workspace: Workspace
    @GestureState private var translation = CGSize.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(node.title).font(.headline).lineLimit(2)
            Text(node.summary.isEmpty ? "No scene summary" : node.summary).font(.caption).lineLimit(3).foregroundStyle(.secondary)
            if node.isDisabled { Text("OMITTED").font(.caption2).foregroundStyle(.orange) }
        }.padding(14).frame(width: 192, height: 92, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(workspace.selectedSceneID == node.id ? Color.accentColor : .secondary.opacity(0.4), lineWidth: 2))
            .position(x: node.x - origin.x + 110 + translation.width, y: node.y - origin.y + 60 + translation.height)
            .gesture(DragGesture(coordinateSpace: .named("storyCanvas"))
                .updating($translation) { value, state, _ in state = value.translation }
                .onEnded { value in
                    workspace.edit("Move Scene Card") { try $0.moveStoryNode(node.id, x: node.x + value.translation.width, y: node.y + value.translation.height) }
                })
            .onTapGesture(count: 2) { workspace.selectedSceneID = node.id; workspace.mode = .edit }
            .onTapGesture { workspace.selectedSceneID = node.id }
            .contextMenu {
                Button(node.isDisabled ? "Include in Screenplay" : "Omit from Screenplay") {
                    workspace.edit("Change Scene Inclusion") { try $0.setSceneOmitted(node.id, omitted: !node.isDisabled) }
                }
                Button("Move Earlier in Script") { workspace.edit("Reorder Scene") { try $0.moveSceneInScript(node.id, offset: -1) } }
                Button("Move Later in Script") { workspace.edit("Reorder Scene") { try $0.moveSceneInScript(node.id, offset: 1) } }
            }
            .accessibilityLabel("Scene \(node.title)\(node.isDisabled ? ", omitted" : "")")
    }
}
#endif
