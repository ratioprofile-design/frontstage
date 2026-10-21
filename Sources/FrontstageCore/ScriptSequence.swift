import Foundation

/// A consecutive script range keeps its scene identity even when that scene returns later.
public struct ScriptSegment: Equatable, Sendable {
    public var scene: Scene
    public var beatIDs: [String]
    public let number: String
    public let isContinuation: Bool
}

extension Project {
    public func orderedScript() throws -> [ScriptSegment] {
        let active = scenes.filter { !$0.isDisabled }
        let numbers = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($0.element.id, $0.element.sceneNumber.isEmpty ? String($0.offset + 1) : $0.element.sceneNumber) })
        guard state["frontstageWhiteboard"] != nil else {
            return active.map { ScriptSegment(scene: $0, beatIDs: [], number: numbers[$0.id]!, isContinuation: false) }
        }
        let board = try whiteboard(), byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let unused = Set(board.layers.filter(\.unused).map(\.id)), inactive = Set(board.blocks.filter { unused.contains($0.layerID) }.map(\.id))
        let represented = Set(board.beats.map(\.sceneID))
        var segments: [ScriptSegment] = [], seen = Set<Decimal>()
        for beat in board.orderedBeats where !beat.omitted && !inactive.contains(beat.blockID) {
            guard var scene = byID[beat.sceneID] else { continue }
            if let last = segments.indices.last, segments[last].scene.id == beat.sceneID {
                segments[last].scene.html += beat.html; segments[last].beatIDs.append(beat.id)
            } else {
                let continued = !seen.insert(scene.id).inserted
                scene.html = beat.html
                if continued { scene.startsNewPage = false }
                segments.append(ScriptSegment(scene: scene, beatIDs: [beat.id], number: numbers[scene.id]!, isContinuation: continued))
            }
        }
        // Preserve active imported scenes that do not yet have native snippet ownership.
        for scene in active where !represented.contains(scene.id) {
            segments.append(ScriptSegment(scene: scene, beatIDs: [], number: numbers[scene.id]!, isContinuation: false))
        }
        return segments
    }
}
