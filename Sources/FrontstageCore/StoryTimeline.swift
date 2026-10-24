import Foundation

/// A read-only projection of estimated story time. Board coordinates are independent.
public enum TimelineTimeBase: String, CaseIterable, Codable, Sendable { case beats = "Beat Number", time = "Time", pages = "Pages" }
public struct StoryTimeline: Sendable {
    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var start: Double
        public var duration: Double
        public var color: String
        public var value: Double? = nil
        public var absolute = false
        public var tension = 0.0
        public var beatID: String
    }
    public struct Track: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var kind: String
        public var items: [Item]
    }
    public var beatTimes: [String: Double] = [:]
    public var beatPages: [String: Double] = [:]
    public var tracks: [Track] = []
    public var end: Double
    public init(project: Project, timeBase: TimelineTimeBase = .beats) throws {
        let board = try project.whiteboard()
        let beats = board.orderedBeats.filter { !$0.omitted && !board.isUnused($0) }
        var items: [Item] = []
        var time = 0.0, pages = 0.0
        for (index, beat) in beats.enumerated() {
            let pageCount = Self.estimatedPages(beat.html)
            let duration = beat.timelineDuration ?? (pageCount * project.timelineMinutesPerPage)
            beatTimes[beat.id] = time; beatPages[beat.id] = pages
            let start = timeBase == .beats ? Double(index) : timeBase == .time ? time : pages
            let length = timeBase == .beats ? 1 : timeBase == .time ? duration : pageCount
            items.append(.init(id: beat.id, title: beat.title, start: start, duration: length, color: beat.color, beatID: beat.id))
            time += duration; pages += pageCount
        }
        end = max(timeBase == .beats ? 25 : 1, (items.last.map { $0.start + $0.duration } ?? 0) + (timeBase == .beats ? 2 : 0.2))
        var scenes: [Item] = []
        var lastScene: Decimal?
        for (index, beat) in beats.enumerated() {
            let item = items[index]
            if lastScene == beat.sceneID, let last = scenes.last, item.start <= last.start + last.duration + 0.0001 {
                scenes[scenes.count - 1].duration = max(last.duration, item.start + item.duration - last.start)
            } else {
                let scene = project.scenes.first { $0.id == beat.sceneID }
                let title = scene.map { "\($0.heading.location.isEmpty ? $0.title : $0.heading.location) – \($0.heading.time)" } ?? beat.title
                scenes.append(Item(id: "scene-" + beat.id, title: title, start: item.start, duration: item.duration, color: beat.color, beatID: beat.id))
            }
            lastScene = beat.sceneID
        }
        let markers = project.storyMilestones
        for (trackID, title) in [("episodes", "Episodes"), ("acts", "Acts"), ("chapters", "Chapters"), ("sections", "Sections")] {
            let matching = markers.filter { $0.kind.trackID == trackID }
            let positions = matching.map { marker in beats.firstIndex { $0.start >= marker.x / StorySequencer.pointsPerPage }.map { items[$0].start } ?? end }
            let intervals = matching.enumerated().map { index, marker in
                let start = positions[index]
                let next = index + 1 < matching.count ? positions[index + 1] : end
                return Item(id: marker.id, title: marker.title, start: start, duration: max(0.1, next - start), color: "#476b9c", beatID: "")
            }
            tracks.append(.init(id: trackID, title: title, kind: trackID, items: intervals))
        }
        tracks.append(.init(id: "scenes", title: "Scenes", kind: "scenes", items: scenes))
        tracks.append(.init(id: "beats", title: "Beats", kind: "beats", items: items))
        for kind in ["tags", "characters"] {
            let names = Set(beats.flatMap { kind == "tags" ? $0.tags : $0.characters }).sorted()
            for name in names {
                let matching = beats.filter { (kind == "tags" ? $0.tags : $0.characters).contains(name) }
                let color = Self.color(name)
                let tracksEmotion = kind == "tags" && matching.contains { $0.emotionChanges?[name] != nil }
                var emotionValue = 0.0
                let trackItems = matching.compactMap { beat -> Item? in
                    guard var item = items.first(where: { $0.id == beat.id }) else { return nil }
                    item.color = color
                    if kind == "tags", let change = beat.emotionChanges?[name] {
                        item.absolute = beat.emotionAbsoluteTags?.contains(name) == true
                        emotionValue = item.absolute ? change : emotionValue + change
                    }
                    if tracksEmotion { item.value = emotionValue }
                    item.tension = beat.tensions?[name] ?? 0
                    return item
                }
                tracks.append(.init(id: kind + ":" + name, title: name, kind: kind, items: trackItems))
            }
        }
        let heat = beats.compactMap { beat -> Item? in
            let tension = (beat.tensions ?? [:]).filter { beat.tags.contains($0.key) }.values.reduce(0) { $0 + max(0, $1) }
            guard tension > 0, var item = items.first(where: { $0.id == beat.id }) else { return nil }
            item.title = "Tension: \(tension)"; item.color = tension >= 5 ? "#ffad25" : "#93652c"; return item
        }
        tracks.append(.init(id: "heat", title: "Heat Map · Tension", kind: "heat", items: heat))
    }
    public static func estimatedPages(_ html: String) -> Double {
        let text = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        return max(1.0 / 55, Double(text.count) / 60 / 55)
    }

    public static func color(_ name: String) -> String {
        let palette = ["#11106b", "#5de5bb", "#a30e3f", "#d6ae1c", "#467e96"]
        return palette[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % palette.count]
    }
    public static func clock(_ time: Double) -> String {
        let seconds = max(0, Int((time * 60).rounded()))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
