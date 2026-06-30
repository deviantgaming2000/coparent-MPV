import Foundation

enum IncidentCategory: String, CaseIterable, Identifiable, Codable {
    case exchange = "Exchange"
    case communication = "Communication"
    case school = "School"
    case medical = "Medical"
    case schedule = "Schedule"
    case financial = "Financial"
    case safety = "Safety"
    case childWellbeing = "Child Wellbeing"
    case other = "Other"

    var id: String { rawValue }
}

struct Incident: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let incidentDate: Date
    let category: String
    let originalNotes: String
    let neutralSummary: String
    let peopleInvolved: String
    let location: String
    let childInvolved: Bool
    let evidenceNotes: String
    let evidenceAttachments: [EvidenceAttachment]
    let followUpQuestions: [String]

    init(
        id: UUID,
        createdAt: Date,
        incidentDate: Date,
        category: String,
        originalNotes: String,
        neutralSummary: String,
        peopleInvolved: String,
        location: String,
        childInvolved: Bool,
        evidenceNotes: String,
        evidenceAttachments: [EvidenceAttachment],
        followUpQuestions: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.incidentDate = incidentDate
        self.category = category
        self.originalNotes = originalNotes
        self.neutralSummary = neutralSummary
        self.peopleInvolved = peopleInvolved
        self.location = location
        self.childInvolved = childInvolved
        self.evidenceNotes = evidenceNotes
        self.evidenceAttachments = evidenceAttachments
        self.followUpQuestions = followUpQuestions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        incidentDate = try container.decode(Date.self, forKey: .incidentDate)
        category = try container.decode(String.self, forKey: .category)
        originalNotes = try container.decode(String.self, forKey: .originalNotes)
        neutralSummary = try container.decode(String.self, forKey: .neutralSummary)
        peopleInvolved = try container.decode(String.self, forKey: .peopleInvolved)
        location = try container.decode(String.self, forKey: .location)
        childInvolved = try container.decode(Bool.self, forKey: .childInvolved)
        evidenceNotes = try container.decode(String.self, forKey: .evidenceNotes)
        evidenceAttachments = try container.decodeIfPresent([EvidenceAttachment].self, forKey: .evidenceAttachments) ?? []
        followUpQuestions = try container.decode([String].self, forKey: .followUpQuestions)
    }
}

struct EvidenceAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let data: Data
}

struct IncidentDraft: Equatable {
    var originalNotes = ""
    var incidentDate = Date()
    var peopleInvolved = ""
    var location = ""
    var childInvolved = false
    var evidenceNotes = ""
    var evidenceAttachments: [EvidenceAttachment] = []
    var category: IncidentCategory = .exchange

    var canCreateSummary: Bool {
        !originalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct IncidentSummaryDraft: Equatable {
    let draft: IncidentDraft
    let neutralSummary: String
    let followUpQuestions: [String]

    var incident: Incident {
        Incident(
            id: UUID(),
            createdAt: Date(),
            incidentDate: draft.incidentDate,
            category: draft.category.rawValue,
            originalNotes: draft.originalNotes,
            neutralSummary: neutralSummary,
            peopleInvolved: draft.peopleInvolved,
            location: draft.location,
            childInvolved: draft.childInvolved,
            evidenceNotes: draft.evidenceNotes,
            evidenceAttachments: draft.evidenceAttachments,
            followUpQuestions: followUpQuestions
        )
    }
}

enum NeutralSummaryGenerator {
    static let followUpQuestions = [
        "Is there any screenshot, text, call log, email, photo, or document that supports this?",
        "Was this a one-time issue or part of a pattern?",
        "Did this affect the child directly? If yes, how?",
        "Was anyone else present?"
    ]

    static func makeSummary(from draft: IncidentDraft) -> IncidentSummaryDraft {
        let summary = """
        Date/Time: \(DateFormatter.factTrailDateTime.string(from: draft.incidentDate))
        Category: \(draft.category.rawValue)
        People Involved: \(displayValue(draft.peopleInvolved))
        Location: \(displayValue(draft.location))
        Summary: \(displayValue(draft.originalNotes))
        Evidence Mentioned: \(displayValue(draft.evidenceNotes))
        Attachments: \(draft.evidenceAttachments.isEmpty ? "None" : "\(draft.evidenceAttachments.count) photo or screenshot attachment(s)")
        Child Involved: \(draft.childInvolved ? "Yes" : "No")
        """

        return IncidentSummaryDraft(
            draft: draft,
            neutralSummary: summary,
            followUpQuestions: followUpQuestions
        )
    }

    private static func displayValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not specified" : trimmed
    }
}

extension DateFormatter {
    static let factTrailDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
