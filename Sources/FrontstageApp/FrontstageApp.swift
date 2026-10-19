#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FrontstageCore

@main
struct FrontstageApp: App {
    @StateObject private var workspace = Workspace()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some SwiftUI.Scene {
        Window("Frontstage", id: "workspace") {
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 850, minHeight: 560)
                .onAppear { delegate.workspace = workspace }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project", action: workspace.newProject).keyboardShortcut("n")
                Button("Open or Import…", action: workspace.open).keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save", action: workspace.save).keyboardShortcut("s")
                Button("Save As…") { workspace.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
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
    @Published private(set) var project = Project()
    @Published var selectedSceneID: Decimal?
    @Published private(set) var hasChanges = false
    @Published var errorMessage: String?
    private var saveURL: URL?

    var selectedScene: FrontstageCore.Scene? {
        project.scenes.first { $0.id == selectedSceneID }
    }

    func newProject() {
        guard confirmDiscardOrSave() else { return }
        project = Project()
        saveURL = nil
        hasChanges = false
        selectedSceneID = nil
    }

    func addScene() {
        selectedSceneID = project.addScene()
        hasChanges = true
    }

    func updateScene(id: Decimal, title: String? = nil, html: String? = nil, summary: String? = nil) {
        do {
            try project.updateScene(id: id, title: title, html: html, summary: summary)
            hasChanges = true
        } catch { errorMessage = error.localizedDescription }
    }

    func rename(_ name: String) {
        project.name = name
        hasChanges = true
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
            project = imported
            selectedSceneID = imported.scenes.first?.id
            // Every open starts a copy. No source project is ever a default save destination.
            saveURL = nil
            hasChanges = true
        } catch { errorMessage = error.localizedDescription }
    }

    func save() { _ = saveCurrent() }

    @discardableResult
    private func saveCurrent() -> Bool {
        guard let saveURL else { return saveAs() }
        do {
            try project.save(to: saveURL)
            hasChanges = false
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
            hasChanges = false
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
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        NavigationSplitView {
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
            if let scene = workspace.selectedScene {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Scene title", text: Binding(
                        get: { workspace.selectedScene?.title ?? "" },
                        set: { workspace.updateScene(id: scene.id, title: $0) }))
                        .font(.title.weight(.semibold)).textFieldStyle(.plain)
                    TextField("Scene summary", text: Binding(
                        get: { workspace.selectedScene?.summary ?? "" },
                        set: { workspace.updateScene(id: scene.id, summary: $0) }))
                        .textFieldStyle(.roundedBorder)
                    Divider()
                    RichTextEditor(html: Binding(
                        get: { workspace.selectedScene?.html ?? "" },
                        set: { workspace.updateScene(id: scene.id, html: $0) }))
                        .id(scene.id)
                    Text("Local project · \(workspace.hasChanges ? "Unsaved changes" : "Saved")")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(28)
            } else {
                ContentUnavailableView {
                    Label("Your next story starts here", systemImage: "doc.richtext")
                } description: {
                    Text("Create a scene, or import an existing Backstage project as a copy.")
                } actions: {
                    Button("Add Scene", action: workspace.addScene)
                    Button("Open or Import…", action: workspace.open)
                }
            }
        }
        .toolbar {
            Button("Add Scene", systemImage: "plus", action: workspace.addScene)
            Button("Save", systemImage: "square.and.arrow.down", action: workspace.save)
        }
        .alert("Frontstage", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } })) {
                Button("OK") { workspace.errorMessage = nil }
            } message: { Text(workspace.errorMessage ?? "") }
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
