import Foundation

/// Only documented application preferences cross domains. System overrides and credentials never do.
public struct PreferenceImportReview: Sendable {
    public static let recognizedKeys: Set<String> = ["default_script_layout", "frontstage_restore_last_project", "frontstage_recent_projects", "frontstage_last_project_path", "write-left-visible", "write-right-visible", "default_paper_size"]
    public let incoming: [String: JSONValue]
    public let current: [String: JSONValue]
    public var conflicts: Set<String> { Set(incoming.keys.filter { current[$0] != nil && current[$0] != incoming[$0] }) }
    public init(current: [String: JSONValue], incoming: [String: JSONValue]) {
        self.current = current.filter { Self.recognizedKeys.contains($0.key) && Self.valid($0.key, $0.value) }
        self.incoming = incoming.filter { Self.recognizedKeys.contains($0.key) && Self.valid($0.key, $0.value) }
    }
    /// Conflicts default to keeping the current device settings.
    public func accepted(replaceConflicts: Set<String> = []) -> [String: JSONValue] {
        incoming.filter { current[$0.key] == nil || current[$0.key] == $0.value || replaceConflicts.contains($0.key) }
    }
    private static func valid(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "default_script_layout":
            let data: Data?
            if let string = value.string { data = string.data(using: .utf8) } else { data = try? JSONEncoder().encode(value) }
            guard let data, let layout = try? JSONDecoder().decode(ScriptLayoutSettings.self, from: data) else { return false }
            return (try? layout.validate()) != nil
        case "frontstage_restore_last_project", "write-left-visible", "write-right-visible": return value == .bool(true) || value == .bool(false)
        case "frontstage_recent_projects": return value.array?.allSatisfy { $0.string != nil } == true
        case "frontstage_last_project_path": return value.string?.isEmpty == false
        case "default_paper_size": return ["A4", "US Letter", "a4", "letter"].contains(value.string ?? "")
        default: return false
        }
    }
}
