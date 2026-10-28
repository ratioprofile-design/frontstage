import Foundation

public enum ProductionField: String, CaseIterable, Sendable {
    case date, callTime, wrapTime, locationName, locationAddress, parkingInstructions
    case hospitalName, hospitalAddress, hospitalEmergencyPhone, director, producer, firstAd, cinematographer, weather, notes
    public var label: String {
        switch self {
        case .locationName: return "Location"
        case .locationAddress: return "Location Address"
        case .parkingInstructions: return "Parking Instructions"
        case .hospitalName: return "Hospital"
        case .hospitalAddress: return "Hospital Address"
        case .hospitalEmergencyPhone: return "Hospital / Emergency Phone"
        case .firstAd: return "First AD"
        case .callTime: return "Crew Call"
        case .wrapTime: return "Estimated Wrap"
        default: return rawValue.capitalized
        }
    }
}

public enum CastTimingField: String, CaseIterable, Sendable {
    case pickupTime, makeupTime, onSetTime, notes
    public var label: String {
        switch self {
        case .pickupTime: return "Pickup"
        case .makeupTime: return "Makeup"
        case .onSetTime: return "On Set"
        case .notes: return "Notes"
        }
    }
}

public struct ProductionDay: Identifiable, Equatable, Sendable {
    public let id: String
    public let number: Int
    public let date: String
    public let callTime: String
    public let wrapTime: String
    public let sceneIDs: [Decimal]
    public let fields: [String: String]
    public let castCalls: [String: [String: String]]
}

public enum ProductionDates {
    public static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    public static func string(_ value: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    public static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    public static func time(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: value)
    }
}

extension Project {
    public var productionDays: [ProductionDay] {
        (state["frontstageProduction"]?.object?["days"]?.array ?? []).compactMap { value in
            guard let day = value.object, let id = day["id"]?.string else { return nil }
            return ProductionDay(id: id, number: min(100_000, max(1, NSDecimalNumber(decimal: day["number"]?.decimal ?? 1).intValue)),
                date: day["date"]?.string ?? "", callTime: day["callTime"]?.string ?? "06:00", wrapTime: day["wrapTime"]?.string ?? "18:00",
                sceneIDs: (day["sceneIDs"]?.array ?? []).compactMap(\.decimal), fields: day.compactMapValues(\.string),
                castCalls: (day["castCalls"]?.object ?? [:]).compactMapValues { $0.object?.compactMapValues(\.string) })
        }.sorted { $0.number == $1.number ? $0.id < $1.id : $0.number < $1.number }
    }

    private mutating func editProduction(_ operation: (inout [String: JSONValue]) throws -> Void) throws {
        if let existing = state["frontstageProduction"], existing.object == nil {
            throw ProjectError.invalidProject("the production plan is not an editable object")
        }
        var production = state["frontstageProduction"]?.object ?? [:]
        if let version = production["schemaVersion"], version != .number(1) {
            throw ProjectError.invalidProject("this production plan requires a newer DOT version")
        }
        if let days = production["days"], days.array == nil { throw ProjectError.invalidProject("production days must be an array") }
        try operation(&production)
        production["schemaVersion"] = .number(1)
        state["frontstageProduction"] = .object(production)
    }

    @discardableResult
    public mutating func addProductionDay(date: String, callTime: String = "06:00", wrapTime: String = "18:00") throws -> String {
        guard ProductionDates.date(date) != nil, ProductionDates.minutes(callTime) != nil,
              ProductionDates.minutes(wrapTime) != nil else { throw ProjectError.invalidProject("enter a valid date and HH:mm call/wrap times") }
        let number = (productionDays.map(\.number).max() ?? 0) + 1
        guard number <= 100_000 else { throw ProjectError.invalidProject("too many shooting days") }
        let id = UUID().uuidString
        try editProduction { fields in
            var days = fields["days"]?.array ?? []
            days.append(.object(["id": .string(id), "number": .number(Decimal(number)), "date": .string(date),
                                  "callTime": .string(callTime), "wrapTime": .string(wrapTime), "sceneIDs": .array([]), "castCalls": .object([:])]))
            fields["days"] = .array(days)
        }
        return id
    }

    private mutating func editProductionDay(_ id: String, _ operation: (inout [String: JSONValue]) throws -> Void) throws {
        try editProduction { production in
            var days = production["days"]?.array ?? []
            guard let index = days.firstIndex(where: { $0.object?["id"] == .string(id) }),
                  var day = days[index].object else { throw ProjectError.invalidProject("shooting day not found") }
            try operation(&day)
            days[index] = .object(day)
            production["days"] = .array(days)
        }
    }

    public mutating func updateProductionDay(_ id: String, field: ProductionField, value: String) throws {
        if field == .date && ProductionDates.date(value) == nil { throw ProjectError.invalidProject("date must be YYYY-MM-DD") }
        if [.callTime, .wrapTime].contains(field) && ProductionDates.minutes(value) == nil {
            throw ProjectError.invalidProject("time must be HH:mm")
        }
        try editProductionDay(id) { $0[field.rawValue] = .string(value) }
    }

    public mutating func assignScene(_ sceneID: Decimal, toProductionDay dayID: String?) throws {
        if let dayID {
            guard productionDays.contains(where: { $0.id == dayID }) else { throw ProjectError.invalidProject("shooting day not found") }
            guard let scene = scenes.first(where: { $0.id == sceneID }), !scene.isDisabled else {
                throw ProjectError.invalidProject("only active scenes can be scheduled")
            }
        }
        try editProduction { fields in
            var days = fields["days"]?.array ?? []
            for index in days.indices {
                guard var day = days[index].object else { continue }
                var ids = (day["sceneIDs"]?.array ?? []).filter { $0 != .number(sceneID) }
                if let dayID, day["id"] == .string(dayID) { ids.append(.number(sceneID)) }
                day["sceneIDs"] = .array(ids)
                days[index] = .object(day)
            }
            fields["days"] = .array(days)
        }
    }

    public mutating func moveScheduledScene(_ sceneID: Decimal, dayID: String, offset: Int) throws {
        try editProductionDay(dayID) { day in
            var ids = day["sceneIDs"]?.array ?? []
            guard let index = ids.firstIndex(of: .number(sceneID)) else { throw ProjectError.sceneNotFound }
            let target = min(max(0, index + offset), ids.count - 1)
            let item = ids.remove(at: index)
            ids.insert(item, at: target)
            day["sceneIDs"] = .array(ids)
        }
    }

    public func sceneEstimate(_ sceneID: Decimal) -> Int {
        let value = state["frontstageProduction"]?.object?["sceneEstimates"]?.object?["\(sceneID)"]?.decimal ?? 60
        return min(1440, max(1, NSDecimalNumber(decimal: value).intValue))
    }

    public mutating func setSceneEstimate(_ sceneID: Decimal, minutes: Int) throws {
        guard scenes.contains(where: { $0.id == sceneID }) else { throw ProjectError.sceneNotFound }
        guard (1...1440).contains(minutes) else { throw ProjectError.invalidProject("scene estimates must be 1–1440 minutes") }
        try editProduction { fields in
            var estimates = fields["sceneEstimates"]?.object ?? [:]
            estimates["\(sceneID)"] = .number(Decimal(minutes))
            fields["sceneEstimates"] = .object(estimates)
        }
    }

    public func scheduledScenes(for dayID: String) -> [Scene] {
        guard let day = productionDays.first(where: { $0.id == dayID }) else { return [] }
        return day.sceneIDs.compactMap { id in scenes.first { $0.id == id && !$0.isDisabled } }
    }

    public func castForProductionDay(_ dayID: String) -> [CharacterRecord] {
        let keys = Set(scheduledScenes(for: dayID).flatMap { sceneCharacters($0.id) })
        return characters.filter { keys.contains($0.id) }
    }

    public mutating func updateCastCall(dayID: String, characterID: String, field: CastTimingField, value: String) throws {
        guard characters.contains(where: { $0.id == characterID }) else { throw ProjectError.invalidProject("character not found") }
        if field != .notes && !value.isEmpty && ProductionDates.minutes(value) == nil { throw ProjectError.invalidProject("cast call time must be HH:mm") }
        try editProductionDay(dayID) { day in
            var calls = day["castCalls"]?.object ?? [:]
            var call = calls[characterID]?.object ?? [:]
            if value.isEmpty { call.removeValue(forKey: field.rawValue) }
            else { call[field.rawValue] = .string(value) }
            calls[characterID] = .object(call)
            day["castCalls"] = .object(calls)
        }
    }

    public func scheduleWarnings(for dayID: String) -> [String] {
        guard let day = productionDays.first(where: { $0.id == dayID }),
              let date = ProductionDates.date(day.date), let start = ProductionDates.minutes(day.callTime),
              let wrap = ProductionDates.minutes(day.wrapTime) else { return ["Invalid shooting-day date or time."] }
        let capacity = wrap > start ? wrap - start : wrap + 1440 - start
        let scheduled = scheduledScenes(for: dayID)
        let estimate = scheduled.reduce(0) { $0 + sceneEstimate($1.id) }
        var warnings: [String] = []
        if estimate > capacity { warnings.append("Estimated scenes exceed the call-to-wrap window by \(estimate - capacity) minutes.") }
        if capacity > 12 * 60 { warnings.append("The planned shooting window exceeds 12 hours.") }
        if scheduled.count != day.sceneIDs.count { warnings.append("Omitted or missing scenes remain assigned; they are excluded from exports.") }
        let ordered = productionDays.sorted { a, b in a.date == b.date ? a.number < b.number : a.date < b.date }
        if let index = ordered.firstIndex(where: { $0.id == dayID }), index > 0 {
            let previous = ordered[index - 1]
            if let previousDate = ProductionDates.date(previous.date),
               let previousCall = ProductionDates.minutes(previous.callTime), let previousWrap = ProductionDates.minutes(previous.wrapTime) {
                let endMinutes = previousWrap > previousCall ? previousWrap : previousWrap + 1440
                let end = previousDate.addingTimeInterval(Double(endMinutes * 60))
                let beginning = date.addingTimeInterval(Double(start * 60))
                let gap = beginning.timeIntervalSince(end) / 3600
                if gap < 0 { warnings.append("This day overlaps the previous shooting day.") }
                else if gap < 12 { warnings.append("Less than 12 hours of turnaround after the previous day.") }
            }
        }
        return warnings
    }
}
