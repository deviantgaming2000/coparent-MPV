import Foundation

struct ExchangeRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let exchangeDate: Date
    let timeZoneIdentifier: String
    let latitude: Double?
    let longitude: Double?
    let address: String
    var role: ExchangeRole
    var timing: ExchangeTiming
    var minutesOffset: Int?
    var attachedIncidentID: UUID?
    var tags: [EntryTag]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        exchangeDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier,
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String = "",
        role: ExchangeRole = .receivingChild,
        timing: ExchangeTiming = .onTime,
        minutesOffset: Int? = nil,
        attachedIncidentID: UUID? = nil,
        tags: [EntryTag] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.exchangeDate = exchangeDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.role = role
        self.timing = timing
        self.minutesOffset = minutesOffset
        self.attachedIncidentID = attachedIncidentID
        self.tags = tags
    }
}

extension ExchangeRecord {
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case exchangeDate
        case timeZoneIdentifier
        case latitude
        case longitude
        case address
        case role
        case timing
        case minutesOffset
        case attachedIncidentID
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        exchangeDate = try container.decode(Date.self, forKey: .exchangeDate)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? TimeZone.current.identifier
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        role = try container.decodeIfPresent(ExchangeRole.self, forKey: .role) ?? .receivingChild
        timing = try container.decodeIfPresent(ExchangeTiming.self, forKey: .timing) ?? .onTime
        minutesOffset = try container.decodeIfPresent(Int.self, forKey: .minutesOffset)
        attachedIncidentID = try container.decodeIfPresent(UUID.self, forKey: .attachedIncidentID)
        tags = try container.decodeIfPresent([EntryTag].self, forKey: .tags) ?? []
    }
}

enum ExchangeRole: String, CaseIterable, Identifiable, Codable {
    case receivingChild = "Receiving Child"
    case transferringChild = "Transferring Child"

    var id: String { rawValue }
}

enum ExchangeTiming: String, CaseIterable, Identifiable, Codable {
    case onTime = "On Time"
    case late = "Late"
    case early = "Early"

    var id: String { rawValue }

    var statusIcon: String {
        switch self {
        case .onTime:
            return "checkmark.circle.fill"
        case .late, .early:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct ExchangeStatistics: Equatable {
    let totalExchanges: Int
    let onTimeExchanges: Int
    let lateExchanges: Int
    let earlyExchanges: Int
    let expandedIncidents: Int
    let averageDelayMinutes: Double?

    init(records: [ExchangeRecord]) {
        totalExchanges = records.count
        onTimeExchanges = records.filter { $0.timing == .onTime }.count
        lateExchanges = records.filter { $0.timing == .late }.count
        earlyExchanges = records.filter { $0.timing == .early }.count
        expandedIncidents = records.filter { $0.attachedIncidentID != nil }.count

        let delayValues = records
            .filter { $0.timing == .late }
            .compactMap(\.minutesOffset)
        averageDelayMinutes = delayValues.isEmpty
            ? nil
            : Double(delayValues.reduce(0, +)) / Double(delayValues.count)
    }
}

extension ExchangeRecord {
    var timingDescription: String {
        switch timing {
        case .onTime:
            return timing.rawValue
        case .late, .early:
            if let minutesOffset {
                return "\(timing.rawValue) by about \(minutesOffset) minute\(minutesOffset == 1 ? "" : "s")"
            }
            return timing.rawValue
        }
    }

    var coordinateDescription: String {
        guard let latitude, let longitude else {
            return "Not captured"
        }

        return String(format: "%.5f, %.5f", latitude, longitude)
    }

    func incidentDraft() -> IncidentDraft {
        var draft = IncidentDraft()
        draft.exchangeRecordID = id
        draft.incidentDate = exchangeDate
        draft.category = .exchange
        draft.location = address
        draft.peopleInvolved = role.rawValue
        draft.childInvolved = true
        draft.patternTags = timing == .late ? [.lateExchange] : []
        draft.originalNotes = """
        Exchange record captured at \(DateFormatter.factTrailDateTime.string(from: exchangeDate)).
        Role: \(role.rawValue)
        Timing: \(timingDescription)
        Address: \(address.isEmpty ? "Not captured" : address)
        GPS: \(coordinateDescription)
        Time Zone: \(timeZoneIdentifier)

        I've already documented the basic exchange information. Tell me what happened during the exchange.
        """
        return draft
    }
}
