#if os(macOS)
import SwiftUI
import AppKit
import FrontstageCore

struct WhiteboardWorkspace: View {
    @ObservedObject var workspace: Workspace
    @State private var selection = Set<String>()
    @State private var blockSelection = Set<String>()
    @State private var showProperties = true
    @State private var showTimeline = true
    @State private var showCharacters = false
    @State private var drawing = false
    @State private var fitRequest = 0
    @State private var linkReason = ""
    @State private var showMarkerEditor = false
    @State private var markerID: String?
    @State private var markerTitle = "Act I"
    @State private var markerTime = 0.0
    private var board: Whiteboard { workspace.whiteboard }
    private var markers: [StoryMilestone] { workspace.project.storyMilestones }
    private var timelineEnd: Double { max(20, board.beats.map { $0.start + $0.duration }.max() ?? 20, (markers.last?.x ?? 0) / StorySequencer.pointsPerPage + 3) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(workspace.project.name).font(.caption.weight(.semibold))
                Spacer()
                Toggle("Script", isOn: $workspace.showBoardScript).toggleStyle(.button)
                Toggle("Timeline", isOn: $showTimeline).toggleStyle(.button)
                Toggle("Properties", isOn: $showProperties).toggleStyle(.button)
            }.font(.caption).buttonStyle(.borderless).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(white: 0.24))
            HSplitView {
                if workspace.showBoardScript {
                    snippetPanel.frame(minWidth: 230, idealWidth: 280, maxWidth: 420)
                }
                VStack(spacing: 0) {
                    if showTimeline { timeline.frame(height: (showCharacters ? 150 : 88) + (markers.isEmpty ? 0 : 20)) }
                    if let cause = workspace.pendingBoardCauseID {
                        HStack {
                            Text("Choose an effect for “\(board.beats.first { $0.id == cause }?.title ?? "Cause")”")
                            Spacer(); Button("Cancel") { workspace.pendingBoardCauseID = nil }
                        }.font(.caption).padding(6).background(.cyan.opacity(0.18))
                    }
                    WhiteboardCanvas(workspace: workspace, selection: $selection, blockSelection: $blockSelection, drawing: drawing, fitRequest: fitRequest)
                    bottomTools
                }.frame(minWidth: 360)
                if showProperties { properties.frame(minWidth: 210, idealWidth: 240, maxWidth: 300) }
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showMarkerEditor) { markerEditor }
        .onAppear { initializeSelection() }
        .onChange(of: workspace.selectedSceneID) { _, id in
            if workspace.selectedBoardBeat?.sceneID != id, let beat = board.orderedBeats.first(where: { $0.sceneID == id }) { workspace.selectBoardBeat(beat.id); selection = [beat.id] }
        }
        .onChange(of: workspace.selectedBoardBeatID) { _, id in if let id, !selection.contains(id) { selection = [id] } }
        .onChange(of: workspace.changeID) { _, _ in
            selection.formIntersection(Set(board.beats.map(\.id)))
            blockSelection.formIntersection(Set(board.blocks.map(\.id)))
        }
    }

    private var bottomTools: some View {
        HStack(spacing: 12) {
            Button { drawing = false } label: { Image(systemName: "cursorarrow") }.tint(drawing ? .gray : .cyan)
            Button { drawing.toggle() } label: { Image(systemName: "pencil.tip") }.tint(drawing ? .cyan : .gray)
                .help("Draw board annotations")
            Button { fitRequest += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Fit selection or board")
            Toggle("Ripple", isOn: $workspace.whiteboardRipple).toggleStyle(.button)
            Button { changeZoom(0.8) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int(board.viewport.zoom * 100))%").monospacedDigit().frame(width: 36)
            Button { changeZoom(1.25) } label: { Image(systemName: "plus.magnifyingglass") }
            Spacer()
            Menu("+ Layer") {
                Button("Story Layer") { addLayer(unused: false) }
                Button("Unused Layer") { addLayer(unused: true) }
            }
            Button("+ Block") { workspace.addWhiteboardBeat(standalone: false) }
            Button("+ Beat") { workspace.addWhiteboardBeat() }
            Button("Add to Block") { workspace.addWhiteboardBeat(blockID: workspace.selectedBoardBeat?.blockID) }
                .disabled(workspace.selectedBoardBeat == nil)
            Menu {
                Button("Group Selected Blocks") { workspace.edit("Group Blocks") { try $0.groupBoardBlocks(blockSelection, name: "New Group") } }
                    .disabled(blockSelection.count < 2)
                Button("Ungroup Selected Groups") { workspace.edit("Ungroup Blocks") { try $0.ungroupBoardBlocks(blockSelection) } }
                    .disabled(!board.blocks.contains { $0.parentID.map(blockSelection.contains) == true })
                Button("Resolve Causal Flow") { workspace.edit("Resolve Causes") { try $0.editWhiteboard { try $0.resolveCauses() } } }
                Button("Compact Causal Time") { workspace.edit("Compact Causal Time") { try $0.editWhiteboard { try $0.compactCauses() } } }
                    .help("Remove time gaps while respecting causes and locked starts. Board placement stays independent.")
                Button("Add Act / Marker…") { editMarker() }
                Button("Apply Story Order to Script") { workspace.edit("Apply Story Order") { try $0.applyWhiteboardStoryOrder() } }
                Button("Merge Selected Snippets") { workspace.edit("Merge Snippets") { try $0.mergeBoardBeats(selection) } }.disabled(selection.count < 2)
                Button("Clear Annotations") { workspace.edit("Clear Drawing") { try $0.editWhiteboard { $0.strokes = [] } } }
            } label: { Image(systemName: "ellipsis.circle") }
            Text("\(board.beats.count) beats").foregroundStyle(.secondary)
        }.font(.system(size: 10)).buttonStyle(.borderless).padding(7).background(Color(white: 0.2))
    }

    private var timeline: some View {
        GeometryReader { proxy in
            let end = timelineEnd
            let scale = max(12, (proxy.size.width - 90) / end)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 2) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(stride(from: 0.0, through: end, by: max(5, (end / 100).rounded(.up)))), id: \.self) { mark in
                            Text("\(Int(mark))").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                .offset(x: 90 + mark * scale, y: 3)
                        }
                    }.frame(height: 20)
                    if !markers.isEmpty {
                        HStack(spacing: 0) {
                            Text("Acts / Markers").font(.system(size: 9)).frame(width: 90, alignment: .leading)
                            ZStack(alignment: .leading) {
                                ForEach(markers) { marker in
                                    Button(marker.title) { editMarker(marker) }.font(.system(size: 9)).buttonStyle(.borderless)
                                        .padding(.horizontal, 5).frame(height: 17).background(Color.blue.opacity(0.6))
                                        .offset(x: marker.x / StorySequencer.pointsPerPage * scale)
                                        .contextMenu {
                                            Button("Edit Marker…") { editMarker(marker) }
                                            Button("Remove Marker") { workspace.edit("Remove Marker") { $0.removeStoryMilestone(marker.id) } }
                                        }
                                }
                            }.frame(width: end * scale, height: 18)
                        }
                    }
                    timelineRow("Scenes", scale: scale, snippets: false)
                    timelineRow("Snippets", scale: scale, snippets: true)
                    if showCharacters {
                        let names = Array(Set(board.beats.flatMap(\.characters))).sorted()
                        ForEach(Array(names.prefix(3)), id: \.self) { name in
                            HStack(spacing: 0) {
                                Text(name).font(.system(size: 9)).lineLimit(1).frame(width: 90, alignment: .leading)
                                ZStack(alignment: .leading) {
                                    ForEach(board.beats.filter { $0.characters.contains(name) }) { beat in
                                        Circle().fill(Color(boardHex: beat.color)).frame(width: 5, height: 5).offset(x: beat.start * scale)
                                    }
                                }.frame(width: end * scale, height: 12)
                            }
                        }
                    }
                    Button(showCharacters ? "Hide character tracks" : "Character tracks") { showCharacters.toggle() }
                        .font(.system(size: 9)).buttonStyle(.borderless).foregroundStyle(.secondary)
                }.frame(width: end * scale + 100, alignment: .leading)
            }.padding(.horizontal, 6)
        }.background(Color(white: 0.19)).overlay(alignment: .bottom) { Divider() }
    }

    private func timelineRow(_ label: String, scale: Double, snippets: Bool) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 9)).frame(width: 90, alignment: .leading)
            ZStack(alignment: .leading) {
                ForEach(board.orderedBeats) { beat in
                    Button { workspace.selectBoardBeat(beat.id); selection = [beat.id] } label: {
                        Text(snippets ? "" : (workspace.project.scenes.first { $0.id == beat.sceneID }?.heading.location ?? beat.title))
                            .font(.system(size: 8)).lineLimit(1).frame(width: max(8, beat.duration * scale - 1), height: 19)
                            .background(snippets ? Color(boardHex: beat.color) : Color(red: 0.23, green: 0.4, blue: 0.66))
                            .overlay(Rectangle().stroke(workspace.selectedBoardBeatID == beat.id ? .white : .black.opacity(0.3), lineWidth: 1))
                    }.buttonStyle(.plain).offset(x: beat.start * scale)
                }
            }.frame(width: timelineEnd * scale, height: 20)
        }
    }

    private func editMarker(_ marker: StoryMilestone? = nil) {
        markerID = marker?.id; markerTitle = marker?.title ?? "Act \(markers.count + 1)"
        markerTime = marker.map { $0.x / StorySequencer.pointsPerPage } ?? workspace.selectedBoardBeat?.start ?? 0
        showMarkerEditor = true
    }
    private var markerEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(markerID == nil ? "Add Act / Marker" : "Edit Act / Marker").font(.headline)
            TextField("Name", text: $markerTitle)
            TextField("Estimated story time", value: $markerTime, format: .number)
            Text("A visual guide in estimated story time; it does not force beats into an act.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { showMarkerEditor = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    workspace.edit("Story Marker") { project in
                        if let markerID { try project.updateStoryMilestone(markerID, title: markerTitle, page: markerTime) }
                        else { _ = try project.addStoryMilestone(title: markerTitle, page: markerTime) }
                    }
                    showMarkerEditor = false
                }.keyboardShortcut(.defaultAction)
                    .disabled(markerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !markerTime.isFinite || markerTime < 0 || markerTime > 1_000_000 / StorySequencer.pointsPerPage)
            }
        }.textFieldStyle(.roundedBorder).padding(22).frame(width: 370)
    }

    private var snippetPanel: some View {
        VStack(spacing: 0) {
            Text("SCRIPT & SNIPPETS").font(.system(size: 10, weight: .semibold)).padding(8)
            if let beat = workspace.selectedBoardBeat {
                Text(beat.title).font(.headline).padding(8)
                Picker("Format", selection: Binding(get: { workspace.editor.activeElement }, set: { workspace.editor.format($0) })) {
                    ForEach(ScreenplayElement.editable, id: \.self) { Text($0.label).tag($0) }
                }.padding(.horizontal, 8)
                ScreenplayEditor(html: Binding(get: { workspace.whiteboard.beats.first { $0.id == beat.id }?.html ?? "" }, set: { html in
                    workspace.edit("Edit Snippet", key: "snippet-\(beat.id)") { try $0.updateBoardBeat(beat.id) { $0.html = html } }
                }), controller: workspace.editor, width: 260, typography: workspace.project.scriptLayout, onError: { workspace.errorMessage = $0 }, editable: workspace.project.scenes.first { $0.id == beat.sceneID }?.isTextLocked != true).id(beat.id)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(board.orderedBeats) { item in
                            Button { workspace.selectBoardBeat(item.id) } label: {
                                HStack {
                                    Circle().fill(Color(boardHex: item.color)).frame(width: 6, height: 6)
                                    Text(item.title).font(.caption).lineLimit(2)
                                    Spacer()
                                }.padding(7).frame(maxWidth: .infinity)
                                    .background(item.id == beat.id ? Color.white.opacity(0.12) : .clear)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 170)
            } else { ContentUnavailableView("Select a beat", systemImage: "text.alignleft") }
        }.background(Color(white: 0.25))
    }

    private var properties: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("▾ Beat Properties").font(.caption.weight(.semibold))
                if let beat = workspace.selectedBoardBeat {
                    TextField("Beat name", text: beatText(beat.id, \.title, label: "Beat Name"))
                    Picker("Type", selection: Binding(get: { beat.kind }, set: { kind in update(beat.id, "Beat Type") { $0.kind = kind } })) {
                        Text("Story Beat").tag(BoardBeatKind.story); Text("Subtext Beat").tag(BoardBeatKind.subtext)
                    }.pickerStyle(.segmented)
                    Toggle("Must Be Caused", isOn: Binding(get: { beat.mustBeCaused }, set: { value in update(beat.id, "Cause Requirement") { $0.mustBeCaused = value } }))
                    Button("Create Dependency From…") { workspace.pendingBoardCauseID = beat.id }
                    TextField("Synopsis", text: beatText(beat.id, \.synopsis, label: "Synopsis"), axis: .vertical).lineLimit(2...5)
                    if let scene = workspace.project.scenes.first(where: { $0.id == beat.sceneID }) {
                        DisclosureGroup("Scene Heading") {
                            TextField("INT. / EXT.", text: headingField(scene.id, \.prefix))
                            TextField("Location", text: headingField(scene.id, \.location))
                            TextField("DAY / NIGHT", text: headingField(scene.id, \.time))
                            TextField("Scene number", text: Binding(get: { workspace.project.scenes.first { $0.id == scene.id }?.sceneNumber ?? "" }, set: { workspace.updateScene(id: scene.id, sceneNumber: $0) }))
                        }.disabled(scene.isTextLocked)
                    }
                    Button("Open Popup Editor") { workspace.popup.open(beat.id, workspace: workspace) }
                    Button("Research & Attachments…") { workspace.openBoardResearch(beat.id) }
                    Divider()
                    Text("▾ Characters").font(.caption.weight(.semibold))
                    listField("Characters", beat: beat, characters: true)
                    Text("▾ Tags").font(.caption.weight(.semibold)); listField("Tags", beat: beat, characters: false)
                    HStack {
                        ForEach(["#39798c", "#a34eae", "#ab7d22", "#34834b", "#535f8a"], id: \.self) { color in
                            Button { update(beat.id, "Beat Color") { $0.color = color } } label: {
                                Circle().fill(Color(boardHex: color)).frame(width: 17, height: 17)
                            }.buttonStyle(.plain)
                        }
                    }
                    Divider(); Text("▾ Story Time").font(.caption.weight(.semibold))
                    numberField("Start", beat: beat, duration: false)
                    numberField("Duration", beat: beat, duration: true)
                    Toggle("Omitted", isOn: Binding(get: { beat.omitted }, set: { value in update(beat.id, "Beat Inclusion") { $0.omitted = value } }))
                    Toggle("Locked", isOn: Binding(get: { beat.locked }, set: { value in update(beat.id, "Beat Lock") { $0.locked = value } }))
                    if let block = board.blocks.first(where: { $0.id == beat.blockID }) {
                        Divider(); Text("▾ Block & Layer").font(.caption.weight(.semibold))
                        TextField("Block name", text: Binding(get: { block.name }, set: { value in
                            workspace.edit("Block Name", key: "block-\(block.id)") { try $0.editWhiteboard { board in
                                if let i = board.blocks.firstIndex(where: { $0.id == block.id }) { board.blocks[i].name = value }
                            } }
                        }))
                        Picker("Layer", selection: Binding(get: { block.layerID }, set: { layer in
                            workspace.edit("Move Block to Layer") { try $0.moveBoardBlocks([block.id], delta: .init(), layerID: layer) }
                        })) { ForEach(board.layers) { Text($0.name).tag($0.id) } }
                        TextField("Layer name", text: Binding(get: { board.layers.first { $0.id == block.layerID }?.name ?? "" }, set: { value in
                            workspace.edit("Layer Name", key: "layer-\(block.layerID)") { try $0.editWhiteboard { board in
                                if let i = board.layers.firstIndex(where: { $0.id == block.layerID }) { board.layers[i].name = value }
                            } }
                        }))
                        if let layer = board.layers.first(where: { $0.id == block.layerID }) {
                            Toggle("Lock Layer", isOn: Binding(get: { layer.locked }, set: { value in
                                workspace.edit("Layer Lock") { try $0.editWhiteboard { board in if let i = board.layers.firstIndex(where: { $0.id == layer.id }) { board.layers[i].locked = value } } }
                            }))
                            Toggle("Unused Layer", isOn: Binding(get: { layer.unused }, set: { value in
                                workspace.edit("Layer Inclusion") { try $0.editWhiteboard { board in if let i = board.layers.firstIndex(where: { $0.id == layer.id }) { board.layers[i].unused = value } } }
                            }))
                        }
                        HStack {
                            Text("Width")
                            TextField("Width", value: Binding(get: { block.width }, set: { value in
                                workspace.edit("Resize Block") { try $0.resizeBoardBlock(block.id, width: value) }
                            }), format: .number)
                        }
                    }
                    dependencyProperties(beat)
                } else { Text("Select a beat to edit its properties.").foregroundStyle(.secondary) }
                Divider(); Text("▾ Story Issues (\(board.issues.count))").font(.caption.weight(.semibold))
                ForEach(board.issues) { issue in
                    Button(issue.message) { if let id = issue.beatIDs.sorted().first { workspace.selectBoardBeat(id) } }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.orange)
                }
            }.padding(10).font(.caption).textFieldStyle(.roundedBorder)
        }.background(Color(white: 0.28))
    }

    private func dependencyProperties(_ beat: BoardBeat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider(); Text("▾ Causes & Effects").fontWeight(.semibold)
            ForEach(board.dependencies.filter { $0.cause == beat.id || $0.effect == beat.id }) { edge in
                let other = edge.cause == beat.id ? edge.effect : edge.cause
                HStack {
                    Button("\(edge.cause == beat.id ? "→" : "←") \(board.beats.first { $0.id == other }?.title ?? "Beat")") { workspace.selectBoardBeat(other) }
                        .buttonStyle(.plain)
                    Spacer()
                    Button { workspace.edit("Remove Dependency") { try $0.editWhiteboard { $0.dependencies.removeAll { $0.id == edge.id } } } }
                        label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                TextField("Reason", text: Binding(get: { edge.reason }, set: { value in
                    workspace.edit("Dependency Reason", key: "edge-\(edge.id)") { try $0.editWhiteboard { board in
                        if let i = board.dependencies.firstIndex(where: { $0.id == edge.id }) { board.dependencies[i].reason = value }
                    } }
                }))
                Toggle("Reference only", isOn: Binding(get: { edge.reference }, set: { value in
                    workspace.edit("Dependency Type") { try $0.editWhiteboard { board in
                        if let i = board.dependencies.firstIndex(where: { $0.id == edge.id }) { board.dependencies[i].reference = value }
                        _ = try board.causalOrder()
                    } }
                }))
            }
        }
    }

    private func beatText(_ id: String, _ path: WritableKeyPath<BoardBeat, String>, label: String) -> Binding<String> {
        Binding(get: { workspace.whiteboard.beats.first { $0.id == id }?[keyPath: path] ?? "" }, set: { value in update(id, label) { $0[keyPath: path] = value } })
    }
    private func headingField(_ id: Decimal, _ path: WritableKeyPath<SceneHeading, String>) -> Binding<String> {
        Binding(get: { workspace.project.scenes.first { $0.id == id }?.heading[keyPath: path] ?? "" }, set: { text in
            guard var heading = workspace.project.scenes.first(where: { $0.id == id })?.heading else { return }
            heading[keyPath: path] = text; workspace.updateScene(id: id, heading: heading)
        })
    }
    private func update(_ id: String, _ label: String, _ action: (inout BoardBeat) -> Void) {
        workspace.edit(label, key: "\(id)-\(label)") { try $0.updateBoardBeat(id, action) }
    }
    private func listField(_ title: String, beat: BoardBeat, characters: Bool) -> some View {
        TextField(title, text: Binding(get: { (characters ? beat.characters : beat.tags).joined(separator: ", ") }, set: { value in
            update(beat.id, title) { if characters { $0.characters = value.boardList } else { $0.tags = value.boardList } }
        }))
    }
    private func numberField(_ title: String, beat: BoardBeat, duration: Bool) -> some View {
        HStack {
            Text(title).frame(width: 55, alignment: .leading)
            TextField(title, value: Binding(get: { duration ? beat.duration : beat.start }, set: { value in
                workspace.edit("Change Story Time") { try $0.editWhiteboard { board in
                    guard let i = board.beats.firstIndex(where: { $0.id == beat.id }), !board.isLocked(board.beats[i]) else { throw ProjectError.invalidProject("unlock this beat first") }
                    if duration { board.beats[i].duration = value } else { board.beats[i].start = value }
                    try board.resolveCauses()
                } }
            }), format: .number.precision(.fractionLength(1)))
        }
    }
    private func changeZoom(_ factor: Double) {
        workspace.edit("Whiteboard View", key: "whiteboard-viewport") { try $0.editWhiteboard { $0.viewport.zoom = max(0.15, min(3, $0.viewport.zoom * factor)) } }
    }
    private func addLayer(unused: Bool) {
        workspace.edit("Add Layer") { try $0.editWhiteboard { $0.layers.append(BoardLayer(name: unused ? "Unused" : "New Layer", unused: unused)) } }
    }
    private func initializeSelection() {
        do {
            _ = try workspace.project.whiteboard()
            if let beat = workspace.selectedBoardBeat ?? board.orderedBeats.first { workspace.selectBoardBeat(beat.id); selection = [beat.id] }
        } catch { workspace.errorMessage = error.localizedDescription }
    }
}
#endif
