#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import FrontstageCore

@main
struct FrontstageApp: App {
    @StateObject private var workspace = Workspace(recoveryStore: .applicationDefault())
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some SwiftUI.Scene {
        Window("Frontstage", id: "workspace") {
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 850, minHeight: 560)
                .onAppear { delegate.workspace = workspace; workspace.checkRecovery() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project", action: workspace.newProject).keyboardShortcut("n")
                Button("Open or Import…", action: workspace.open).keyboardShortcut("o")
                Button("Import Script Document…", action: workspace.importScriptDocument)
                Button("Import Spreadsheet to Research…", action: workspace.importSpreadsheet)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save", action: workspace.save).keyboardShortcut("s")
                Button("Save As…") { workspace.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("Export Screenplay PDF…", action: workspace.exportPDF)
                    .disabled(!workspace.hasActiveScenes)
                Button("Export Screenplay DOCX…", action: workspace.exportDOCX).disabled(!workspace.hasActiveScenes)
                Button("Export Schedule XLSX…", action: workspace.exportScheduleXLSX)
                Button("Print Screenplay…", action: workspace.printScreenplay).keyboardShortcut("p")
                    .disabled(!workspace.hasActiveScenes)
            }
            CommandMenu("Screenplay") {
                ForEach(Array(ScreenplayElement.editable.enumerated()), id: \.element.rawValue) { index, element in
                    Button(element.label) { workspace.focusedScreenplayController?.format(element) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.option])
                        .disabled(workspace.selectedScene == nil || (workspace.mode != .edit && workspace.mode != .board))
                }
            }
            CommandMenu("Project") {
                Button("Undo \(workspace.history.undoLabel)", action: workspace.undoProject)
                    .keyboardShortcut("z", modifiers: [.command, .option]).disabled(!workspace.history.canUndo)
                Button("Redo \(workspace.history.redoLabel)", action: workspace.redoProject)
                    .keyboardShortcut("z", modifiers: [.command, .option, .shift]).disabled(!workspace.history.canRedo)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: Workspace?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace?.confirmDiscardOrSave() == false ? .terminateCancel : .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
final class Workspace: ObservableObject {
    var focusedScreenplayController: ScreenplayEditorController? {
        if let focused = popup.focusedController { return focused }
        guard let text = editor.textView, let window = text.window,
              NSApp.keyWindow === window, window.firstResponder === text else { return nil }
        return editor
    }
    enum Mode: String, CaseIterable {
        case edit = "Write", pages = "Pages", revisions = "Revisions", board = "Whiteboard", people = "People", breakdown = "Breakdown", production = "Production", writingTools = "Writing Tools", studio = "Research & Studio", shared = "Shared Projects"
    }
    @Published private(set) var project = Project()
    @Published var selectedSceneID: Decimal? {
        didSet { if oldValue != selectedSceneID { editor.textView?.undoManager?.removeAllActions() } }
    }
    @Published private(set) var hasChanges = false
    @Published var errorMessage: String?
    @Published var selectedBoardBeatID: String?
    @Published var pendingBoardCauseID: String?
    @Published var showBoardScript = false
    @Published var whiteboardRipple = true
    @Published var selectedResearchID: String?
    @Published var mode = Mode.board {
        didSet { if oldValue != mode { editor.textView?.undoManager?.removeAllActions() } }
    }
    @Published var paper = ScreenplayPaper.letter
    @Published private(set) var preview: PDFDocument?
    @Published private(set) var history = ProjectHistory()
    @Published private(set) var recoveryCandidate: Project?
    @Published private(set) var recoveryStatus = ""
    @Published private(set) var changeID = 0
    private(set) var documentSessionID = UUID()
    @Published private(set) var whiteboardCache: Whiteboard?
    let editor = ScreenplayEditorController()
    let popup = BeatPopupPresenter()
    let sharedProjects = SharedProjectClient()
    private var saveURL: URL?
    private var savedProject: Project? = Project()
    private let recoveryStore: RecoveryStore?
    private var recoveryTask: Task<Void, Never>?
    private var checkedRecovery = false
    private var recoveryBlocked = false

    init(recoveryStore: RecoveryStore? = nil) { self.recoveryStore = recoveryStore }

    func checkRecovery() {
        guard !checkedRecovery else { return }
        checkedRecovery = true
        do { recoveryCandidate = try recoveryStore?.load() }
        catch {
            recoveryBlocked = true
            recoveryStatus = "Recovery disabled: unreadable copy preserved"
            errorMessage = "The recovery copy could not be read. It has been kept on disk and will not be overwritten. \(error.localizedDescription)"
        }
    }

    func recoverSession() {
        guard let candidate = recoveryCandidate else { return }
        recoveryCandidate = nil
        loadCopy(candidate)
    }

    func loadCopy(_ imported: Project) {
        documentSessionID = UUID()
        sharedProjects.detach()
        popup.close()
        selectedBoardBeatID = nil
        recoveryTask?.cancel()
        editor.textView?.undoManager?.removeAllActions()
        project = imported
        savedProject = nil
        history = ProjectHistory()
        selectedSceneID = project.scenes.first?.id
        saveURL = nil
        mode = .board
        preview = nil
        changed()
    }

    func discardRecovery() {
        do { try recoveryStore?.clear(); recoveryCandidate = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func flushRecovery() throws {
        recoveryTask?.cancel()
        guard !recoveryBlocked else { throw ProjectError.invalidProject("an unreadable recovery copy must be recovered manually before automatic recovery can resume") }
        if hasChanges {
            try recoveryStore?.save(project)
            if recoveryStore != nil { recoveryStatus = "Recovery copy saved" }
        } else { try recoveryStore?.clear() }
    }

    func edit(_ label: String, key: String? = nil, _ operation: (inout Project) throws -> Void) {
        let previous = project
        do {
            try operation(&project)
            guard project != previous else { return }
            history.record(previous, label: label, key: key)
            changed()
        } catch { project = previous; errorMessage = error.localizedDescription }
    }

    func undoProject() {
        guard let previous = history.undo(current: project) else { return }
        project = previous
        reconcileSelection()
        changed()
    }

    func redoProject() {
        guard let next = history.redo(current: project) else { return }
        project = next
        reconcileSelection()
        changed()
    }

    private func reconcileSelection() {
        if !project.scenes.contains(where: { $0.id == selectedSceneID }) { selectedSceneID = project.scenes.first?.id }
        editor.textView?.undoManager?.removeAllActions()
        for id in popup.panels.keys { popup.controller(for: id)?.textView?.undoManager?.removeAllActions() }
        if !whiteboard.beats.contains(where: { $0.id == selectedBoardBeatID }) { selectedBoardBeatID = whiteboard.orderedBeats.first?.id }
    }

    private func didSave() {
        savedProject = project
        hasChanges = false
        recoveryTask?.cancel()
        do { if !recoveryBlocked { try recoveryStore?.clear(); recoveryStatus = "" } }
        catch { recoveryStatus = "Saved project; recovery cleanup failed" }
    }

    var selectedScene: FrontstageCore.Scene? {
        project.scenes.first { $0.id == selectedSceneID }
    }
    var hasActiveScenes: Bool { project.scenes.contains { !$0.isDisabled } }

    func newProject() {
        guard confirmDiscardOrSave() else { return }
        documentSessionID = UUID()
        sharedProjects.detach()
        popup.close(); selectedBoardBeatID = nil
        recoveryTask?.cancel()
        if !recoveryBlocked {
            do { try recoveryStore?.clear() }
            catch { errorMessage = error.localizedDescription; return }
        }
        editor.textView?.undoManager?.removeAllActions()
        project = Project()
        whiteboardCache = nil
        savedProject = project
        history = ProjectHistory()
        saveURL = nil
        hasChanges = false
        selectedSceneID = nil
        mode = .board
        preview = nil
    }

    func addScene() {
        if project.preservedState["frontstageWhiteboard"] != nil {
            addWhiteboardBeat()
            mode = .board
            return
        }
        var id: Decimal?
        edit("Add Scene") { id = $0.addScene() }
        selectedSceneID = id
        mode = .board
    }

    func updateScene(id: Decimal, title: String? = nil, html: String? = nil, summary: String? = nil,
                     heading: SceneHeading? = nil, sceneNumber: String? = nil) {
        let field = html != nil ? "Text" : heading != nil ? "Heading" : title != nil ? "Title" : summary != nil ? "Summary" : "Number"
        edit("Edit Scene \(field)", key: "\(id)-\(field)") {
            try $0.updateScene(id: id, title: title, html: html, summary: summary,
                                    heading: heading, sceneNumber: sceneNumber)
        }
    }

    func rename(_ name: String) {
        edit("Rename Project", key: "name") { $0.name = name }
    }

    private func changed() {
        whiteboardCache = try? project.whiteboard()
        changeID &+= 1
        hasChanges = project != savedProject
        preview = nil
        if mode == .pages { makePreview() }
        recoveryTask?.cancel()
        if recoveryStore != nil && !recoveryBlocked {
            recoveryStatus = hasChanges ? "Recovery copy pending…" : ""
            recoveryTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                do { try self.flushRecovery() }
                catch { self.recoveryStatus = "Recovery unavailable: \(error.localizedDescription)" }
            }
        }
    }

    func makePreview() {
        guard hasActiveScenes else { preview = nil; return }
        do {
            let result = try ScreenplayPDF.render(project: project, paper: paper)
            guard let document = PDFDocument(data: result.data) else { throw ScreenplayPDFError.cannotCreatePDF }
            preview = document
        } catch { preview = nil; errorMessage = error.localizedDescription }
    }

    func exportPDF() {
        do {
            let result = try ScreenplayPDF.render(project: project, paper: paper)
            try exportPDF(result, name: project.name)
        } catch { errorMessage = error.localizedDescription }
    }

    func exportPDF(_ result: RenderedScreenplay, name: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = name.replacingOccurrences(of: "/", with: "-") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try result.save(to: url)
    }

    func printScreenplay() {
        do {
            let result = try ScreenplayPDF.render(project: project, paper: paper)
            try printPDF(result)
        } catch { errorMessage = error.localizedDescription }
    }

    func printPDF(_ result: RenderedScreenplay) throws {
            guard let document = PDFDocument(data: result.data) else { throw ScreenplayPDFError.cannotCreatePDF }
            let settings = NSPrintInfo.shared.copy() as! NSPrintInfo
            settings.paperSize = NSSize(width: result.paper.width, height: result.paper.height)
            settings.orientation = .portrait
            guard let operation = document.printOperation(for: settings, scalingMode: .pageScaleToFit, autoRotate: false) else {
                throw ScreenplayPDFError.cannotCreatePDF
            }
            operation.run()
    }

    func open() {
        guard confirmDiscardOrSave() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json,
            UTType(filenameExtension: "backstage") ?? .data,
            UTType(filenameExtension: "frontstage") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Legacy projects are imported as copies. Save them as new Frontstage files."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try Project.load(from: url)
            // Every open starts a copy. No source project is ever a default save destination.
            loadCopy(imported)
        } catch { errorMessage = error.localizedDescription }
    }

    func save() { _ = saveCurrent() }

    @discardableResult
    private func saveCurrent() -> Bool {
        guard let saveURL else { return saveAs() }
        do {
            try project.save(to: saveURL)
            didSave()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "frontstage") ?? .json]
        panel.nameFieldStringValue = "\(project.name.replacingOccurrences(of: "/", with: "-" )).frontstage"
        panel.message = "Save a native Frontstage copy. Your imported source stays unchanged."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try project.save(to: url)
            saveURL = url
            didSave()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func confirmDiscardOrSave() -> Bool {
        guard hasChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(project.name)?"
        alert.informativeText = "Unsaved edits will be lost if you discard them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveCurrent()
        case .alertThirdButtonReturn:
            recoveryTask?.cancel()
            do { if !recoveryBlocked { try recoveryStore?.clear() }; return true }
            catch { errorMessage = error.localizedDescription; return false }
        default: return false
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var workspace: Workspace
    @State private var columns = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            VStack(alignment: .leading, spacing: 12) {
                Text("FRONTSTAGE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal)
                TextField("Project name", text: Binding(
                    get: { workspace.project.name }, set: { workspace.rename($0) }))
                    .font(.title3.weight(.semibold)).textFieldStyle(.plain).padding(.horizontal)
                List(workspace.project.scenes, selection: $workspace.selectedSceneID) { scene in
                    Label(scene.title.isEmpty ? "Untitled Scene" : scene.title, systemImage: "doc.text")
                        .tag(scene.id)
                }
                HStack {
                    Text("\(workspace.project.scenes.count) scenes").foregroundStyle(.secondary)
                    Spacer()
                    Button(action: workspace.addScene) { Image(systemName: "plus") }
                        .help("Add Scene")
                }.padding()
            }.padding(.top)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if workspace.mode == .shared {
                SharedProjectsView(workspace: workspace, client: workspace.sharedProjects)
            } else if workspace.mode == .studio {
                StudioView(workspace: workspace)
            } else if workspace.mode == .writingTools {
                WritingToolsView(workspace: workspace)
            } else if workspace.mode == .production {
                ProductionView(workspace: workspace)
            } else if workspace.mode == .people {
                PeopleView(workspace: workspace)
            } else if workspace.mode == .breakdown {
                BreakdownView(workspace: workspace)
            } else if workspace.mode == .board {
                StoryWorkspaceView(workspace: workspace, boardFirst: true)
            } else if workspace.mode == .revisions {
                RevisionsView(workspace: workspace)
            } else if workspace.mode == .pages {
                if let preview = workspace.preview {
                    VStack(spacing: 0) {
                        Text("\(preview.pageCount) pages · \(workspace.paper.label)")
                            .font(.caption).foregroundStyle(.secondary).padding(8)
                        ScreenplayPDFView(document: preview)
                    }
                } else {
                    ContentUnavailableView("No screenplay pages", systemImage: "doc.text",
                        description: Text("Add an active scene to preview the screenplay."))
                }
            } else {
                StoryWorkspaceView(workspace: workspace, boardFirst: false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text(workspace.hasChanges ? "Unsaved project changes" : "No pending changes")
                Spacer()
                if !workspace.recoveryStatus.isEmpty { Text(workspace.recoveryStatus) }
            }.font(.caption).foregroundStyle(.secondary).padding(8).background(.regularMaterial)
        }
        .toolbar {
            Picker("View", selection: $workspace.mode) {
                ForEach(Workspace.Mode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
            }.pickerStyle(.menu).frame(width: 140)
            Picker("Paper", selection: $workspace.paper) {
                ForEach(ScreenplayPaper.allCases, id: \.self) { paper in Text(paper.label).tag(paper) }
            }.frame(width: 120)
            Button("Add Scene", systemImage: "plus", action: workspace.addScene)
            Button("Save", systemImage: "square.and.arrow.down", action: workspace.save)
            Button("Export PDF", systemImage: "doc.richtext", action: workspace.exportPDF)
                .disabled(!workspace.hasActiveScenes)
        }
        .onChange(of: workspace.mode) { _, mode in if mode == .pages { workspace.makePreview() } }
        .onChange(of: workspace.paper) { _, _ in if workspace.mode == .pages { workspace.makePreview() } }
        .sheet(isPresented: Binding(get: { workspace.recoveryCandidate != nil }, set: { _ in })) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Recover your last session?").font(.title2)
                Text("A recovery copy of \(workspace.recoveryCandidate?.name ?? "your project") was found. Recover it as a new unsaved copy, or discard it.")
                HStack {
                    Button("Discard Recovery", action: workspace.discardRecovery)
                    Spacer()
                    Button("Recover", action: workspace.recoverSession).keyboardShortcut(.defaultAction)
                }
            }.padding(28).frame(width: 440).interactiveDismissDisabled()
        }
        .alert("Frontstage", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } })) {
                Button("OK") { workspace.errorMessage = nil }
            } message: { Text(workspace.errorMessage ?? "") }
    }
}

struct SceneWritingView: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        if let scene = workspace.selectedScene {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    TextField("Scene title", text: Binding(
                        get: { workspace.selectedScene?.title ?? "" },
                        set: { workspace.updateScene(id: scene.id, title: $0) }))
                        .font(.title3.weight(.semibold)).textFieldStyle(.plain)
                    if scene.isDisabled { Text("OMITTED").font(.caption).foregroundStyle(.orange) }
                }
                TextField("Beat summary — what changes because of this scene?", text: Binding(
                    get: { workspace.selectedScene?.summary ?? "" },
                    set: { workspace.updateScene(id: scene.id, summary: $0) }))
                    .textFieldStyle(.roundedBorder)
                SceneHeadingFields(scene: scene, workspace: workspace)
                ScreenplayFormatBar(controller: workspace.editor)
                ScreenplayEditor(html: Binding(
                    get: { workspace.selectedScene?.html ?? "" },
                    set: { workspace.updateScene(id: scene.id, html: $0) }),
                    controller: workspace.editor, width: workspace.paper.contentWidth,
                    onError: { workspace.errorMessage = $0 })
                    .id(scene.id)
            }.padding(16)
        } else {
            ContentUnavailableView {
                Label("Your next story starts here", systemImage: "doc.richtext")
            } description: {
                Text("Create a beat in the sequencer, or import a Backstage project as a copy.")
            } actions: {
                Button("Add Scene", action: workspace.addScene)
                Button("Open or Import…", action: workspace.open)
            }
        }
    }
}

private struct SceneHeadingFields: View {
    let scene: FrontstageCore.Scene
    @ObservedObject var workspace: Workspace

    private func heading(_ key: WritableKeyPath<SceneHeading, String>) -> Binding<String> {
        Binding(get: { (workspace.selectedScene?.heading ?? scene.heading)[keyPath: key] }, set: { value in
            var current = workspace.selectedScene?.heading ?? scene.heading
            current[keyPath: key] = value
            workspace.updateScene(id: scene.id, heading: current)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCENE HEADING").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                TextField("INT. / EXT.", text: heading(\.prefix)).frame(width: 90)
                    .accessibilityLabel("Interior or exterior")
                TextField("Location", text: heading(\.location)).accessibilityLabel("Scene location")
                TextField("DAY / NIGHT", text: heading(\.time)).frame(width: 110).accessibilityLabel("Time of day")
                TextField("Auto #", text: Binding(get: { workspace.selectedScene?.sceneNumber ?? "" },
                    set: { workspace.updateScene(id: scene.id, sceneNumber: $0) }))
                    .frame(width: 65).accessibilityLabel("Scene number override")
            }.textFieldStyle(.roundedBorder)
        }
    }
}

private struct ScreenplayFormatBar: View {
    @ObservedObject var controller: ScreenplayEditorController
    var body: some View {
        HStack {
            Picker("Element", selection: Binding(get: { controller.activeElement }, set: { controller.format($0) })) {
                ForEach(ScreenplayElement.editable, id: \.self) { element in Text(element.label).tag(element) }
            }.frame(width: 210)
            Spacer()
            Text("Tab changes element · Return continues dialogue · ⌥1–7 formats")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
#else
import Foundation
@main
struct FrontstageUnsupportedPlatform {
    static func main() {
        FileHandle.standardError.write(Data("Frontstage's native UI requires macOS 14 or later. Run swift test to validate the portable core.\n".utf8))
    }
}
#endif
