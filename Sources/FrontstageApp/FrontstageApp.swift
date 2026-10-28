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
        Window("DOT", id: "workspace") {
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 850, minHeight: 560)
                .onAppear { delegate.workspace = workspace; workspace.checkRecovery() }
        }
        Settings { DOTPreferences(workspace: workspace) }
        .commands {
            CommandGroup(after: .newItem) {
                Menu("Open Recent") {
                    ForEach(workspace.recentProjectPaths, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) { workspace.openProjectURL(URL(fileURLWithPath: path)) }
                    }
                }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo", action: workspace.undoProject).keyboardShortcut("z").disabled(!workspace.history.canUndo)
                Button("Redo", action: workspace.redoProject).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!workspace.history.canRedo)
            }
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
                Button("Export Final Draft FDX…", action: workspace.exportFDX).disabled(!workspace.hasActiveScenes)
                Button("Export Fountain…", action: workspace.exportFountain).disabled(!workspace.hasActiveScenes)
                Button("Export Schedule XLSX…", action: workspace.exportScheduleXLSX)
                Button("Print Screenplay…", action: workspace.printScreenplay).keyboardShortcut("p")
                    .disabled(!workspace.hasActiveScenes)
            }
            CommandMenu("Screenplay") {
                ForEach(Array(ScreenplayElement.editable.enumerated()), id: \.element.rawValue) { index, element in
                    Button("\(index + 1) \(element.label)") { workspace.focusedScreenplayController?.format(element) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
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
    private let branding = DOTBrandController()
    private var pendingProject: URL?
    weak var workspace: Workspace? {
        didSet { if let url = pendingProject, let workspace { pendingProject = nil; workspace.openProjectURL(url) } }
    }
    func applicationDidFinishLaunching(_ notification: Notification) { branding.start() }
    func applicationDidResignActive(_ notification: Notification) {
        guard workspace?.focusedScreenplayController?.textView?.hasMarkedText() != true else { return }
        TamilInputManager.restoreStandardInput()
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let workspace { workspace.openProjectURL(url) } else { pendingProject = url }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace?.confirmDiscardOrSave() == false ? .terminateCancel : .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
final class Workspace: ObservableObject {
    var focusedScreenplayController: ScreenplayEditorController? {
        screenplayController(in: NSApp.keyWindow)
    }
    func screenplayController(in focusedWindow: NSWindow?) -> ScreenplayEditorController? {
        if let focused = popup.focusedController(in: focusedWindow) { return focused }
        if let focused = scriptEditors.values.first(where: { controller in
            guard let text = controller.textView, let window = text.window else { return false }
            return focusedWindow === window && window.firstResponder === text
        }) { return focused }
        guard let text = editor.textView, let window = text.window,
              focusedWindow === window, window.firstResponder === text else { return nil }
        return editor
    }
    enum Mode: String, CaseIterable {
        case board = "Whiteboard", edit = "Write", pages = "Pages", revisions = "Revisions", people = "People", breakdown = "Breakdown", production = "Production", writingTools = "Writing Tools", studio = "Research & Studio", shared = "Shared Projects"
    }
    @Published private(set) var project = Project(oneBeatPerScene: true)
    var writingSelectedQuote: (sceneID: Decimal, text: String)?
    @Published var selectedSceneID: Decimal? {
        didSet { if oldValue != selectedSceneID { editor.textView?.undoManager?.removeAllActions() } }
    }
    @Published private(set) var hasChanges = false
    @Published var errorMessage: String?
    @Published var selectedBoardBeatID: String?
    @Published var pendingBoardCauseID: String?
    @Published var showBoardScript = true
    @Published var writeCardsVisible = UserDefaults.standard.object(forKey: "write-left-visible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(writeCardsVisible, forKey: "write-left-visible") }
    }
    @Published var writeInspectorVisible = UserDefaults.standard.object(forKey: "write-right-visible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(writeInspectorVisible, forKey: "write-right-visible") }
    }
    @Published var writeCardsToggle = 0
    @Published var writeInspectorToggle = 0
    @Published var reader = ScriptReaderSettings()
    @Published var whiteboardRipple = true
    @Published var selectedResearchID: String?
    @Published var mode = Mode.board {
        didSet { if oldValue != mode { editor.textView?.undoManager?.removeAllActions() } }
    }
    @Published var paper = ScreenplayPaper.a4
    @Published private(set) var preview: PDFDocument?
    @Published private(set) var history = ProjectHistory()
    @Published private(set) var recoveryCandidate: Project?
    @Published private(set) var recoveryStatus = ""
    @Published private(set) var changeID = 0
    private(set) var documentSessionID = UUID()
    @Published private(set) var whiteboardCache: Whiteboard?
    let editor = ScreenplayEditorController()
    private var scriptEditors: [String: ScreenplayEditorController] = [:]
    func scriptController(_ id: String) -> ScreenplayEditorController {
        if let controller = scriptEditors[id] { return controller }
        let controller = ScreenplayEditorController()
        controller.historyBoundary = { [weak self] in self?.endScriptTypingGroup() }
        controller.projectUndo = { [weak self] in self?.undoProject() }; controller.projectRedo = { [weak self] in self?.redoProject() }
        scriptEditors[id] = controller; return controller
    }
    func endScriptTypingGroup() { history.endTypingGroup() }
    func duplicateBeat(_ id: String) {
        var created: String?
        edit("Duplicate Beat") { created = try $0.duplicateBoardBeat(id) }
        if let created { selectBoardBeat(created) }
    }
    @Published var timelineDetached = false
    let timelineWindow = TimelineWindowPresenter()
    let popup = BeatPopupPresenter()
    let sharedProjects = SharedProjectClient()
    private var saveURL: URL?
    private var savedProject: Project? = Project(oneBeatPerScene: true)
    private let recoveryStore: RecoveryStore?
    private var recoveryTask: Task<Void, Never>?
    private var checkedRecovery = false
    private var recoveryBlocked = false

    init(recoveryStore: RecoveryStore? = nil) {
        self.recoveryStore = recoveryStore
        editor.historyBoundary = { [weak self] in self?.endScriptTypingGroup() }
        editor.projectUndo = { [weak self] in self?.undoProject() }; editor.projectRedo = { [weak self] in self?.redoProject() }
    }

    func checkRecovery() {
        guard !checkedRecovery else { return }
        checkedRecovery = true
        do {
            recoveryCandidate = try recoveryStore?.load()
            if recoveryCandidate == nil, saveURL == nil, !hasChanges,
               UserDefaults.standard.bool(forKey: "frontstage_restore_last_project"),
               let path = UserDefaults.standard.string(forKey: "frontstage_last_project_path") {
                openProjectURL(URL(fileURLWithPath: path))
            }
        }
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

    func acceptConvertedCopy(_ copy: Project) throws {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Frontstage/Conversion Originals", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try project.encoded().write(to: root.appendingPathComponent(UUID().uuidString + ".frontstage"), options: .atomic)
        loadCopy(copy); mode = .edit
    }

    func loadCopy(_ imported: Project) {
        documentSessionID = UUID()
        reader.filters = .init(); reader.filter = ""
        sharedProjects.detach()
        popup.close()
        scriptEditors.removeAll()
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
        guard sharedProjects.linked?.access != "reader" else { errorMessage = "This shared project is read-only."; return }
        let previous = project
        do {
            try operation(&project)
            try project.validateSceneModel()
            guard project != previous else { return }
            history.record(previous, label: label, key: key)
            changed()
        } catch { project = previous; errorMessage = error.localizedDescription }
    }

    func undoProject() {
        guard sharedProjects.linked?.access != "reader" else { return }
        guard let previous = history.undo(current: project) else { return }
        project = previous
        reconcileSelection()
        changed()
    }

    func redoProject() {
        guard sharedProjects.linked?.access != "reader" else { return }
        guard let next = history.redo(current: project) else { return }
        project = next
        reconcileSelection()
        changed()
    }

    private func reconcileSelection() {
        if !project.scenes.contains(where: { $0.id == selectedSceneID }) { selectedSceneID = project.scenes.first?.id }
        editor.textView?.undoManager?.removeAllActions()
        for id in popup.panels.keys { popup.controller(for: id)?.textView?.undoManager?.removeAllActions() }
        for controller in scriptEditors.values { controller.textView?.undoManager?.removeAllActions() }
        if !whiteboard.beats.contains(where: { $0.id == selectedBoardBeatID }) { selectedBoardBeatID = whiteboard.orderedBeats.first?.id }
        if let beat = whiteboard.beats.first(where: { $0.id == selectedBoardBeatID }), project.scenes.contains(where: { $0.id == beat.sceneID }) { selectedSceneID = beat.sceneID }
        if project.scenes.isEmpty { selectedSceneID = nil; selectedBoardBeatID = nil }
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
        reader.filters = .init(); reader.filter = ""
        sharedProjects.detach()
        popup.close(); scriptEditors.removeAll(); selectedBoardBeatID = nil
        recoveryTask?.cancel()
        if !recoveryBlocked {
            do { try recoveryStore?.clear() }
            catch { errorMessage = error.localizedDescription; return }
        }
        editor.textView?.undoManager?.removeAllActions()
        project = Project(oneBeatPerScene: true)
        if let data = UserDefaults.standard.data(forKey: "default_script_layout"), let layout = try? JSONDecoder().decode(ScriptLayoutSettings.self, from: data) { try? project.setScriptLayout(layout) }
        paper = UserDefaults.standard.string(forKey: "default_paper_size") == "US Letter" ? .letter : .a4
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
        if let board = whiteboardCache { popup.refreshTitles(board) }
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

    @Published private(set) var recentProjectPaths = UserDefaults.standard.stringArray(forKey: "frontstage_recent_projects") ?? []
    private func recordRecent(_ url: URL) {
        let path = url.standardizedFileURL.path
        recentProjectPaths = [path] + recentProjectPaths.filter { $0 != path }.prefix(19)
        UserDefaults.standard.set(recentProjectPaths, forKey: "frontstage_recent_projects")
        UserDefaults.standard.set(path, forKey: "frontstage_last_project_path")
    }
    func openProjectURL(_ url: URL) {
        guard confirmDiscardOrSave() else { return }
        do {
            let loaded = try Project.load(from: url)
            loadCopy(loaded)
            // Native files support ordinary Save. Legacy imports always remain copy-only.
            let source = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
            if ["dot", "frontstage"].contains(url.pathExtension.lowercased()), source.object?["format"]?.string == "frontstage" {
                saveURL = url; savedProject = loaded; recordRecent(url)
            }
        } catch { errorMessage = "The project could not be opened. Its recent-project entry is retained so you can locate or restore the file. \(error.localizedDescription)" }
    }
    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json,
            UTType(filenameExtension: "backstage") ?? .data,
            UTType(filenameExtension: "frontstage") ?? .data, UTType(filenameExtension: "dot") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Legacy projects are imported as copies. Save them as new DOT .dot files."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProjectURL(url)
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
        panel.allowedContentTypes = [UTType(exportedAs: "design.ratioprofile.frontstage.project", conformingTo: .json)]
        panel.nameFieldStringValue = "\(project.name.replacingOccurrences(of: "/", with: "-" )).dot"
        panel.message = "Save a native DOT copy. Your imported source stays unchanged."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try project.save(to: url)
            saveURL = url
            recordRecent(url)
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
    @State private var columns = NavigationSplitViewVisibility.all

    private var workspaceLayout: some View {
        NavigationSplitView(columnVisibility: $columns) {
            ScriptSidePaper(workspace: workspace)
                .navigationSplitViewColumnWidth(min: 320, ideal: 460, max: 700)
        } detail: {
            Group {
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
                ScriptWritingWorkspace(workspace: workspace)
            }
            }.background(Color(boardHex: WorkspaceDesign.panelColor))
        }
    }
    var body: some View {
        workspaceLayout
        .onAppear { if workspace.mode == .edit { columns = .detailOnly } }
        .onChange(of: workspace.mode) { old, mode in if mode == .edit { columns = .detailOnly } else if old == .edit { columns = workspace.showBoardScript ? .all : .detailOnly } }
        .onChange(of: workspace.showBoardScript) { visible in columns = workspace.mode != .edit && visible ? .all : .detailOnly }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text(workspace.hasChanges ? "Unsaved project changes" : "No pending changes")
                Spacer()
                if !workspace.recoveryStatus.isEmpty { Text(workspace.recoveryStatus) }
            }.font(.caption).foregroundStyle(.secondary).padding(8).background(.regularMaterial)
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar { workspaceToolbar }
        .preferredColorScheme(.dark)
        .tint(DOTTheme.accent).accentColor(DOTTheme.accent)
        .font(.system(size: 12))
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
        .alert("DOT", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } })) {
                Button("OK") { workspace.errorMessage = nil }
            } message: { Text(workspace.errorMessage ?? "") }
    }
    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) { DOTWordmark() }
        ToolbarItem(placement: .navigation) {
            Button("Toggle navigation", systemImage: "sidebar.left") {
                if workspace.mode == .edit { workspace.writeCardsToggle += 1 }
                else { workspace.showBoardScript.toggle() }
            }
        }
        ToolbarItemGroup {
            Button("Undo", systemImage: "arrow.uturn.backward", action: workspace.undoProject).disabled(!workspace.history.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward", action: workspace.redoProject).disabled(!workspace.history.canRedo)
            Picker("View", selection: $workspace.mode) {
                ForEach(Workspace.Mode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
            }.pickerStyle(.menu).frame(width: 140)
            Picker("Paper", selection: $workspace.paper) {
                ForEach(ScreenplayPaper.allCases, id: \.self) { paper in Text(paper.label).tag(paper) }
            }.frame(width: 120)
            Button("Add Scene", systemImage: "plus", action: workspace.addScene)
            Button("Save", systemImage: "square.and.arrow.down", action: workspace.save)
            Button("Export PDF", systemImage: "doc.richtext", action: workspace.exportPDF).disabled(!workspace.hasActiveScenes)
        }
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

struct ScriptSuggestionField: NSViewRepresentable {
    let label: String
    @Binding var text: String
    let options: [String]
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text.uppercased())
        field.placeholderString = label; field.setAccessibilityLabel(label)
        field.isBezeled = true; field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self; field.isEnabled = enabled
        if field.currentEditor() == nil { field.stringValue = text.uppercased() }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ScriptSuggestionField
        var completing = false
        init(_ parent: ScriptSuggestionField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
            if let editor = field.currentEditor() as? NSTextView, editor.string != editor.string.uppercased() {
                let caret = editor.selectedRange();let prefix = (editor.string as NSString).substring(to: min(caret.location, (editor.string as NSString).length)).uppercased()
                editor.string = editor.string.uppercased();editor.setSelectedRange(NSRange(location: prefix.utf16.count, length: 0))
            }
            parent.text = field.stringValue.uppercased()
            guard !completing, let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText(), !field.stringValue.isEmpty else { return }
            completing = true; editor.complete(nil); completing = false
        }
        func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange range: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
            let source = textView.string as NSString
            let prefix = source.substring(to: NSMaxRange(range))
            let before = source.substring(to: range.location)
            index.pointee = -1
            return Array(Set(parent.options.map { $0.uppercased() })).sorted().filter { $0.lowercased().hasPrefix(prefix.lowercased()) && $0.lowercased() != prefix.lowercased() }.map { String($0.dropFirst(before.count)) }
        }
    }
}

struct SceneHeadingFields: View {
    let scene: FrontstageCore.Scene
    @ObservedObject var workspace: Workspace
    var compact = false
    private var current: FrontstageCore.Scene { workspace.project.scenes.first { $0.id == scene.id } ?? scene }
    private func heading(_ key: WritableKeyPath<SceneHeading, String>) -> Binding<String> {
        Binding(get: { current.heading[keyPath: key] }, set: { value in
            var updated = current.heading; updated[keyPath: key] = value.uppercased()
            workspace.updateScene(id: scene.id, heading: updated)
        })
    }
    @ViewBuilder private var fields: some View {
        ScriptSuggestionField(label: "INT. / EXT.", text: heading(\.prefix), options: ["INT.", "EXT.", "INT./EXT.", "EXT./INT."])
        ScriptSuggestionField(label: "Location", text: heading(\.location), options: Array(Set(workspace.project.scenes.map { $0.heading.location }.filter { !$0.isEmpty })).sorted())
        ScriptSuggestionField(label: "DAY / NIGHT", text: heading(\.time), options: ["DAY", "NIGHT", "DAWN", "DUSK", "MORNING", "AFTERNOON", "EVENING", "LATER", "CONTINUOUS", "SAME TIME"])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SLUGLINE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if compact { VStack { fields } } else { HStack { fields } }
            TextField("Auto #", text: Binding(get: { current.sceneNumber }, set: { workspace.updateScene(id: scene.id, sceneNumber: $0) }))
                .frame(width: 65).accessibilityLabel("Scene number override")
        }.disabled(current.isTextLocked)
    }
}

extension Workspace {
    static let screenplayFixedCompletions: [ScreenplayElement: [String]] = [
        .transition: ["CUT TO:", "DISSOLVE TO:", "FADE IN:", "FADE OUT.", "FADE TO BLACK.", "SMASH CUT TO:", "MATCH CUT TO:"],
        .parenthetical: CharacterCue.deliveryNotes, .shot: ["CLOSE ON", "ANGLE ON", "INSERT", "POV"]]
    var screenplayCompletions: [ScreenplayElement: [String]] {
        var choices = Self.screenplayFixedCompletions
        choices[.character] = Array(Set((project.characters.map(\.name) + whiteboard.beats.flatMap(\.characters) + whiteboard.beats.flatMap { ScriptCueNames.characters(in: $0.html) } + project.scenes.flatMap { ScriptCueNames.characters(in: $0.html) }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })).filter { !$0.isEmpty }.sorted()
        choices[.sceneHeading] = project.scenes.map { $0.heading.inlineText }
        return choices
    }
}

struct ScreenplaySuggestions: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: ScreenplayEditorController
    private var names: [String] {
        Array(Set(workspace.project.characters.map(\.name) + workspace.whiteboard.beats.flatMap(\.characters))).filter { !$0.isEmpty }.sorted()
    }
    var body: some View {
        Text("Type for suggestions · Tab changes screenplay element")
            .font(.caption).foregroundStyle(.secondary)
    }
}

private struct ScreenplayFormatBar: View {
    @ObservedObject var controller: ScreenplayEditorController
    var body: some View {
        HStack {
            Picker("Element", selection: Binding(get: { controller.activeElement }, set: { controller.format($0) })) {
                ForEach(Array(ScreenplayElement.editable.enumerated()), id: \.element) { index, element in Text("\(index + 1) \(element.label)").tag(element) }
            }.frame(width: 210)
            Spacer()
            Text("Tab changes element · Cmd+1–8 formats · Cmd+Enter Action")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
#else
import Foundation
@main
struct FrontstageUnsupportedPlatform {
    static func main() {
        FileHandle.standardError.write(Data("DOT's native UI requires macOS 14 or later. Run swift test to validate the portable core.\n".utf8))
    }
}
#endif
