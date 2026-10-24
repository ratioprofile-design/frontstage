#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FrontstageCore

struct StoryTimelineView: View {
    @ObservedObject var workspace: Workspace
    @Binding var expanded: Bool
    @State private var preferences = TimelineDisplayPreferences(compact: true)
    @AppStorage("frontstage-timeline-mini") private var compactPreferences = ""
    @AppStorage("frontstage-timeline-full") private var fullPreferences = ""
    @State private var time = 0.0
    @State private var showingTiming = false
    @State private var minutesPerPage = 1.0
    @State private var showingMarker = false
    @State private var markerID: String?
    @State private var markerTitle = "Act"
    @State private var markerUnit = 0.0
    @State private var markerKind: StructuralBreakKind = .act
    private let sectionKinds = ["episodes", "acts", "chapters", "sections", "scenes", "beats", "tags", "characters", "heat"]
    private func isStructural(_ kind: String) -> Bool { ["episodes", "acts", "chapters", "sections"].contains(kind) }
    @State private var editingBeat: String?
    @State private var editingTag: String?
    @State private var emotion = "0"
    @State private var tension = "0"
    @State private var absolute = false
    @State private var duration = ""
    private var model: StoryTimeline? { try? StoryTimeline(project: workspace.project, timeBase: preferences.primary) }
    private var beatItems: [StoryTimeline.Item] { model?.tracks.first { $0.kind == "beats" }?.items ?? [] }
    private var current: StoryTimeline.Item? { beatItems.first { time >= $0.start && time < $0.start + $0.duration } }
    private func counter(_ base: TimelineTimeBase) -> String {
        guard let current else { return "–" }
        let fraction = max(0, (time - current.start) / current.duration)
        let beat = workspace.whiteboard.beats.first { $0.id == current.id }
        let pages = StoryTimeline.estimatedPages(beat?.html ?? "")
        switch base {
        case .beats: return String((beatItems.firstIndex { $0.id == current.id } ?? 0) + 1)
        case .time: return StoryTimeline.clock((model?.beatTimes[current.id] ?? 0) + (beat?.timelineDuration ?? (pages * workspace.project.timelineMinutesPerPage)) * fraction)
        case .pages: return String(format: "%.2f", (model?.beatPages[current.id] ?? 0) + 1 + pages * fraction)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            controls
            if let model {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ruler(model.end)
                        ForEach(sectionKinds.filter { !preferences.hidden.contains($0) }, id: \.self) { kind in
                            section(kind, model: model)
                        }
                    }
                    .frame(width: 174 + model.end * preferences.scale, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        Rectangle().fill(.cyan).frame(width: 1).offset(x: 174 + time * preferences.scale).allowsHitTesting(false)
                    }
                }
            }
        }.background(Color(white: 0.20))
        .onAppear { loadPreferences() }
        .onChange(of: expanded) { _, _ in loadPreferences() }
        .onChange(of: preferences) { _, value in
            guard value.isValid, let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else { return }
            if expanded { fullPreferences = text } else { compactPreferences = text }
        }
        .onChange(of: workspace.selectedBoardBeatID) { _, id in if current?.id != id, let item = beatItems.first(where: { $0.id == id }) { time = item.start } }
        .onChange(of: preferences.primary) { old, value in if preferences.secondary == value { preferences.secondary = old }; time = beatItems.first { $0.id == workspace.selectedBoardBeatID }?.start ?? 0 }
        .onChange(of: preferences.secondary) { old, value in if preferences.primary == value { preferences.primary = old } }
        .sheet(isPresented: $showingTiming) { timingEditor }
        .sheet(isPresented: $showingMarker) { structuralEditor }
        .sheet(isPresented: Binding(get: { editingBeat != nil }, set: { if !$0 { editingBeat = nil } })) { valueEditor }
    }
    private func loadPreferences() {
        let text = expanded ? fullPreferences : compactPreferences
        if let data = text.data(using: .utf8), let saved = try? JSONDecoder().decode(TimelineDisplayPreferences.self, from: data), saved.isValid { preferences = saved }
        else { preferences = TimelineDisplayPreferences(compact: !expanded) }
    }
    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(counter(preferences.primary) + "   " + counter(preferences.secondary)).font(.system(size: 18, design: .monospaced)).foregroundStyle(.cyan)
                Button(expanded ? "Restore Board" : "Expand Timeline") { expanded.toggle() }
                Button("−") { preferences.scale = max(12, preferences.scale / 1.25) }.accessibilityLabel("Zoom timeline out")
                Button("+") { preferences.scale = min(180, preferences.scale * 1.25) }.accessibilityLabel("Zoom timeline in")
                Picker("Primary", selection: $preferences.primary) { ForEach(TimelineTimeBase.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.fixedSize()
                Picker("Secondary", selection: $preferences.secondary) { ForEach(TimelineTimeBase.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.fixedSize()
                Picker("Title lines", selection: $preferences.lines) { ForEach(1...3, id: \.self) { Text("\($0) lines").tag($0) } }.fixedSize()
                Menu("Tracks") {
                    ForEach(sectionKinds, id: \.self) { kind in
                        Toggle(title(kind), isOn: Binding(get: { !preferences.hidden.contains(kind) }, set: { visible in
                            if visible { preferences.hidden.remove(kind) } else { preferences.hidden.insert(kind) }
                        }))
                    }
                }
                Menu("Add Break") { ForEach(StructuralBreakKind.allCases, id: \.self) { kind in Button(kind.title) { openMarker(nil, kind: kind) } } }
                Button("Timing…") { minutesPerPage = workspace.project.timelineMinutesPerPage; showingTiming = true }
            }.font(.caption).padding(5).fixedSize()
        }.frame(height: 38).background(Color(white: 0.16))
    }
    private func ruler(_ end: Double) -> some View {
        HStack(spacing: 0) {
            Text(preferences.primary == .beats ? "Beat Number" : "\(preferences.primary.rawValue) · estimated").font(.caption).frame(width: 174, height: 36)
            ZStack(alignment: .topLeading) {
                Color(white: 0.19)
                ForEach(Array(stride(from: 0.0, through: end, by: max(1, ceil(55 / preferences.scale)))), id: \.self) { value in
                    Text(String(format: "%.0f", value)).font(.system(size: 10, design: .monospaced)).offset(x: value * preferences.scale, y: 6)
                }
            }.frame(width: end * preferences.scale, height: 36).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { time = min(end, max(0, $0.location.x / preferences.scale)) }.onEnded { _ in if let current { workspace.selectBoardBeat(current.id) } })
                .accessibilityLabel("Timeline playhead").accessibilityValue(StoryTimeline.clock(time))
                .accessibilityAdjustableAction { direction in time = min(end, max(0, time + (direction == .increment ? 0.1 : -0.1))) }
        }
    }
    private func title(_ kind: String) -> String { ["episodes":"Episodes", "chapters":"Chapters", "sections":"Sections", "acts":"Acts", "scenes":"Scenes", "beats":"Beats", "tags":"Tags / Emotions", "characters":"Characters", "heat":"Heat Map"][kind] ?? kind }
    private func section(_ kind: String, model: StoryTimeline) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button((preferences.collapsed.contains(kind) ? "▸ " : "▾ ") + title(kind)) {
                    if !preferences.collapsed.insert(kind).inserted { preferences.collapsed.remove(kind) }
                }.buttonStyle(.plain).frame(width: 166, alignment: .leading).padding(4).background(Color(white: 0.28))
                Spacer()
            }.frame(height: 26)
            if !preferences.collapsed.contains(kind) {
                ForEach(model.tracks.filter { $0.kind == kind }) { track in
                    trackRow(track, end: model.end)
                }
                if model.tracks.filter({ $0.kind == kind }).isEmpty { Text("Assign \(kind) to beats to show tracks.").font(.caption).foregroundStyle(.secondary).padding(.leading, 180) }
            }
        }
    }
    private func trackRow(_ track: StoryTimeline.Track, end: Double) -> some View {
        let height: Double = track.kind == "beats" ? Double(preferences.lines * 15 + 10) : track.items.contains(where: { $0.value != nil }) ? 72 : 28
        return HStack(spacing: 0) {
            Text(track.title).font(.system(size: 11)).lineLimit(1).frame(width: 158, height: height, alignment: .leading).padding(.horizontal, 8).background(Color(white: 0.28))
            ZStack(alignment: .topLeading) {
                Color(white: 0.21)
                ForEach(Array(stride(from: 0.0, through: end, by: 5)), id: \.self) { value in Rectangle().fill(.black.opacity(0.12)).frame(width: 1).offset(x: value * preferences.scale) }
                if track.kind == "tags" {
                    Path { path in
                        for (index, item) in track.items.enumerated() {
                            let point = CGPoint(x: (item.start + item.duration / 2) * preferences.scale, y: item.value.map { height - 6 - min(100, max(0, $0)) / 100 * (height - 12) } ?? height / 2)
                            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }.stroke(Color(boardHex: track.items.first?.color ?? "#467e96"), lineWidth: 2)
                }
                ForEach(track.items) { item in
                    timelineItem(item, kind: track.kind, height: height)
                        .offset(x: item.start * preferences.scale)
                        .onDrag { NSItemProvider(object: ("timeline:" + track.kind + ":" + item.id) as NSString) }
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            guard let provider = providers.first else { return false }
                            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                                guard let raw = value as? String else { return }
                                Task { @MainActor in
                                    let parts = raw.split(separator: ":", maxSplits: 2).map(String.init)
                                    guard parts.count == 3, parts[0] == "timeline" else { return }
                                    if isStructural(parts[1]) {
                                        let title = workspace.project.storyMilestones.first { $0.id == parts[2] }?.title ?? "Act"
                                        let unit = workspace.whiteboard.beats.first { $0.id == item.beatID }?.start ?? item.start
                                        workspace.edit("Move Structural Break") { try $0.updateStoryMilestone(parts[2], title: title, page: unit) }
                                    } else if let source = model?.tracks.first(where: { $0.kind == parts[1] })?.items.first(where: { $0.id == parts[2] }) {
                                        let ids = parts[1] == "scenes" ? Set(beatItems.filter { $0.start >= source.start && $0.start < source.start + source.duration }.map(\.id)) : Set([source.beatID])
                                        workspace.edit("Reorder Timeline") { try $0.reorderTimelineBeats(ids, before: item.beatID) }
                                    }
                                }
                            }; return true
                        }
                        .contextMenu {
                            if isStructural(track.kind) {
                                Button("Edit Break…") { openMarker(item.id) }
                                Button("Remove Break") { workspace.edit("Remove Break") { $0.removeStoryMilestone(item.id) } }
                            }
                            if track.kind == "tags" { Button("Edit Emotion / Tension…") { startEditing(item.beatID, tag: track.title) } }
                            if track.kind == "beats" { Button("Duration Override…") { startEditing(item.beatID, tag: nil) } }
                            if !item.beatID.isEmpty { Button("Open Beat Editor") { workspace.popup.open(item.beatID, workspace: workspace) } }
                        }
                }
            }.frame(width: end * preferences.scale, height: height)
        }.overlay(alignment: .bottom) { Color.black.opacity(0.15).frame(height: 1) }
    }
    private func timelineItem(_ item: StoryTimeline.Item, kind: String, height: Double) -> some View {
        let color = Color(boardHex: item.color)
        return ZStack {
            Rectangle().fill(color.opacity(kind == "tags" ? 0.08 : kind == "characters" ? 0.35 : 0.85))
            if kind == "characters" || kind == "tags" {
                RoundedRectangle(cornerRadius: item.absolute ? 0 : 4).fill(color).frame(width: 8, height: 8)
                    .shadow(color: color, radius: max(0, item.tension) * 3)
                    .offset(y: item.value.map { (height - 12) / 2 - min(100, max(0, $0)) / 100 * (height - 12) } ?? 0)
            }
            else if kind != "heat" { Text(item.title).font(.system(size: 10)).lineLimit(preferences.lines).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 3) }
        }.frame(width: max(3, item.duration * preferences.scale - 1), height: height - 2)
            .overlay(Rectangle().stroke(workspace.selectedBoardBeatID == item.beatID ? .white : .clear))
            .contentShape(Rectangle()).help(item.title)
            .onTapGesture(count: 2) { if !item.beatID.isEmpty { workspace.popup.open(item.beatID, workspace: workspace) } }
            .onTapGesture { time = item.start; if isStructural(kind) { openMarker(item.id) }; if !item.beatID.isEmpty { workspace.selectBoardBeat(item.beatID) } }
    }
    private func openMarker(_ id: String?, kind: StructuralBreakKind = .act) {
        let marker = workspace.project.storyMilestones.first { $0.id == id }
        markerID = marker?.id; markerTitle = marker?.title ?? kind.title
        markerKind = marker?.kind ?? kind
        markerUnit = marker.map { $0.x / StorySequencer.pointsPerPage } ?? workspace.selectedBoardBeat?.start ?? 0
        showingMarker = true
    }
    private var structuralEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(markerID == nil ? "Add Structural Break" : "Edit Structural Break").font(.headline)
            Picker("Type", selection: $markerKind) { ForEach(StructuralBreakKind.allCases, id: \.self) { Text($0.title).tag($0) } }
            TextField("Title", text: $markerTitle)
            TextField("Story position", value: $markerUnit, format: .number)
            Text("Each break type is independent; an act can cross an episode boundary.").font(.caption)
            HStack {
                Button("Cancel") { showingMarker = false }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    workspace.edit("Structural Break") { project in
                        if let markerID { try project.updateStoryMilestone(markerID, title: markerTitle, page: markerUnit, kind: markerKind) }
                        else { _ = try project.addStoryMilestone(title: markerTitle, page: markerUnit, kind: markerKind) }
                    }
                    if workspace.errorMessage == nil { showingMarker = false }
                }.disabled(markerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !markerUnit.isFinite || markerUnit < 0 || markerUnit > 1_000_000 / StorySequencer.pointsPerPage)
            }
        }.padding(20).frame(width: 380)
    }
    private var timingEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimated Timing").font(.headline)
            TextField("Minutes per screenplay page", value: $minutesPerPage, format: .number)
            Text("Applies to estimated running time. Explicit beat durations remain unchanged. Page counts are still estimates.").font(.caption)
            HStack {
                Button("Cancel") { showingTiming = false }.keyboardShortcut(.cancelAction)
                Button("Save") { workspace.edit("Timeline Timing") { try $0.setTimelineMinutesPerPage(minutesPerPage) }; if workspace.errorMessage == nil { showingTiming = false } }
                    .disabled(!minutesPerPage.isFinite || minutesPerPage < 0.1 || minutesPerPage > 10)
            }
        }.padding(20).frame(width: 380)
    }
    private func startEditing(_ id: String, tag: String?) {
        guard let beat = workspace.whiteboard.beats.first(where: { $0.id == id }), !workspace.whiteboard.isLocked(beat) else { return }
        editingBeat = id; editingTag = tag; duration = beat.timelineDuration.map { String($0) } ?? ""
        if let tag { emotion = String(beat.emotionChanges?[tag] ?? 0); tension = String(beat.tensions?[tag] ?? 0); absolute = beat.emotionAbsoluteTags?.contains(tag) == true }
    }
    private var valueEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let tag = editingTag {
                Text(tag).font(.headline)
                Toggle("Absolute checkpoint (0–100)", isOn: $absolute)
                TextField("Emotion change", text: $emotion)
                TextField("Momentary tension (−5…5)", text: $tension)
            } else { Text("Duration in minutes; leave blank to estimate from screenplay."); TextField("Duration", text: $duration) }
            HStack {
                Button("Cancel") { editingBeat = nil }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let id = editingBeat else { return }
                    workspace.edit("Timeline Values") { project in
                        try project.updateBoardBeat(id) { beat in
                            if let tag = editingTag {
                                guard let value = Double(emotion), let t = Double(tension), value.isFinite, t.isFinite, value >= (absolute ? 0 : -100), value <= 100, abs(t) <= 5 else { throw ProjectError.invalidProject("Choose valid emotion and tension values") }
                                var changes = beat.emotionChanges ?? [:]; changes[tag] = value; beat.emotionChanges = changes
                                var values = beat.tensions ?? [:]; values[tag] = t; beat.tensions = values
                                var checkpoints = beat.emotionAbsoluteTags ?? []; checkpoints.removeAll { $0 == tag }; if absolute { checkpoints.append(tag) }; beat.emotionAbsoluteTags = checkpoints
                            } else {
                                let value = duration.isEmpty ? nil : Double(duration)
                                guard duration.isEmpty || (value.map { $0.isFinite && $0 > 0 && $0 <= 1000 } ?? false) else { throw ProjectError.invalidProject("Choose a duration between 0 and 1000 minutes") }
                                beat.timelineDuration = value
                            }
                        }
                    }; if workspace.errorMessage == nil { editingBeat = nil }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 380)
    }
}
#endif
