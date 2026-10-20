import Foundation

public struct ProjectMergeResult: Sendable, Equatable {
    public var value: JSONValue
    public var conflicts: [String]
}

/// Three-way merge for shared document fields. Conflicting edits require an explicit choice.
public enum ProjectMerge {
    public static func merge(base: JSONValue, local: JSONValue, remote: JSONValue) -> ProjectMergeResult {
        var conflicts: [String] = []
        func id(_ value: JSONValue) -> String? {
            if let text = value.object?["id"]?.string { return text }
            return value.object?["id"]?.decimal.map { "\($0)" }
        }
        func escaped(_ key: String) -> String { key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
        func combine(_ base: JSONValue?, _ local: JSONValue?, _ remote: JSONValue?, path: String) -> JSONValue? {
            if local == remote { return local }
            if local == base { return remote }
            if remote == base { return local }
            if let l = local?.object, let r = remote?.object, base == nil || base?.object != nil {
                let b = base?.object ?? [:]
                var output: [String: JSONValue] = [:]
                for key in Set(b.keys).union(l.keys).union(r.keys).sorted() {
                    output[key] = combine(b[key], l[key], r[key], path: path + "/" + escaped(key))
                }
                return .object(output)
            }
            if let b = base?.array, let l = local?.array, let r = remote?.array {
                let bi = b.compactMap(id), li = l.compactMap(id), ri = r.compactMap(id)
                if bi.count == b.count && li.count == l.count && ri.count == r.count && Set(bi).count == bi.count && Set(li).count == li.count && Set(ri).count == ri.count {
                    let bm = Dictionary(uniqueKeysWithValues: zip(bi, b)), lm = Dictionary(uniqueKeysWithValues: zip(li, l)), rm = Dictionary(uniqueKeysWithValues: zip(ri, r))
                    var values: [String: JSONValue] = [:]
                    for key in Set(bi).union(li).union(ri).sorted() { values[key] = combine(bm[key], lm[key], rm[key], path: path + "/" + escaped(key)) }
                    let alive = Set(values.keys), order: [String]
                    if li == bi { order = ri }
                    else if ri == bi || li == ri { order = li }
                    else {
                        var edges: [String: Set<String>] = [:], incoming = Dictionary(uniqueKeysWithValues: alive.map { ($0, 0) })
                        for list in [li, ri] {
                            let valid = list.filter(alive.contains)
                            for (a, b) in zip(valid, valid.dropFirst()) where a != b {
                                if edges[a, default: []].insert(b).inserted { incoming[b, default: 0] += 1 }
                            }
                        }
                        var sorted: [String] = [], ready = incoming.filter { $0.value == 0 }.map(\.key).sorted()
                        while !ready.isEmpty {
                            let key = ready.removeFirst(); sorted.append(key)
                            for next in (edges[key] ?? []).sorted() { incoming[next, default: 0] -= 1; if incoming[next] == 0 { ready.append(next); ready.sort() } }
                        }
                        if sorted.count != alive.count { conflicts.append(path + "/@order"); order = li + ri.filter { !Set(li).contains($0) } }
                        else { order = sorted }
                    }
                    return .array(order.filter(alive.contains).compactMap { values[$0] })
                }
            }
            conflicts.append(path.isEmpty ? "/" : path)
            return local
        }
        let value = combine(base, local, remote, path: "") ?? .null
        return ProjectMergeResult(value: value, conflicts: conflicts)
    }
}
