#if os(macOS)
import AppKit
import SwiftUI
import FrontstageCore

@MainActor
struct DOTPreferences: View {
    @ObservedObject var workspace: Workspace
    @AppStorage("dot_preferences_tab") private var tab = 0
    @State private var fontSearch = ""
    @AppStorage("dot_tamil_input_source") private var tamilSource = ""
    @AppStorage("dot_english_input_source") private var englishSource = ""
    @AppStorage("dot_export_highlights") private var exportHighlights = false
    @State private var element: ScreenplayElement = .action
    @State private var deviceDefaults = false
    @State private var defaults = ScriptLayoutSettings()
    @State private var migration: PreferenceImportReview?
    @State private var replacements = Set<String>()
    @AppStorage("dot_switch_tamil_input") private var switchTamilInput = false
    @AppStorage("frontstage_restore_last_project") private var restoreLast = false
    @AppStorage("default_paper_size") private var defaultPaper = "A4"
    private var layout: ScriptLayoutSettings { deviceDefaults ? defaults : workspace.project.scriptLayout }
    private var override: ElementTypography? { layout.elements[element.rawValue] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DOT Preferences").font(.title2)
            Picker("Preferences", selection: $tab) { Text("Script Typography").tag(0); Text("General Settings").tag(1) }.pickerStyle(.segmented)
            ScrollView { if tab == 0 { typographyContent } else { generalContent } }
        }.padding(20).frame(width: 820, height: 700).textFieldStyle(.roundedBorder)
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: "default_script_layout"), let saved = try? JSONDecoder().decode(ScriptLayoutSettings.self, from: data) { defaults = saved }
        }
    }
    private var typographyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Apply typography to", selection: $deviceDefaults) { Text("Current project").tag(false); Text("Defaults for new projects").tag(true) }.pickerStyle(.segmented)
            Text("Device defaults apply only to new projects. Imported projects retain their typography.").font(.caption).foregroundStyle(.secondary)
            GroupBox("Global Script Typography") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Reset to Industry Standard") { update { $0 = ScriptLayoutSettings() } }
                    TextField("Filter installed fonts…", text: $fontSearch)
                    fontField("Base Font", value: layout.fontName) { name in update { $0.fontName = name } }
                    HStack {
                        Text("Size"); TextField("Base Size", value: Binding(get: { layout.fontSize }, set: { size in update { $0.fontSize = size; $0.lineHeight = max(size, $0.lineHeight) } }), format: .number).frame(width: 60)
                        Stepper("Size", value: Binding(get: { layout.fontSize }, set: { size in update { $0.fontSize = size; $0.lineHeight = max(size, $0.lineHeight) } }), in: 8...36).labelsHidden()
                        Text("Line height"); TextField("Line Height", value: Binding(get: { layout.lineHeight }, set: { value in update { $0.lineHeight = value } }), format: .number).frame(width: 60)
                        Text("Spacing"); TextField("Paragraph Spacing", value: Binding(get: { layout.paragraphSpacing }, set: { value in update { $0.paragraphSpacing = value } }), format: .number).frame(width: 60)
                    }
                }.padding(8)
            }
            GroupBox("Element-Specific Formatting") {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal) {
                        HStack { ForEach(Array(ScreenplayElement.editable.enumerated()), id: \.element) { index, item in
                            Button("\(index + 1) \(item.label)\(layout.isTamil(for: item) ? " · த" : "")") { element = item }.tint(element == item ? .accentColor : .secondary)
                        } }
                    }
                    Toggle("Custom Font", isOn: Binding(get: { override?.fontName?.isEmpty == false }, set: { enabled in updateElement { $0.fontName = enabled ? layout.fontName : nil } }))
                    if override?.fontName?.isEmpty == false { fontField("Element Font", value: override?.fontName ?? layout.fontName) { name in updateElement { $0.fontName = name } } }
                    else { Text("Inheriting base font: \(layout.fontName)").font(.caption).foregroundStyle(.secondary) }
                    Toggle("Custom Size", isOn: Binding(get: { override?.fontSize != nil }, set: { enabled in updateElement { $0.fontSize = enabled ? layout.fontSize : nil } }))
                    if override?.fontSize != nil {
                        HStack { TextField("Element Size", value: Binding(get: { override?.fontSize ?? layout.fontSize }, set: { size in updateElement { $0.fontSize = size } }), format: .number).frame(width: 80); Stepper("Size", value: Binding(get: { override?.fontSize ?? layout.fontSize }, set: { size in updateElement { $0.fontSize = size } }), in: 8...36).labelsHidden() }
                    } else { Text("Inheriting base size: \(Int(layout.fontSize)) pt").font(.caption).foregroundStyle(.secondary) }
                    HStack { flag("Bold", \.isBold); flag("Italic", \.isItalic); flag("Underline", \.isUnderline); flag("Uppercase", \.isUppercase) }
                    Picker("Element Language", selection: Binding(get: { layout.isTamil(for: element) }, set: { tamil in updateElement { value in value.isTamil = tamil; if tamil && (value.fontName?.isEmpty != false) { value.fontName = "Tamil Sangam MN" } } })) { Text("English").tag(false); Text("Tamil · தமிழ்").tag(true) }.pickerStyle(.segmented)
                    Text("Fonts and spacing follow the element. Optional keyboard switching is configured under General Settings.").font(.caption).foregroundStyle(.secondary)
                    Button("Clear Element Overrides") { update { $0.elements.removeValue(forKey: element.rawValue) } }.disabled(override == nil)
                }.padding(8)
            }
            GroupBox("Live Screenplay Preview") {
                VStack(alignment: .leading, spacing: layout.paragraphSpacing) {
                    previewLine(.sceneHeading, english: "INT. ROOM - DAY", tamil: "INT. வீடு - பகல்")
                    previewLine(.action, english: "She opens the door.", tamil: "அவள் கதவைத் திறக்கிறாள்.")
                    previewLine(.character, english: "ABI", tamil: "அபி")
                    previewLine(.parenthetical, english: "(quietly)", tamil: "(மெதுவாக)")
                    previewLine(.dialogue, english: "We can begin again.", tamil: "நாம் மீண்டும் தொடங்கலாம்.")
                    previewLine(.transition, english: "CUT TO:", tamil: "CUT TO:")
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.black).background(.white)
            }
        }.padding(.vertical, 8)
    }
    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Startup & Recent Projects") {
                VStack(alignment: .leading) { Toggle("Restore the last native project at startup", isOn: $restoreLast); Text("Recovery copies take priority over session restoration.").font(.caption).foregroundStyle(.secondary) }.padding(8)
            }
            GroupBox("Page & Export") {
                VStack(alignment: .leading) {
                    Picker("Default paper for new projects", selection: $defaultPaper) { Text("A4").tag("A4"); Text("US Letter").tag("US Letter") }
                    Toggle("Include Highlights in PDF and DOCX", isOn: $exportHighlights)
                    Text("Production breakdown marks never enter exports. FDX and Fountain do not include highlights.").font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("Element Keyboard Switching") {
                VStack(alignment: .leading) {
                    Toggle("Switch keyboard source for Tamil / English elements", isOn: $switchTamilInput)
                    Picker("Tamil source", selection: $tamilSource) { Text("Automatic Tamil source").tag(""); ForEach(TamilInputManager.availableSources(tamil: true)) { source in Text(source.name).tag(source.id) } }
                    Picker("English source", selection: $englishSource) { Text("Previous input source").tag(""); ForEach(TamilInputManager.availableSources(tamil: false)) { source in Text(source.name).tag(source.id) } }
                    Text("Only enabled macOS sources are listed. Switching pauses during composition and restores the source DOT changed when editing ends.").font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("Project File Format") { Text("DOT saves native .dot files. Existing .frontstage projects remain supported; legacy imports stay copy-only.").font(.caption).padding(8) }
            GroupBox("Beat Popup Editor") { Text("Popup text scales to at least 15pt while preserving project typography ratios. Saved typography is unchanged.").font(.caption).padding(8) }
                GroupBox("Antigravity settings import") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let migration {
                            Text("Recognized preferences: \(migration.incoming.count). Conflicts keep current settings unless selected below.")
                            ForEach(migration.conflicts.sorted(), id: \.self) { key in
                                Text(preferenceName(key)).font(.headline)
                                Text("Current: \(describe(migration.current[key]))\nAntigravity: \(describe(migration.incoming[key]))").font(.caption).textSelection(.enabled)
                                Toggle("Use Antigravity settings for \(preferenceName(key))", isOn: Binding(get: { replacements.contains(key) }, set: { if $0 { replacements.insert(key) } else { replacements.remove(key) } }))
                            }
                            Button("Back Up and Import Reviewed Settings") { importSettings(migration) }
                        } else { Button("Review Antigravity Settings…", action: reviewSettings) }
                        Text("Imports device preferences only. Projects, credentials and system text-rendering overrides are excluded.").font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
        }.padding(.vertical, 8)
    }
    private func previewLine(_ kind: ScreenplayElement, english: String, tamil: String) -> some View {
        let value = layout.isTamil(for: kind) ? tamil : english
        let indent: CGFloat = kind == .character ? 180 : kind == .dialogue ? 85 : kind == .parenthetical ? 135 : 0
        return Text(layout.isUppercase(for: kind) ? value.uppercased() : value)
            .font(Font(NSFont(name: layout.effectiveFontName(for: kind), size: layout.effectiveFontSize(for: kind)) ?? .monospacedSystemFont(ofSize: layout.effectiveFontSize(for: kind), weight: .regular)))
            .fontWeight(layout.isBold(for: kind) ? .bold : .regular).italic(layout.isItalic(for: kind)).underline(layout.isUnderline(for: kind))
            .padding(.leading, indent).frame(maxWidth: .infinity, alignment: kind == .transition ? .trailing : .leading)
    }
    private func updateElement(_ action: (inout ElementTypography) -> Void) {
        update { value in
            var entry = value.elements[element.rawValue] ?? ElementTypography(isBold: value.isBold(for: element), isUppercase: value.isUppercase(for: element))
            action(&entry); value.elements[element.rawValue] = entry
        }
    }
    private func preferenceName(_ key: String) -> String {
        ["default_script_layout": "Typography defaults", "frontstage_restore_last_project": "Session restoration", "frontstage_recent_projects": "Recent projects", "frontstage_last_project_path": "Last project", "write-left-visible": "Scene cards visibility", "write-right-visible": "Inspector visibility", "default_paper_size": "Default paper size"][key] ?? key
    }
    private func describe(_ value: JSONValue?) -> String {
        guard let value else { return "Not set" }
        if value == .bool(true) { return "On" }; if value == .bool(false) { return "Off" }
        if let fields = value.object, fields["fontName"] != nil {
            let size: String
            if case .number(let value) = fields["fontSize"] { size = NSDecimalNumber(decimal: value).stringValue } else { size = "12" }
            return "\(fields["fontName"]?.string ?? "Courier"), \(size) pt, \(fields["elements"]?.object?.count ?? 0) element overrides"
        }
        if let string = value.string { return string }
        if let array = value.array { return array.compactMap(\.string).joined(separator: "\n") }
        return "Imported preference"
    }
    private func fontField(_ label: String, value: String, changed: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading) {
            HStack {
                TextField(label, text: Binding(get: { value }, set: changed))
                Menu("Installed Fonts") { ForEach(NSFontManager.shared.availableFontFamilies.filter { fontSearch.isEmpty || $0.localizedCaseInsensitiveContains(fontSearch) }.sorted(), id: \.self) { font in Button(font) { changed(font) } } }
            }
            if !value.isEmpty && NSFont(name: value, size: 12) == nil {
                Text("\(value) is unavailable; using system monospace. The stored font name is retained.").font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private func flag(_ title: String, _ key: WritableKeyPath<ElementTypography, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { key == \.isBold ? layout.isBold(for: element) : key == \.isItalic ? layout.isItalic(for: element) : key == \.isUnderline ? layout.isUnderline(for: element) : layout.isUppercase(for: element) }, set: { enabled in updateElement { $0[keyPath: key] = enabled } }))
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

#if os(macOS)
struct TypographyPreferencesMenuItem: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View { Button("Typography Preferences…") { UserDefaults.standard.set(0, forKey: "dot_preferences_tab"); openSettings() } }
}
#endif
