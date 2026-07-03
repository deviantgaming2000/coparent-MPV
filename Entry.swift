import Foundation

struct Entry: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var eventAt: Date?
    var eventTimeConfirmed: Bool
    let category: EntryCategory
    var bodyText: String
    var attachments: [EntryAttachment]
    var isFlagged: Bool
    var tags: [EntryTag]
    var editHistory: [EditRecord]

    var isLocked: Bool {
        Date().timeIntervalSince(createdAt) > Self.lockWindowSeconds
    }

    static let lockWindowSeconds: TimeInterval = 300

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        eventAt: Date? = nil,
        eventTimeConfirmed: Bool = false,
        category: EntryCategory,
        bodyText: String,
        attachments: [EntryAttachment] = [],
        isFlagged: Bool = false,
        tags: [EntryTag] = [],
        editHistory: [EditRecord] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.eventAt = eventAt
        self.eventTimeConfirmed = eventTimeConfirmed
        self.category = category
        self.bodyText = bodyText
        self.attachments = attachments
        self.isFlagged = isFlagged
        self.tags = tags
        self.editHistory = editHistory
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case eventAt
        case eventTimeConfirmed
        case category
        case bodyText
        case attachments
        case isFlagged
        case tags
        case editHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        eventAt = try container.decodeIfPresent(Date.self, forKey: .eventAt)
        eventTimeConfirmed = try container.decodeIfPresent(Bool.self, forKey: .eventTimeConfirmed) ?? false
        category = try container.decode(EntryCategory.self, forKey: .category)
        bodyText = try container.decode(String.self, forKey: .bodyText)
        attachments = try container.decodeIfPresent([EntryAttachment].self, forKey: .attachments) ?? []
        isFlagged = try container.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
        tags = try container.decodeIfPresent([EntryTag].self, forKey: .tags) ?? []
        editHistory = try container.decodeIfPresent([EditRecord].self, forKey: .editHistory) ?? []
    }
}

struct EntryTag: Codable, Hashable, Identifiable {
    let category: TagCategory
    let value: TagValue

    var id: String {
        "\(category.rawValue):\(value.rawValue)"
    }

    var displayName: String {
        value.displayName
    }
}

enum TagCategory: String, Codable, CaseIterable {
    case timing
    case communication
    case compliance
    case consistencyOfCare
}

enum TagValue: String, Codable, CaseIterable {
    case lateArrival
    case earlyArrival
    case missedExchange
    case noShow
    case scheduleChange
    case repeatedDelay
    case unansweredMessage
    case delayedResponse
    case hostileCommunication
    case noPriorNotice
    case refusalToCommunicate
    case authorizationRefused
    case unsignedForm
    case courtOrderConcern
    case deniedAccess
    case missedRequirement
    case missedAppointment
    case therapyConcern
    case medicationConcern
    case schoolConcern
    case medicalCareConcern

    var displayName: String {
        switch self {
        case .lateArrival:
            return "Late arrival"
        case .earlyArrival:
            return "Early arrival"
        case .missedExchange:
            return "Missed exchange"
        case .noShow:
            return "No show"
        case .scheduleChange:
            return "Schedule change"
        case .repeatedDelay:
            return "Repeated delay"
        case .unansweredMessage:
            return "Unanswered message"
        case .delayedResponse:
            return "Delayed response"
        case .hostileCommunication:
            return "Hostile communication"
        case .noPriorNotice:
            return "No prior notice"
        case .refusalToCommunicate:
            return "Refusal to communicate"
        case .authorizationRefused:
            return "Authorization refused"
        case .unsignedForm:
            return "Unsigned form"
        case .courtOrderConcern:
            return "Court order concern"
        case .deniedAccess:
            return "Denied access"
        case .missedRequirement:
            return "Missed requirement"
        case .missedAppointment:
            return "Missed appointment"
        case .therapyConcern:
            return "Therapy"
        case .medicationConcern:
            return "Medication"
        case .schoolConcern:
            return "School"
        case .medicalCareConcern:
            return "Medical care"
        }
    }
}

enum EntryTagger {
    static func tags(for text: String) -> [EntryTag] {
        let normalized = text.lowercased()
        var tags: [EntryTag] = []

        func add(_ category: TagCategory, _ value: TagValue) {
            let tag = EntryTag(category: category, value: value)
            guard !tags.contains(tag), tags.count < 3 else {
                return
            }
            tags.append(tag)
        }

        if normalized.containsAny(["minutes late", "late", "delayed", "arrived at"]) {
            add(.timing, .lateArrival)
        }
        if normalized.containsAny(["early", "arrived early"]) {
            add(.timing, .earlyArrival)
        }
        if normalized.containsAny(["missed exchange", "missed pickup", "missed drop-off", "no show", "no-show"]) {
            add(.timing, .missedExchange)
        }
        if normalized.containsAny(["schedule change", "changed the schedule", "reschedule"]) {
            add(.timing, .scheduleChange)
        }
        if normalized.containsAny(["again", "repeated", "another time", "fourth", "third"]) {
            add(.timing, .repeatedDelay)
        }
        if normalized.containsAny(["no notice", "without notice", "no prior notice", "didn't tell me", "did not tell me"]) {
            add(.communication, .noPriorNotice)
        }
        if normalized.containsAny(["unanswered", "ignored", "no response", "didn't respond", "did not respond"]) {
            add(.communication, .unansweredMessage)
        }
        if normalized.containsAny(["hostile", "threat", "yelled", "insult"]) {
            add(.communication, .hostileCommunication)
        }
        if normalized.containsAny(["refused", "declined", "wouldn't sign", "would not sign", "authorization"]) {
            add(.compliance, .authorizationRefused)
        }
        if normalized.containsAny(["unsigned", "not signed", "signature"]) {
            add(.compliance, .unsignedForm)
        }
        if normalized.containsAny(["court order", "custody order", "order violation"]) {
            add(.compliance, .courtOrderConcern)
        }
        if normalized.containsAny(["denied access", "wouldn't allow", "would not allow"]) {
            add(.compliance, .deniedAccess)
        }
        if normalized.containsAny(["missed appointment", "missed doctor", "missed therapy"]) {
            add(.consistencyOfCare, .missedAppointment)
        }
        if normalized.contains("therapy") {
            add(.consistencyOfCare, .therapyConcern)
        }
        if normalized.contains("medication") || normalized.contains("medicine") {
            add(.consistencyOfCare, .medicationConcern)
        }
        if normalized.contains("school") || normalized.contains("teacher") {
            add(.consistencyOfCare, .schoolConcern)
        }
        if normalized.contains("doctor") || normalized.contains("medical") {
            add(.consistencyOfCare, .medicalCareConcern)
        }

        return Array(tags.prefix(3))
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}

enum EntryCategory: String, CaseIterable, Identifiable, Codable {
    case incident
    case exchange
    case checkIn
    case document
    case communication
    case scheduling

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .incident:
            return "Incident"
        case .exchange:
            return "Exchange"
        case .checkIn:
            return "Check-in"
        case .document:
            return "Document"
        case .communication:
            return "Communication"
        case .scheduling:
            return "Scheduling"
        }
    }
}

struct EntryAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date
}

struct EditRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let previousText: String
    let newText: String
    let fieldChanged: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        previousText: String,
        newText: String,
        fieldChanged: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.previousText = previousText
        self.newText = newText
        self.fieldChanged = fieldChanged
    }
}

extension Entry {
    func updatedBodyText(_ newText: String) -> Entry? {
        guard !isLocked else {
            return nil
        }

        var updated = self
        updated.editHistory.append(
            EditRecord(
                previousText: bodyText,
                newText: newText,
                fieldChanged: "bodyText"
            )
        )
        updated.bodyText = newText
        return updated
    }

    func updatedEventAt(_ newDate: Date?, confirmed: Bool) -> Entry? {
        guard !isLocked else {
            return nil
        }

        var updated = self
        updated.editHistory.append(
            EditRecord(
                previousText: eventAt.map(DateFormatter.factTrailDateTime.string) ?? "Not set",
                newText: newDate.map(DateFormatter.factTrailDateTime.string) ?? "Not set",
                fieldChanged: "eventAt"
            )
        )
        updated.eventAt = newDate
        updated.eventTimeConfirmed = confirmed
        return updated
    }
}
