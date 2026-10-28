#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

@MainActor
struct DOTPreferences: View {
    @ObservedObject var workspace: Workspace
    @State private var element: ScreenplayElement = .action
    @State private var deviceDefaults = false
    @State private var defaults = ScriptLayoutSettings()
    @State private var migration: PreferenceImportReview?
    @State private var replacements = Set<String>()
    @AppStorage("frontstage_restore_last_project") private var restoreLast = false
    @AppStorage("default_paper_size") private var defaultPaper = "A4"
    private var layout: ScriptLayoutSettings { deviceDefaults ? defaults : workspace.project.scriptLayout }
    private var override: ElementTypography? { layout.elements[element.rawValue] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("DOT Preferences").font(.title2)
                Picker("Apply typography to", selection: $deviceDefaults) {
                    Text("Current project").tag(false); Text("Defaults for new projects").tag(true)
                }.pickerStyle(.segmented)
                Text("Device defaults apply only to new projects. Imported projects retain their own typography.").font(.caption).foregroundStyle(.secondary)
                GroupBox("Base typography") {
                    VStack(alignment: .leading) {
                        fontField("Font name", value: layout.fontName) { name in update { $0.fontName = name } }
                        HStack {
                            Text("Size"); TextField("Size", value: Binding(get: { layout.fontSize }, set: { size in update { $0.fontSize = size; $0.lineHeight = max(size, $0.lineHeight) } }), format: .number)
                            Text("Line height"); TextField("Height", value: Binding(get: { layout.lineHeight }, set: { value in update { $0.lineHeight = value } }), format: .number)
                            Text("Spacing"); TextField("Spacing", value: Binding(get: { layout.paragraphSpacing }, set: { value in update { $0.paragraphSpacing = value } }), format: .number)
                        }
                    }.padding(8)
                }
                GroupBox("Element typography") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Element", selection: $element) { ForEach(ScreenplayElement.editable, id: \.self) { Text($0.label).tag($0) } }
                        Toggle("Customize this element", isOn: Binding(get: { override != nil }, set: { enabled in update { value in
                            value.elements[element.rawValue] = enabled ? ElementTypography(isBold: value.isBold(for: element), isUppercase: value.isUppercase(for: element)) : nil
                        } }))
                        if override != nil {
                            fontField("Font (blank inherits)", value: override?.fontName ?? "") { name in update { $0.elements[element.rawValue]?.fontName = name } }
                            TextField("Size", value: Binding(get: { override?.fontSize ?? layout.fontSize }, set: { size in update { $0.elements[element.rawValue]?.fontSize = size } }), format: .number)
                            HStack { flag("Bold", \.isBold); flag("Italic", \.isItalic); flag("Underline", \.isUnderline); flag("Uppercase", \.isUppercase); flag("Tamil", \.isTamil) }
                        }
                        Text(layout.isUppercase(for: element) ? "Sample text · தமிழ்".uppercased() : "Sample text · தமிழ்")
                            .font(Font(NSFont(name: layout.effectiveFontName(for: element), size: layout.effectiveFontSize(for: element)) ?? .monospacedSystemFont(ofSize: layout.effectiveFontSize(for: element), weight: .regular)))
                            .fontWeight(layout.isBold(for: element) ? .bold : .regular)
                            .italic(layout.isItalic(for: element))
                            .underline(layout.isUnderline(for: element))
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(8)
                }
                GroupBox("Device workflow") {
                    VStack(alignment: .leading) {
                        Toggle("Restore the last native project at startup", isOn: $restoreLast)
                        Picker("Default paper for new projects", selection: $defaultPaper) { Text("A4").tag("A4"); Text("US Letter").tag("US Letter") }
                        Text("Recovery copies take priority over session restoration.").font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("Antigravity settings import") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let migration {
                            Text("Recognized preferences: \(migration.incoming.count). Conflicts keep current settings unless selected below.")
                            ForEach(migration.conflicts.sorted(), id: \.self) { key in
                                Toggle("Use Antigravity: \(key)", isOn: Binding(get: { replacements.contains(key) }, set: { if $0 { replacements.insert(key) } else { replacements.remove(key) } }))
                            }
                            Button("Back Up and Import Reviewed Settings") { importSettings(migration) }
                        } else { Button("Review Antigravity Settings…", action: reviewSettings) }
                        Text("Imports device preferences only. Projects, credentials and system text-rendering overrides are excluded.").font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
            }.padding(20)
        }.frame(width: 700, height: 640).textFieldStyle(.roundedBorder)
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: "default_script_layout"), let saved = try? JSONDecoder().decode(ScriptLayoutSettings.self, from: data) { defaults = saved }
        }
    }
    private func fontField(_ label: String, value: String, changed: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading) {
            TextField(label, text: Binding(get: { value }, set: changed))
            if !value.isEmpty && NSFont(name: value, size: 12) == nil {
                Text("\(value) is unavailable; using system monospace. The stored font name is retained.").font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private func flag(_ title: String, _ key: WritableKeyPath<ElementTypography, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { override?[keyPath: key] ?? false }, set: { enabled in update { $0.elements[element.rawValue]?[keyPath: key] = enabled } }))
    }
    private func update(_ action: (inout ScriptLayoutSettings) -> Void) {
        var value = layout; action(&value)
        do {
            try value.validate()
            if deviceDefaults { defaults = value; UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: "default_script_layout") }
            else { workspace.edit("Script Typography") { try $0.setScriptLayout(value) } }
        } catch { workspace.errorMessage = error.localizedDescription }
    }
    private func settings(_ domain: String) -> [String: JSONValue] {
        let raw = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        return raw.compactMapValues { value in
            if let data = value as? Data, let layout = try? JSONDecoder().decode(JSONValue.self, from: data) { return layout }
            guard JSONSerialization.isValidJSONObject(["value": value]), let data = try? JSONSerialization.data(withJSONObject: ["value": value]) else { return nil }
            return (try? JSONDecoder().decode(JSONValue.self, from: data))?.object?["value"]
        }
    }
    private func reviewSettings() {
        migration = PreferenceImportReview(current: settings("design.ratioprofile.frontstage"), incoming: settings("design.ratioprofile.dot")); replacements = []
    }
    private func importSettings(_ review: PreferenceImportReview) {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Frontstage/Settings Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let backup = JSONValue.object(["current": .object(review.current), "antigravity": .object(review.incoming)])
            try JSONEncoder().encode(backup).write(to: root.appendingPathComponent("settings-\(UUID().uuidString).json"), options: .atomic)
            for (key, value) in review.accepted(replaceConflicts: replacements) {
                let data = try JSONEncoder().encode(value)
                if key == "default_script_layout" {
                    let layoutData = value.string?.data(using: .utf8) ?? data
                    let layout = try JSONDecoder().decode(ScriptLayoutSettings.self, from: layoutData)
                    try layout.validate()
                    UserDefaults.standard.set(try JSONEncoder().encode(layout), forKey: key); defaults = layout
                }
                else { UserDefaults.standard.set(try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed), forKey: key) }
            }
            UserDefaults.standard.set(true, forKey: "dot_antigravity_preferences_imported")
            workspace.reloadDevicePreferences()
            migration = nil
        } catch { workspace.errorMessage = error.localizedDescription }
    }
}
private extension View {
    @ViewBuilder func italic(_ enabled: Bool) -> some View { if enabled { self.italic() } else { self } }
}
#endif
