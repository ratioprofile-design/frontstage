import Foundation

public enum CharacterField: String, CaseIterable, Sendable {
    case occupation, backstory, psychology, physiology, sociology, wardrobeNotes, specialSkills, playingAge
    public var label: String {
        switch self {
        case .wardrobeNotes: return "Wardrobe Notes"
        case .specialSkills: return "Special Skills"
        case .playingAge: return "Playing Age"
        default: return rawValue.capitalized
        }
    }
}

public enum CastingStatus: String, CaseIterable, Sendable {
    case idea, inTalks = "in_talks", auditionRequested = "audition_requested"
    case selfTapeReceived = "self_tape_received", callback, chemistryRead = "chemistry_read"
    case offerSent = "offer_sent", contractSigned = "contract_signed", onBoard = "on_board", passed, hold
    public var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

public struct CastingOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let notes: String
    public let email: String
    public let phone: String
}

public struct CharacterRecord: Identifiable, Equatable, Sendable {
    /// The legacy dictionary key remains stable so scene assignments retain their references.
    public let id: String
    public let name: String
    public let fields: [String: String]
    public let artists: [CastingOption]
    public let confirmedArtistID: String?
}

extension Project {
    public var characters: [CharacterRecord] {
        (state["characterData"]?.object ?? [:]).compactMap { key, value in
            guard let record = value.object else { return nil }
            let artists = (record["artists"]?.array ?? []).compactMap { value -> CastingOption? in
                guard let item = value.object, let id = item["id"]?.string else { return nil }
                let contact = item["contact"]?.object ?? [:]
                return CastingOption(id: id, name: item["name"]?.string ?? "Unnamed",
                    status: item["status"]?.string ?? "idea", notes: item["notes"]?.string ?? "",
                    email: contact["email"]?.string ?? "", phone: contact["phone"]?.string ?? item["phone"]?.string ?? "")
            }
            return CharacterRecord(id: key, name: record["name"]?.string ?? key,
                fields: record.compactMapValues(\.string), artists: artists,
                confirmedArtistID: record["confirmedArtistId"]?.string)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    public mutating func createCharacter(name: String) throws -> String {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { throw ProjectError.invalidProject("a character needs a name") }
        if let existing = state["characterData"], existing.object == nil { throw ProjectError.invalidProject("the character dictionary cannot be edited in this format") }
        var records = state["characterData"]?.object ?? [:]
        guard !records.keys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }),
              !characters.contains(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) else {
            throw ProjectError.invalidProject("a character with that name already exists")
        }
        records[key] = .object(["id": .string(UUID().uuidString), "name": .string(key), "backstory": .string(""),
                                "artists": .array([]), "relationships": .array([]), "images": .array([])])
        state["characterData"] = .object(records)
        return key
    }

    private mutating func editCharacter(_ key: String, _ operation: (inout [String: JSONValue]) throws -> Void) throws {
        var records = state["characterData"]?.object ?? [:]
        guard var record = records[key]?.object else { throw ProjectError.invalidProject("character not found") }
        try operation(&record)
        records[key] = .object(record)
        state["characterData"] = .object(records)
    }

    public mutating func updateCharacter(_ key: String, field: CharacterField, value: String) throws {
        try editCharacter(key) { $0[field.rawValue] = .string(value) }
    }

    @discardableResult
    public mutating func addCastingOption(character key: String, name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ProjectError.invalidProject("an actor needs a name") }
        let id = UUID().uuidString
        try editCharacter(key) { fields in
            var artists = fields["artists"]?.array ?? []
            artists.append(.object(["id": .string(id), "name": .string(clean), "rank": .number(Decimal(artists.count + 1)),
                                    "status": .string(CastingStatus.idea.rawValue), "notes": .string("")]))
            fields["artists"] = .array(artists)
        }
        return id
    }

    public mutating func updateCastingOption(character key: String, artistID: String, name: String? = nil,
        status: CastingStatus? = nil, notes: String? = nil, email: String? = nil, phone: String? = nil) throws {
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProjectError.invalidProject("an actor needs a name")
        }
        try editCharacter(key) { fields in
            var artists = fields["artists"]?.array ?? []
            guard let index = artists.firstIndex(where: { $0.object?["id"] == .string(artistID) }),
                  var artist = artists[index].object else { throw ProjectError.invalidProject("casting option not found") }
            if let name { artist["name"] = .string(name) }
            if let status { artist["status"] = .string(status.rawValue) }
            if let notes { artist["notes"] = .string(notes) }
            if email != nil || phone != nil {
                var contact = artist["contact"]?.object ?? [:]
                if let email { contact["email"] = .string(email) }
                if let phone { contact["phone"] = .string(phone) }
                artist["contact"] = .object(contact)
            }
            if status == .passed && fields["confirmedArtistId"] == .string(artistID) { fields.removeValue(forKey: "confirmedArtistId") }
            artists[index] = .object(artist)
            fields["artists"] = .array(artists)
        }
    }

    public mutating func confirmCastingOption(character key: String, artistID: String?) throws {
        try editCharacter(key) { fields in
            if let artistID {
                guard let artist = fields["artists"]?.array?.first(where: { $0.object?["id"] == .string(artistID) })?.object,
                      artist["status"] != .string("passed") else { throw ProjectError.invalidProject("choose an available casting option") }
                fields["confirmedArtistId"] = .string(artistID)
            } else { fields.removeValue(forKey: "confirmedArtistId") }
        }
    }

    public func sceneCharacters(_ sceneID: Decimal) -> [String] {
        let fields = state["beats"]?.array?.first { $0.object?["id"] == .number(sceneID) }?.object
        return (fields?["characters"]?.array ?? []).compactMap(\.string)
    }

    public mutating func assignCharacter(_ key: String, to sceneID: Decimal, assigned: Bool) throws {
        guard characters.contains(where: { $0.id == key }) else { throw ProjectError.invalidProject("character not found") }
        try editBeat(sceneID) { fields in
            var names = fields["characters"]?.array ?? []
            if assigned {
                if !names.contains(.string(key)) { names.append(.string(key)) }
            } else { names.removeAll { $0 == .string(key) } }
            fields["characters"] = .array(names)
        }
    }
}
