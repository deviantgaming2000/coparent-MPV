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

enum EvidenceType: String, CaseIterable, Identifiable, Codable {
    case textMessages = "Text messages"
    case screenshots = "Screenshots"
    case emails = "Emails"
    case photos = "Photos"
    case callLogs = "Call logs"
    case schoolRecords = "School records"
    case medicalRecords = "Medical records"
    case exchangeRecords = "Exchange records"
    case other = "Other"

    var id: String { rawValue }
}

enum PatternTag: String, CaseIterable, Identifiable, Codable {
    case lateExchange = "late_exchange"
    case missedExchange = "missed_exchange"
    case earlyReturn = "early_return"
    case communicationIssue = "communication_issue"
    case schoolIssue = "school_issue"
    case medicalIssue = "medical_issue"
    case scheduleIssue = "schedule_issue"
    case financialIssue = "financial_issue"
    case safetyConcern = "safety_concern"
    case childWellbeing = "child_wellbeing"
    case evidenceAvailable = "evidence_available"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lateExchange:
            return "Late exchange"
        case .missedExchange:
            return "Missed exchange"
        case .earlyReturn:
            return "Early return"
        case .communicationIssue:
            return "Communication issue"
        case .schoolIssue:
            return "School issue"
        case .medicalIssue:
            return "Medical issue"
        case .scheduleIssue:
            return "Schedule issue"
        case .financialIssue:
            return "Financial issue"
        case .safetyConcern:
            return "Safety concern"
        case .childWellbeing:
            return "Child wellbeing"
        case .evidenceAvailable:
            return "Evidence available"
        }
    }
}

struct GuidedQuestionAnswer: Identifiable, Codable, Equatable {
    let id: UUID
    let question: String
    var answer: String
}

/// One entry in an incident's tamper-evident change history. Every change to an
/// entry after it's created is recorded here with the moment it happened, so the
/// record reads as a contemporaneous, court-reliable trail.
struct AuditEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let action: String

    init(id: UUID = UUID(), timestamp: Date = Date(), action: String) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
    }
}

struct Incident: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let incidentDate: Date
    let category: String
    /// True when the category was auto-suggested from the notes rather than chosen by
    /// the user, so the UI can label it "Suggested" instead of presenting it as a fact.
    let categoryWasSuggested: Bool
    let originalNotes: String
    let neutralSummary: String
    let peopleInvolved: String
    let location: String
    let childInvolved: Bool
    let evidenceNotes: String
    let evidenceAttachments: [EvidenceAttachment]
    let evidenceTypes: [EvidenceType]
    let guidedAnswers: [GuidedQuestionAnswer]
    let patternTags: [PatternTag]
    let followUpQuestions: [String]
    let aiAnalysis: AIIncidentAnalysis?
    let finalDocumentationSummary: String
    let documentationCompleteness: DocumentationCompleteness?
    let exchangeRecordID: UUID?
    let tags: [EntryTag]
    let auditLog: [AuditEntry]

    /// The window during which the original text can still be corrected. After this,
    /// the original description is immutable; only timestamped supplements can be added.
    static let lockWindow: TimeInterval = 5 * 60

    /// True once the original description is locked (5 minutes after creation).
    var isOriginalLocked: Bool {
        Date().timeIntervalSince(createdAt) > Incident.lockWindow
    }

    init(
        id: UUID,
        createdAt: Date,
        incidentDate: Date,
        category: String,
        categoryWasSuggested: Bool = false,
        originalNotes: String,
        neutralSummary: String,
        peopleInvolved: String,
        location: String,
        childInvolved: Bool,
        evidenceNotes: String,
        evidenceAttachments: [EvidenceAttachment],
        evidenceTypes: [EvidenceType],
        guidedAnswers: [GuidedQuestionAnswer],
        patternTags: [PatternTag],
        followUpQuestions: [String],
        aiAnalysis: AIIncidentAnalysis? = nil,
        finalDocumentationSummary: String = "",
        documentationCompleteness: DocumentationCompleteness? = nil,
        exchangeRecordID: UUID? = nil,
        tags: [EntryTag] = [],
        auditLog: [AuditEntry] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.incidentDate = incidentDate
        self.category = category
        self.categoryWasSuggested = categoryWasSuggested
        self.originalNotes = originalNotes
        self.neutralSummary = neutralSummary
        self.peopleInvolved = peopleInvolved
        self.location = location
        self.childInvolved = childInvolved
        self.evidenceNotes = evidenceNotes
        self.evidenceAttachments = evidenceAttachments
        self.evidenceTypes = evidenceTypes
        self.guidedAnswers = guidedAnswers
        self.patternTags = patternTags
        self.followUpQuestions = followUpQuestions
        self.aiAnalysis = aiAnalysis
        self.finalDocumentationSummary = finalDocumentationSummary
        self.documentationCompleteness = documentationCompleteness
        self.exchangeRecordID = exchangeRecordID
        self.tags = tags
        self.auditLog = auditLog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        incidentDate = try container.decode(Date.self, forKey: .incidentDate)
        category = try container.decode(String.self, forKey: .category)
        categoryWasSuggested = try container.decodeIfPresent(Bool.self, forKey: .categoryWasSuggested) ?? false
        originalNotes = try container.decode(String.self, forKey: .originalNotes)
        neutralSummary = try container.decode(String.self, forKey: .neutralSummary)
        peopleInvolved = try container.decode(String.self, forKey: .peopleInvolved)
        location = try container.decode(String.self, forKey: .location)
        childInvolved = try container.decode(Bool.self, forKey: .childInvolved)
        evidenceNotes = try container.decode(String.self, forKey: .evidenceNotes)
        evidenceAttachments = try container.decodeIfPresent([EvidenceAttachment].self, forKey: .evidenceAttachments) ?? []
        evidenceTypes = try container.decodeIfPresent([EvidenceType].self, forKey: .evidenceTypes) ?? []
        guidedAnswers = try container.decodeIfPresent([GuidedQuestionAnswer].self, forKey: .guidedAnswers) ?? []
        patternTags = try container.decodeIfPresent([PatternTag].self, forKey: .patternTags) ?? []
        followUpQuestions = try container.decode([String].self, forKey: .followUpQuestions)
        aiAnalysis = try container.decodeIfPresent(AIIncidentAnalysis.self, forKey: .aiAnalysis)
        finalDocumentationSummary = try container.decodeIfPresent(String.self, forKey: .finalDocumentationSummary) ?? ""
        documentationCompleteness = try container.decodeIfPresent(DocumentationCompleteness.self, forKey: .documentationCompleteness)
        exchangeRecordID = try container.decodeIfPresent(UUID.self, forKey: .exchangeRecordID)
        tags = try container.decodeIfPresent([EntryTag].self, forKey: .tags) ?? []
        auditLog = try container.decodeIfPresent([AuditEntry].self, forKey: .auditLog) ?? []
    }
}

extension Incident {
    /// The core specifics that turn a quick note into a useful record. Kept intentionally
    /// simple and field-based so the "Pick up where you left off" count responds directly
    /// to what the user edits — no stale AI score that could keep an entry flagged after
    /// they've added detail.
    var missingDetailFields: [String] {
        var missing: [String] = []
        if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("the location")
        }
        if peopleInvolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("who was involved")
        }
        if originalNotes.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
            missing.append("more about what happened")
        }
        return missing
    }

    /// True when the entry is thin enough to invite the user to strengthen it.
    var needsMoreDetail: Bool {
        missingDetailFields.count >= 2
    }

    /// A short, human prompt describing what would strengthen this entry.
    var detailSuggestion: String {
        let fields = missingDetailFields
        guard !fields.isEmpty else {
            return "Add a little more detail to strengthen this record."
        }
        return "Add \(ListFormatter.localizedString(byJoining: fields))."
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
    var neutralSummaryOverride = ""
    var evidenceAttachments: [EvidenceAttachment] = []
    var evidenceTypes: [EvidenceType] = []
    var guidedAnswers: [GuidedQuestionAnswer] = []
    var patternTags: [PatternTag] = []
    var tags: [EntryTag] = []
    var aiAnalysis: AIIncidentAnalysis?
    var finalDocumentation: FinalDocumentationSummary?
    var exchangeRecordID: UUID?
    // Default to a neutral category. Previously this defaulted to `.exchange`,
    // which mislabeled every entry as an "Exchange" even with no supporting data.
    var category: IncidentCategory = .other
    /// Set when the app fills the category from a suggestion; cleared when the user
    /// picks one themselves. Surfaces a "Suggested" label so an auto-pick is never
    /// mistaken for the user's own choice.
    var categoryWasSuggested = false

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
            categoryWasSuggested: draft.categoryWasSuggested,
            originalNotes: draft.originalNotes,
            neutralSummary: neutralSummary,
            peopleInvolved: draft.peopleInvolved,
            location: draft.location,
            childInvolved: draft.childInvolved,
            evidenceNotes: draft.evidenceNotes,
            evidenceAttachments: draft.evidenceAttachments,
            evidenceTypes: draft.evidenceTypes,
            guidedAnswers: draft.guidedAnswers,
            patternTags: draft.patternTags,
            followUpQuestions: followUpQuestions,
            aiAnalysis: draft.aiAnalysis,
            finalDocumentationSummary: draft.finalDocumentation?.summary ?? "",
            documentationCompleteness: draft.finalDocumentation?.completeness,
            exchangeRecordID: draft.exchangeRecordID,
            tags: draft.tags,
            auditLog: [AuditEntry(action: "Entry created")]
        )
    }
}

extension Incident {
    func withTags(_ newTags: [EntryTag]) -> Incident {
        Incident(
            id: id,
            createdAt: createdAt,
            incidentDate: incidentDate,
            category: category,
            categoryWasSuggested: categoryWasSuggested,
            originalNotes: originalNotes,
            neutralSummary: neutralSummary,
            peopleInvolved: peopleInvolved,
            location: location,
            childInvolved: childInvolved,
            evidenceNotes: evidenceNotes,
            evidenceAttachments: evidenceAttachments,
            evidenceTypes: evidenceTypes,
            guidedAnswers: guidedAnswers,
            patternTags: patternTags,
            followUpQuestions: followUpQuestions,
            aiAnalysis: aiAnalysis,
            finalDocumentationSummary: finalDocumentationSummary,
            documentationCompleteness: documentationCompleteness,
            exchangeRecordID: exchangeRecordID,
            tags: newTags,
            auditLog: auditLog
        )
    }

    var draft: IncidentDraft {
        var draft = IncidentDraft()
        draft.originalNotes = originalNotes
        draft.incidentDate = incidentDate
        draft.peopleInvolved = peopleInvolved
        draft.location = location
        draft.childInvolved = childInvolved
        draft.evidenceNotes = evidenceNotes
        draft.evidenceAttachments = evidenceAttachments
        draft.evidenceTypes = evidenceTypes
        draft.guidedAnswers = guidedAnswers
        draft.patternTags = patternTags
        draft.tags = tags
        draft.aiAnalysis = aiAnalysis
        draft.exchangeRecordID = exchangeRecordID
        if !finalDocumentationSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.neutralSummaryOverride = finalDocumentationSummary
            draft.finalDocumentation = FinalDocumentationSummary(
                summary: finalDocumentationSummary,
                completeness: documentationCompleteness ?? DocumentationCompletenessCalculator.calculate(draft: draft, analysis: aiAnalysis)
            )
        } else {
            draft.neutralSummaryOverride = neutralSummary
        }
        draft.category = IncidentCategory(rawValue: category) ?? .other
        draft.categoryWasSuggested = categoryWasSuggested
        return draft
    }

    func updated(from draft: IncidentDraft) -> Incident {
        let locked = isOriginalLocked

        // The original description is immutable after the lock window: keep the stored
        // text and summary regardless of what the draft carries.
        var effectiveDraft = draft
        if locked { effectiveDraft.originalNotes = originalNotes }
        let summaryDraft = NeutralSummaryGenerator.makeSummary(from: effectiveDraft)

        // Record every change with the moment it happened — never backdated.
        var newAudit = auditLog
        let now = Date()
        func log(_ action: String) { newAudit.append(AuditEntry(timestamp: now, action: action)) }

        if !locked && draft.originalNotes != originalNotes {
            log("Edited the original description")
        }
        if draft.peopleInvolved != peopleInvolved {
            log(peopleInvolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Added who was involved" : "Updated who was involved")
        }
        if draft.location != location {
            log(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Added a location" : "Updated the location")
        }
        if draft.childInvolved != childInvolved {
            log("Marked child involved: \(draft.childInvolved ? "Yes" : "No")")
        }
        if draft.category.rawValue != category {
            log("Set category to \(draft.category.rawValue)")
        }
        let addedAttachments = draft.evidenceAttachments.count - evidenceAttachments.count
        if addedAttachments > 0 {
            log("Added \(addedAttachments) attachment\(addedAttachments == 1 ? "" : "s")")
        }

        return Incident(
            id: id,
            createdAt: createdAt,
            incidentDate: draft.incidentDate,
            category: draft.category.rawValue,
            categoryWasSuggested: draft.categoryWasSuggested,
            originalNotes: effectiveDraft.originalNotes,
            neutralSummary: summaryDraft.neutralSummary,
            peopleInvolved: draft.peopleInvolved,
            location: draft.location,
            childInvolved: draft.childInvolved,
            evidenceNotes: draft.evidenceNotes,
            evidenceAttachments: draft.evidenceAttachments,
            evidenceTypes: draft.evidenceTypes,
            guidedAnswers: draft.guidedAnswers,
            patternTags: draft.patternTags,
            followUpQuestions: summaryDraft.followUpQuestions,
            aiAnalysis: draft.aiAnalysis,
            finalDocumentationSummary: draft.finalDocumentation?.summary ?? "",
            documentationCompleteness: draft.finalDocumentation?.completeness,
            exchangeRecordID: draft.exchangeRecordID,
            tags: draft.tags,
            auditLog: newAudit
        )
    }
}

enum NeutralSummaryGenerator {
    static let defaultFollowUpQuestions = [
        "Is there any screenshot, text, call log, email, photo, or document that supports this?",
        "Was this a one-time issue or part of a pattern?",
        "Did this affect the child directly? If yes, how?",
        "Was anyone else present?"
    ]

    static func followUpQuestions(for category: IncidentCategory) -> [String] {
        switch category {
        case .exchange:
            return [
                "What was the agreed exchange time and location?",
                "What time did each person arrive or leave?",
                "Who was present during the exchange?",
                "Were there any messages or records related to the exchange?"
            ]
        case .communication:
            return [
                "What communication method was used?",
                "What was the main topic of the communication?",
                "When did the communication occur?",
                "Is there a record of the communication?"
            ]
        case .school:
            return [
                "What school-related event or record is involved?",
                "Who from the school was involved or notified?",
                "What date or school period does this relate to?",
                "Are there emails, forms, attendance records, or other school records?"
            ]
        case .medical:
            return [
                "What medical appointment, concern, or record is involved?",
                "Who provided or received the medical information?",
                "What date did the appointment or communication occur?",
                "Are there visit notes, messages, prescriptions, or medical records?"
            ]
        case .schedule:
            return [
                "What was the agreed schedule or expectation?",
                "What date and time did the schedule issue occur?",
                "How was the schedule discussed or confirmed?",
                "Were any alternatives proposed or documented?"
            ]
        case .financial:
            return [
                "What expense, payment, or financial record is involved?",
                "What amount or document is relevant, if known?",
                "When was the expense or communication created?",
                "Are there receipts, invoices, statements, or messages?"
            ]
        case .safety:
            return [
                "What happened that raised a safety concern?",
                "Who was present or directly involved?",
                "Was anyone injured or in immediate danger?",
                "Are there photos, messages, reports, or witness notes?"
            ]
        case .childWellbeing:
            return [
                "What did you observe about the child's wellbeing?",
                "When and where did you observe it?",
                "Did the child say anything relevant in their own words?",
                "Were any caregivers, teachers, or professionals notified?"
            ]
        case .other:
            return [
                "What happened in neutral, factual terms?",
                "When and where did it occur?",
                "Who was involved or present?",
                "What records or evidence may help document it?"
            ]
        }
    }

    static func suggestedCategory(for notes: String) -> IncidentCategory {
        let text = notes.lowercased()

        if text.contains("school") || text.contains("teacher") || text.contains("attendance") {
            return .school
        }

        if text.contains("doctor") || text.contains("medical") || text.contains("appointment") || text.contains("medicine") {
            return .medical
        }

        if text.contains("paid") || text.contains("payment") || text.contains("receipt") || text.contains("expense") {
            return .financial
        }

        if text.contains("late") || text.contains("exchange") || text.contains("pickup") || text.contains("drop off") {
            return .exchange
        }

        if text.contains("text") || text.contains("call") || text.contains("email") || text.contains("message") {
            return .communication
        }

        if text.contains("schedule") || text.contains("time") || text.contains("date") {
            return .schedule
        }

        if text.contains("safe") || text.contains("danger") || text.contains("injury") || text.contains("threat") {
            return .safety
        }

        if text.contains("child") || text.contains("upset") || text.contains("wellbeing") {
            return .childWellbeing
        }

        return .other
    }

    static func suggestedPatternTags(for draft: IncidentDraft) -> [PatternTag] {
        var tags = Set<PatternTag>()
        let text = [
            draft.originalNotes,
            draft.evidenceNotes,
            draft.guidedAnswers.map(\.answer).joined(separator: " ")
        ].joined(separator: " ").lowercased()

        switch draft.category {
        case .communication:
            tags.insert(.communicationIssue)
        case .school:
            tags.insert(.schoolIssue)
        case .medical:
            tags.insert(.medicalIssue)
        case .schedule:
            tags.insert(.scheduleIssue)
        case .financial:
            tags.insert(.financialIssue)
        case .safety:
            tags.insert(.safetyConcern)
        case .childWellbeing:
            tags.insert(.childWellbeing)
        default:
            break
        }

        if text.contains("late") {
            tags.insert(.lateExchange)
        }

        if text.contains("missed") || text.contains("no show") || text.contains("did not arrive") {
            tags.insert(.missedExchange)
        }

        if text.contains("early") {
            tags.insert(.earlyReturn)
        }

        if !draft.evidenceNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.evidenceAttachments.isEmpty
            || !draft.evidenceTypes.isEmpty {
            tags.insert(.evidenceAvailable)
        }

        return PatternTag.allCases.filter { tags.contains($0) }
    }

    static func makeSummary(from draft: IncidentDraft) -> IncidentSummaryDraft {
        let answeredQuestions = draft.guidedAnswers.filter {
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let guidedResponseText = answeredQuestions.isEmpty
            ? "None"
            : answeredQuestions.map { "\($0.question) \($0.answer)" }.joined(separator: "\n")
        let evidenceTypeText = draft.evidenceTypes.isEmpty
            ? "Not specified"
            : draft.evidenceTypes.map(\.rawValue).joined(separator: ", ")
        let patternTagText = draft.patternTags.isEmpty
            ? "None"
            : draft.patternTags.map(\.displayName).joined(separator: ", ")
        let generatedSummary = """
        Date/Time: \(DateFormatter.factTrailDateTime.string(from: draft.incidentDate))
        Category: \(draft.category.rawValue)
        People Involved: \(displayValue(draft.peopleInvolved))
        Location: \(displayValue(draft.location))
        Summary: \(displayValue(draft.originalNotes))
        Evidence Mentioned: \(displayValue(draft.evidenceNotes))
        Evidence Types: \(evidenceTypeText)
        Attachments: \(draft.evidenceAttachments.isEmpty ? "None" : "\(draft.evidenceAttachments.count) photo or screenshot attachment(s)")
        Guided Responses:
        \(guidedResponseText)
        Pattern Tags: \(patternTagText)
        Child Involved: \(draft.childInvolved ? "Yes" : "No")
        """
        let editedSummary = draft.neutralSummaryOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSummary = draft.finalDocumentation?.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        return IncidentSummaryDraft(
            draft: draft,
            neutralSummary: finalSummary?.isEmpty == false ? draft.finalDocumentation?.summary ?? generatedSummary : (editedSummary.isEmpty ? generatedSummary : draft.neutralSummaryOverride),
            followUpQuestions: draft.guidedAnswers.isEmpty
                ? followUpQuestions(for: draft.category)
                : draft.guidedAnswers.map(\.question)
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

    static let factTrailWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    static let factTrailCompactDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    static let factTrailTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static let factTrailMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    static let factTrailWeekdayMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
}
