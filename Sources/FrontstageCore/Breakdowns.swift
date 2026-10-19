import Foundation

public enum BreakdownCategory: String, CaseIterable, Sendable {
    case cast = "CAST", extras = "EXTRAS", stunts = "STUNTS", vehicles = "VEHICLES", props = "PROPS"
    case sfx = "SFX", wardrobe = "WARDROBE", makeup = "MAKEUP", animals = "ANIMALS", sound = "SOUND"
    case setDressing = "SET_DRESSING", greenery = "GREENERY", specialEquipment = "SPECIAL_EQUIPMENT"
    case lightingGrip = "LIGHTING_GRIP", safety = "SAFETY"
    public var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

public struct BreakdownEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let name: String
    public let notes: String
    public let count: Int
    let storageKey: String
    let bucket: String
    let index: Int
}

extension Project {
    private static func breakdownStorageKey(_ beat: [String: JSONValue]) -> String {
        beat["breakdownData"]?.object != nil ? "breakdownData" : "breakdown"
    }

    public func breakdownItems(for sceneID: Decimal) -> [BreakdownEntry] {
        guard let beat = state["beats"]?.array?.first(where: { $0.object?["id"] == .number(sceneID) })?.object else { return [] }
        let key = Self.breakdownStorageKey(beat)
        let fields = beat[key]?.object ?? [:]
        let aliases = ["props": "PROPS", "costume": "WARDROBE", "practical": "SFX", "sound": "SOUND", "cast": "CAST", "location": "LOCATION", "vfx": "VFX"]
        var result: [BreakdownEntry] = []
        for bucket in fields.keys.sorted() {
            guard let items = fields[bucket]?.array else { continue }
            for (index, value) in items.enumerated() {
                let object = value.object
                guard let name = value.string ?? object?["name"]?.string else { continue }
                let count = max(1, min(100_000, NSDecimalNumber(decimal: object?["count"]?.decimal ?? 1).intValue))
                result.append(BreakdownEntry(id: "\(key):\(bucket):\(object?["id"]?.string ?? String(index))",
                    category: object?["category"]?.string ?? aliases[bucket] ?? bucket,
                    name: name, notes: object?["description"]?.string ?? "", count: count,
                    storageKey: key, bucket: bucket, index: index))
            }
        }
        return result
    }

    public mutating func addBreakdownItem(sceneID: Decimal, category: BreakdownCategory,
        name: String, count: Int = 1, notes: String = "") throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, (1...100_000).contains(count) else { throw ProjectError.invalidProject("enter an item name and a positive quantity") }
        try editBeat(sceneID) { fields in
            let key = Self.breakdownStorageKey(fields)
            var breakdown = fields[key]?.object ?? [:]
            var items = breakdown[category.rawValue]?.array ?? []
            items.append(.object(["id": .string(UUID().uuidString), "name": .string(clean), "count": .number(Decimal(count)),
                                   "category": .string(category.rawValue), "description": .string(notes)]))
            breakdown[category.rawValue] = .array(items)
            fields[key] = .object(breakdown)
        }
    }

    public mutating func updateBreakdownItem(sceneID: Decimal, itemID: String, name: String? = nil,
        count: Int? = nil, notes: String? = nil) throws {
        guard let entry = breakdownItems(for: sceneID).first(where: { $0.id == itemID }) else { throw ProjectError.invalidProject("breakdown item not found") }
        if let count, !(1...100_000).contains(count) { throw ProjectError.invalidProject("quantity must be positive") }
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ProjectError.invalidProject("item name cannot be empty") }
        try editBeat(sceneID) { fields in
            var breakdown = fields[entry.storageKey]?.object ?? [:]
            var items = breakdown[entry.bucket]?.array ?? []
            var item = items[entry.index].object ?? ["name": .string(entry.name)]
            if let name { item["name"] = .string(name) }
            if let count { item["count"] = .number(Decimal(count)) }
            if let notes { item["description"] = .string(notes) }
            items[entry.index] = .object(item)
            breakdown[entry.bucket] = .array(items)
            fields[entry.storageKey] = .object(breakdown)
        }
    }

    public mutating func removeBreakdownItem(sceneID: Decimal, itemID: String) throws {
        guard let entry = breakdownItems(for: sceneID).first(where: { $0.id == itemID }) else { throw ProjectError.invalidProject("breakdown item not found") }
        try editBeat(sceneID) { fields in
            var breakdown = fields[entry.storageKey]?.object ?? [:]
            var items = breakdown[entry.bucket]?.array ?? []
            items.remove(at: entry.index)
            breakdown[entry.bucket] = .array(items)
            fields[entry.storageKey] = .object(breakdown)
        }
    }
}
