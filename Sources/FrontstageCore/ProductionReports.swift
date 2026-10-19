import Foundation

public enum ProductionCSV {
    public static func cell(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let text = first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    public static func save(_ text: String, to url: URL) throws {
        let resolved = url.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "csv", resolved.pathExtension.lowercased() == "csv" else {
            throw ProjectError.invalidProject("choose a .csv destination that does not point to a project file")
        }
        try Data(text.utf8).write(to: resolved, options: .atomic)
    }
}

extension Project {
    public func sceneNumber(for sceneID: Decimal) -> String {
        let active = scenes.filter { !$0.isDisabled }
        guard let index = active.firstIndex(where: { $0.id == sceneID }) else { return "\(sceneID)" }
        return active[index].sceneNumber.isEmpty ? String(index + 1) : active[index].sceneNumber
    }

    public func scheduleCSV() -> String {
        var rows = [["Day", "Date", "Crew Call", "Wrap", "Scene ID", "Scene Number", "Heading", "Estimated Minutes", "Characters"]]
        for day in productionDays {
            for scene in scheduledScenes(for: day.id) {
                let number = sceneNumber(for: scene.id)
                rows.append([String(day.number), day.date, day.callTime, day.wrapTime, "\(scene.id)", number,
                    scene.heading.text, String(sceneEstimate(scene.id)), sceneCharacters(scene.id).joined(separator: "; ")])
            }
        }
        return ProductionCSV.encode(rows)
    }

    public func breakdownCSV() -> String {
        var rows = [["Scene ID", "Scene", "Category", "Item", "Quantity", "Notes"]]
        for scene in scenes where !scene.isDisabled {
            for item in breakdownItems(for: scene.id) {
                rows.append(["\(scene.id)", scene.heading.text, item.category, item.name, String(item.count), item.notes])
            }
        }
        return ProductionCSV.encode(rows)
    }

    public func callSheetText(for dayID: String) throws -> String {
        guard let day = productionDays.first(where: { $0.id == dayID }) else { throw ProjectError.invalidProject("shooting day not found") }
        func value(_ key: ProductionField) -> String {
            let text = day.fields[key.rawValue] ?? ""
            return text.isEmpty ? "Not entered" : text
        }
        var lines = [name.uppercased(), "CALL SHEET · DAY \(day.number) OF \(productionDays.count)", day.date,
                     "Crew call: \(day.callTime)    Estimated wrap: \(day.wrapTime)", "", "LOCATION & SAFETY",
                     "Location: \(value(.locationName))", "Address: \(value(.locationAddress))", "Parking: \(value(.parkingInstructions))",
                     "Hospital: \(value(.hospitalName))", "Hospital address: \(value(.hospitalAddress))",
                     "Emergency contact: \(value(.hospitalEmergencyPhone))", "Weather: \(value(.weather))", "", "KEY CREW",
                     "Director: \(value(.director))", "Producer: \(value(.producer))", "First AD: \(value(.firstAd))",
                     "Cinematographer: \(value(.cinematographer))", "", "SCHEDULED SCENES"]
        for scene in scheduledScenes(for: dayID) {
            lines.append("\(sceneNumber(for: scene.id)) · \(scene.heading.text) · \(sceneEstimate(scene.id)) min")
            for item in breakdownItems(for: scene.id) {
                lines.append("  \(item.category): \(item.name) ×\(item.count)\(item.notes.isEmpty ? "" : " — " + item.notes)")
            }
        }
        lines += ["", "CAST CALLS"]
        for role in castForProductionDay(dayID) {
            let actor = role.artists.first { $0.id == role.confirmedArtistID }?.name ?? "Casting unconfirmed"
            let call = day.castCalls[role.id] ?? [:]
            lines.append("\(role.name) — \(actor)")
            lines.append("  Pickup: \(call["pickupTime"] ?? "Not entered") · Makeup: \(call["makeupTime"] ?? "Not entered") · On set: \(call["onSetTime"] ?? day.callTime)")
            if let notes = call["notes"], !notes.isEmpty { lines.append("  \(notes)") }
        }
        let profiles = Set(characters.map(\.id))
        let unprofiled = Set(scheduledScenes(for: dayID).flatMap { sceneCharacters($0.id) }).subtracting(profiles)
        if !unprofiled.isEmpty { lines.append("Roles without profiles/call times: \(unprofiled.sorted().joined(separator: ", "))") }
        lines += ["", "PRODUCTION NOTES", value(.notes)]
        let warnings = scheduleWarnings(for: dayID)
        if !warnings.isEmpty { lines += ["", "SCHEDULE CHECKS"] + warnings }
        return lines.joined(separator: "\n")
    }
}
