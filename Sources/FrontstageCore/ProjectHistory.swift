import Foundation

/// Session history is bounded and coalesces bursts of typing without mutating saved snapshots.
public struct ProjectHistory: Sendable {
    private struct Entry: Sendable { let project: Project; let label: String }
    private var past: [Entry] = []
    private var future: [Entry] = []
    private var lastKey: String?
    private var lastTime: Date?
    private let limit: Int

    public init(limit: Int = 40) { self.limit = max(1, limit) }
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var undoLabel: String { past.last?.label ?? "Project Change" }
    public var redoLabel: String { future.last?.label ?? "Project Change" }

    public mutating func endTypingGroup() { lastKey = nil; lastTime = nil }

    public mutating func record(_ previous: Project, label: String, key: String? = nil, now: Date = Date()) {
        let coalesce = key != nil && key == lastKey && future.isEmpty &&
            now.timeIntervalSince(lastTime ?? .distantPast) >= 0 &&
            now.timeIntervalSince(lastTime ?? .distantPast) < 1
        if !coalesce {
            past.append(Entry(project: previous, label: label))
            if past.count > limit { past.removeFirst(past.count - limit) }
        }
        future.removeAll()
        lastKey = key
        lastTime = now
    }

    public mutating func undo(current: Project) -> Project? {
        guard let entry = past.popLast() else { return nil }
        future.append(Entry(project: current, label: entry.label))
        lastKey = nil
        return entry.project
    }

    public mutating func redo(current: Project) -> Project? {
        guard let entry = future.popLast() else { return nil }
        past.append(Entry(project: current, label: entry.label))
        lastKey = nil
        return entry.project
    }
}

/// Recovery writes only an app-owned copy; it never writes to an imported source path.
public struct RecoveryStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("session.frontstage") }
    public init(directory: URL) { self.directory = directory }

    public static func applicationDefault() -> Self {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return Self(directory: base.appendingPathComponent("Frontstage/Recovery", isDirectory: true))
    }

    public func save(_ project: Project) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try project.save(to: fileURL)
    }

    public func load() throws -> Project? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Project.load(from: fileURL)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
