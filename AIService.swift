import Foundation

enum FollowUpPriority: String, Codable, CaseIterable, Equatable {
    case high = "High"
    case helpfulContext = "Helpful Context"
    case optional = "Optional"
}

struct AIFollowUpQuestion: Identifiable, Codable, Equatable {
    let id: UUID
    let priority: FollowUpPriority
    let question: String
    let whyItMatters: String

    init(
        id: UUID = UUID(),
        priority: FollowUpPriority,
        question: String,
        whyItMatters: String
    ) {
        self.id = id
        self.priority = priority
        self.question = question
        self.whyItMatters = whyItMatters
    }
}

struct AIAnalysisDebugSnapshot: Codable, Equatable {
    let structuredFacts: [String]
    let detectedEntities: [String]
    let detectedEventType: String
    let detectedCategory: String
    let categoryConfidence: String
    let evidenceDetected: [String]
    let missingFacts: [String]
    let generatedQuestions: [String]
    let patternTags: [String]
}

struct AIIncidentAnalysis: Codable, Equatable {
    let understandingSummary: [String]
    let suggestedCategory: IncidentCategory
    let categoryReason: String
    let neutralSummary: String
    let missingInformation: [String]
    let evidenceMentioned: [String]
    let patternTags: [PatternTag]
    let followUpQuestions: [AIFollowUpQuestion]
    let disclaimer: String
    let debugSnapshot: AIAnalysisDebugSnapshot?
}

typealias AISuggestion = AIIncidentAnalysis

protocol AIService {
    func analyzeIncident(draft: IncidentDraft) async throws -> AIIncidentAnalysis
    func generateFinalDocumentation(draft: IncidentDraft, analysis: AIIncidentAnalysis?) async throws -> FinalDocumentationSummary
    /// Analyze the whole timeline for recurring patterns (Insights + spine annotations).
    func analyzeTimeline(entries: [TimelineEntryInput]) async throws -> TimelineAnalysis
}

extension AIService {
    // Default: local, on-device heuristic engine. The backend service overrides this
    // with an LLM call once a provider is configured.
    func analyzeTimeline(entries: [TimelineEntryInput]) async throws -> TimelineAnalysis {
        TimelineInsightEngine.analyze(entries: entries)
    }
}

// MARK: - Timeline insights domain (Color-free; the UI layer maps type/kind -> color)

enum InsightType: Equatable {
    case concern, affirm
}

/// Semantic entry category — the UI maps this to the timeline color palette.
enum EntryKind: String, Equatable {
    case entry, checkin, exchange, document, flag
}

enum InsightVisual: Equatable {
    case strip(dates: [String])
    case tally(values: [Int], labels: [String])
    case none
}

struct InsightSupport: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: String
    let kind: EntryKind
}

struct Insight: Identifiable, Equatable {
    let id = UUID()
    let type: InsightType
    let visual: InsightVisual
    let iconSystemName: String
    let eyebrow: String
    let headline: String
    let body: String
    let tag: String
    let firstSeen: String
    let lastSeen: String
    let occurrences: Int
    let supporting: [InsightSupport]
}

/// An AI-generated pattern marker rendered between entries on the branch spine
/// (the amber "Pattern of ... begins here" flag).
struct TimelineAnnotation: Identifiable, Hashable {
    let id: UUID
    let text: String
    /// Chronological position — the annotation renders after entries dated before this.
    let anchorDate: Date

    init(id: UUID = UUID(), text: String, anchorDate: Date) {
        self.id = id
        self.text = text
        self.anchorDate = anchorDate
    }
}

/// Neutral representation of one timeline entry, decoupled from the UI's TimelineItem.
struct TimelineEntryInput {
    let id: String
    let date: Date
    let kind: EntryKind
    let title: String
    let text: String
    let tags: [String]
    let flagged: Bool
    let location: String
}

struct TimelineAnalysis {
    let insights: [Insight]
    let annotations: [TimelineAnnotation]
}

/// On-device heuristic pattern detection. Produces genuinely data-driven insights
/// from the user's real entries — recurring tags, flagged clusters, and check-in
/// consistency. Intentionally conservative: returns nothing when there isn't a real
/// pattern, so the screen honestly shows the empty state until enough is logged.
enum TimelineInsightEngine {
    static func analyze(entries: [TimelineEntryInput]) -> TimelineAnalysis {
        guard entries.count >= 2 else {
            return TimelineAnalysis(insights: [], annotations: [])
        }

        let sorted = entries.sorted { $0.date < $1.date }
        let shortDate = DateFormatter()
        shortDate.dateFormat = "MMM d"

        var insights: [Insight] = []
        var annotations: [TimelineAnnotation] = []

        // 1) Recurring tags (>= 3 occurrences of the same tag).
        var tagBuckets: [String: [TimelineEntryInput]] = [:]
        for entry in sorted {
            for tag in entry.tags where !tag.trimmingCharacters(in: .whitespaces).isEmpty {
                tagBuckets[tag, default: []].append(entry)
            }
        }
        for (tag, group) in tagBuckets.sorted(by: { $0.value.count > $1.value.count }) where group.count >= 3 {
            let first = group.first!.date
            let last = group.last!.date
            insights.append(
                Insight(
                    type: .concern,
                    visual: .tally(values: monthlyCounts(group, endingAt: last, months: 6),
                                   labels: monthLabels(endingAt: last, count: 6)),
                    iconSystemName: "chart.bar",
                    eyebrow: "Recurring pattern",
                    headline: "\(tag) keeps coming up",
                    body: "\"\(tag)\" appears across \(group.count) entries between \(shortDate.string(from: first)) and \(shortDate.string(from: last)).",
                    tag: tag,
                    firstSeen: shortDate.string(from: first),
                    lastSeen: shortDate.string(from: last),
                    occurrences: group.count,
                    supporting: group.suffix(3).reversed().map {
                        InsightSupport(text: $0.title, date: shortDate.string(from: $0.date), kind: $0.kind)
                    }
                )
            )
            annotations.append(
                TimelineAnnotation(text: "Pattern of \(tag.lowercased()) begins here", anchorDate: first)
            )
            // Mark where the pattern was most recently noted too, so both the start and
            // the latest occurrence are visible on the timeline.
            if last > first {
                annotations.append(
                    TimelineAnnotation(text: "Pattern of \(tag.lowercased()) last noted here", anchorDate: last)
                )
            }
        }

        // Flagged entries are intentionally NOT aggregated into a single "flagged
        // incidents are adding up" insight — a flag is a property of an individual
        // entry, and lumping unrelated flags together implies a pattern that may not
        // exist. Each flagged entry stands alone in the timeline instead.

        // 2) Check-in consistency this month (affirming, >= 3).
        let calendar = Calendar.current
        let checkIns = sorted.filter { $0.kind == .checkin }
        let now = Date()
        let thisMonth = checkIns.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
        if thisMonth.count >= 3 {
            insights.append(
                Insight(
                    type: .affirm,
                    visual: .none,
                    iconSystemName: "checkmark.seal",
                    eyebrow: "Your consistency",
                    headline: "You've logged \(thisMonth.count) check-ins this month",
                    body: "You've consistently recorded your handoffs and appointments this month, keeping a clear, contemporaneous record.",
                    tag: "checkin_consistency",
                    firstSeen: shortDate.string(from: thisMonth.first!.date),
                    lastSeen: shortDate.string(from: thisMonth.last!.date),
                    occurrences: thisMonth.count,
                    supporting: thisMonth.suffix(3).reversed().map {
                        InsightSupport(text: $0.title, date: shortDate.string(from: $0.date), kind: .checkin)
                    }
                )
            )
        }

        // Concern-first, capped.
        insights.sort { ($0.type == .concern ? 0 : 1) < ($1.type == .concern ? 0 : 1) }
        return TimelineAnalysis(insights: Array(insights.prefix(6)), annotations: annotations)
    }

    private static func startOfMonth(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func monthLabels(endingAt end: Date, count: Int) -> [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        var labels: [String] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            if let date = calendar.date(byAdding: .month, value: -offset, to: end) {
                labels.append(formatter.string(from: date))
            }
        }
        return labels
    }

    private static func monthlyCounts(_ entries: [TimelineEntryInput], endingAt end: Date, months: Int) -> [Int] {
        let calendar = Calendar.current
        let endMonth = startOfMonth(end, calendar)
        var counts = Array(repeating: 0, count: months)
        for entry in entries {
            let entryMonth = startOfMonth(entry.date, calendar)
            let diff = calendar.dateComponents([.month], from: entryMonth, to: endMonth).month ?? -1
            let index = months - 1 - diff
            if index >= 0 && index < months {
                counts[index] += 1
            }
        }
        return counts
    }
}

private struct InternalIncidentAnalysis {
    let incidentText: String
    let eventType: String
    let primaryTopic: String
    let secondaryTopic: String?
    let timelineFacts: [String]
    let people: [String]
    let childImpact: String?
    let evidenceMentioned: [String]
    let knownFacts: [String]
    let missingFacts: [MissingFact]
    let patternTags: [PatternTag]
    let suggestedCategory: IncidentCategory
    let categoryConfidence: String
}

private struct MissingFact: Identifiable, Equatable {
    let id: String
    let label: String
    let priority: FollowUpPriority
    let question: String
    let whyItMatters: String
}

struct MockAIService: AIService {
    func analyzeIncident(draft: IncidentDraft) async -> AIIncidentAnalysis {
        let incidentText = freshInputText(from: draft)
        let internalAnalysis = makeInternalAnalysis(from: draft, incidentText: incidentText)
        let questions = internalAnalysis.missingFacts.map {
            AIFollowUpQuestion(
                priority: $0.priority,
                question: $0.question,
                whyItMatters: $0.whyItMatters
            )
        }
        let analysis = AIIncidentAnalysis(
            understandingSummary: understandingSummary(from: internalAnalysis),
            suggestedCategory: internalAnalysis.suggestedCategory,
            categoryReason: categoryReason(from: internalAnalysis),
            neutralSummary: neutralSummary(from: draft, internalAnalysis: internalAnalysis),
            missingInformation: internalAnalysis.missingFacts.map(\.label),
            evidenceMentioned: internalAnalysis.evidenceMentioned,
            patternTags: internalAnalysis.patternTags,
            followUpQuestions: questions,
            disclaimer: "This is not legal advice. This is only for documentation and organization.",
            debugSnapshot: AIAnalysisDebugSnapshot(
                structuredFacts: internalAnalysis.knownFacts,
                detectedEntities: internalAnalysis.people,
                detectedEventType: internalAnalysis.eventType,
                detectedCategory: internalAnalysis.suggestedCategory.rawValue,
                categoryConfidence: internalAnalysis.categoryConfidence,
                evidenceDetected: internalAnalysis.evidenceMentioned,
                missingFacts: internalAnalysis.missingFacts.map(\.label),
                generatedQuestions: questions.map(\.question),
                patternTags: internalAnalysis.patternTags.map(\.rawValue)
            )
        )

        logAnalysisStart(incidentText: incidentText, internalAnalysis: internalAnalysis, analysis: analysis)
        return analysis
    }

    func generateFinalDocumentation(draft: IncidentDraft, analysis: AIIncidentAnalysis?) async throws -> FinalDocumentationSummary {
        var summaryDraft = draft
        if let analysis {
            summaryDraft.aiAnalysis = analysis
            // Only fill in a suggested category when the user left it at the neutral
            // default — an explicit choice must never be silently overwritten.
            if draft.category == .other {
                summaryDraft.category = analysis.suggestedCategory
                summaryDraft.categoryWasSuggested = true
            }
            summaryDraft.patternTags = analysis.patternTags
        }

        let summary = buildFinalSummary(from: summaryDraft, analysis: analysis)
        summaryDraft.finalDocumentation = FinalDocumentationSummary(
            summary: summary,
            completeness: DocumentationCompleteness(score: 0, completedItems: [], missingItems: [])
        )
        let completeness = DocumentationCompletenessCalculator.calculate(draft: summaryDraft, analysis: analysis)

        let finalDocumentation = FinalDocumentationSummary(summary: summary, completeness: completeness)
        AIDebugLogger.log("MockAIService final documentation", summary)
        AIDebugLogger.log("MockAIService completeness", "\(completeness.score)% \(completeness.status)")
        return finalDocumentation
    }

    private func freshInputText(from draft: IncidentDraft) -> String {
        [
            draft.originalNotes,
            draft.peopleInvolved,
            draft.location,
            draft.evidenceNotes,
            draft.evidenceTypes.map(\.rawValue).joined(separator: " ")
        ]
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeInternalAnalysis(from draft: IncidentDraft, incidentText: String) -> InternalIncidentAnalysis {
        let lower = incidentText.lowercased()
        let category = suggestedCategory(from: lower)
        let evidence = evidenceMentioned(in: draft, text: lower)
        let people = detectedPeople(from: draft, text: lower)
        let timelineFacts = detectedTimelineFacts(from: incidentText)
        let eventType = detectedEventType(category: category, text: lower)
        let childImpact = detectedChildImpact(from: lower)
        let patternTags = patternTags(from: lower, category: category, evidence: evidence)
        let knownFacts = knownFactsForDebug(
            eventType: eventType,
            timelineFacts: timelineFacts,
            people: people,
            childImpact: childImpact,
            evidence: evidence,
            patternTags: patternTags
        )
        let missingFacts = missingFactsForQuestions(
            draft: draft,
            text: lower,
            category: category,
            timelineFacts: timelineFacts,
            people: people,
            childImpact: childImpact,
            evidence: evidence
        )

        return InternalIncidentAnalysis(
            incidentText: incidentText,
            eventType: eventType,
            primaryTopic: category.rawValue,
            secondaryTopic: secondaryTopic(from: lower),
            timelineFacts: timelineFacts,
            people: people,
            childImpact: childImpact,
            evidenceMentioned: evidence,
            knownFacts: knownFacts,
            missingFacts: Array(missingFacts.prefix(6)),
            patternTags: patternTags,
            suggestedCategory: category,
            categoryConfidence: categoryConfidence(category: category, text: lower)
        )
    }

    private func suggestedCategory(from text: String) -> IncidentCategory {
        if text.contains("doctor") || text.contains("medical") || text.contains("appointment") || text.contains("medicine") || text.contains("clinic") || text.contains("hospital") {
            return .medical
        }

        if text.contains("school") || text.contains("teacher") || text.contains("principal") || text.contains("assignment") || text.contains("attendance") || text.contains("permission slip") {
            return .school
        }

        if text.contains("paid") || text.contains("payment") || text.contains("receipt") || text.contains("expense") || text.contains("invoice") {
            return .financial
        }

        if text.contains("exchange") || text.contains("pickup") || text.contains("drop off") || text.contains("drop-off") || text.contains("handoff") {
            return .exchange
        }

        if text.contains("text") || text.contains("call") || text.contains("email") || text.contains("message") || text.contains("communication") {
            return .communication
        }

        if text.contains("schedule") || text.contains("scheduled") || text.contains("supposed to") || text.contains("agreed time") {
            return .schedule
        }

        if text.contains("safe") || text.contains("danger") || text.contains("injury") || text.contains("threat") {
            return .safety
        }

        if text.contains("child") || text.contains("upset") || text.contains("wellbeing") || text.contains("waiting") {
            return .childWellbeing
        }

        return .other
    }

    private func detectedEventType(category: IncidentCategory, text: String) -> String {
        switch category {
        case .medical:
            if text.contains("missed") && text.contains("appointment") { return "Missed medical appointment" }
            if text.contains("medicine") || text.contains("medication") { return "Medical medication documentation" }
            return "Medical documentation"
        case .school:
            if text.contains("permission slip") { return "School permission or form issue" }
            if text.contains("assignment") { return "School assignment issue" }
            return "School communication or record issue"
        case .exchange:
            if text.contains("late") { return "Late exchange" }
            if text.contains("missed") || text.contains("no show") { return "Missed exchange" }
            return "Exchange documentation"
        case .communication:
            return "Communication documentation"
        case .schedule:
            return "Schedule documentation"
        case .financial:
            return "Financial documentation"
        case .safety:
            return "Safety-related documentation"
        case .childWellbeing:
            return "Child wellbeing observation"
        case .other:
            return "General documentation"
        }
    }

    private func secondaryTopic(from text: String) -> String? {
        if hasPatternLanguage(text) { return "Possible recurrence" }
        if mentionsEvidence(text) { return "Evidence available" }
        if text.contains("child") || text.contains("upset") || text.contains("waiting") { return "Child observation" }
        return nil
    }

    private func categoryConfidence(category: IncidentCategory, text: String) -> String {
        switch category {
        case .medical where text.contains("appointment") || text.contains("doctor") || text.contains("clinic"):
            return "High"
        case .school where text.contains("school") || text.contains("teacher") || text.contains("permission slip"):
            return "High"
        case .exchange where text.contains("exchange") || text.contains("pickup") || text.contains("drop off"):
            return "High"
        case .communication where text.contains("text") || text.contains("email") || text.contains("message"):
            return "Medium"
        default:
            return "Medium"
        }
    }

    private func detectedTimelineFacts(from text: String) -> [String] {
        var facts: [String] = []
        let lower = text.lowercased()

        for match in regexMatches(pattern: #"\b\d{1,2}:\d{2}\s?(?:am|pm|AM|PM)?\b"#, text: text) {
            facts.append("Time mentioned: \(match)")
        }

        for phrase in ["today", "yesterday", "three weeks", "few times", "multiple times", "before", "after"] where lower.contains(phrase) {
            facts.append("Timeline context mentioned: \(phrase)")
        }

        return unique(facts)
    }

    private func detectedPeople(from draft: IncidentDraft, text: String) -> [String] {
        var people: [String] = []
        if !draft.peopleInvolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            people.append(contentsOf: draft.peopleInvolved
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            )
        }
        if text.contains("other parent") { people.append("other parent") }
        if text.contains("child") { people.append("child") }
        if text.contains("teacher") { people.append("teacher") }
        if text.contains("doctor") || text.contains("clinic") { people.append("medical provider or clinic") }
        return unique(people)
    }

    private func detectedChildImpact(from text: String) -> String? {
        if text.contains("upset") { return "Child was described as upset" }
        if text.contains("waiting") { return "Child was described as waiting" }
        if text.contains("missed") && text.contains("appointment") { return "Possible child impact from a missed appointment" }
        if text.contains("field trip") { return "Possible child impact related to school participation" }
        return nil
    }

    private func evidenceMentioned(in draft: IncidentDraft, text: String) -> [String] {
        var evidence = Set<String>()
        if text.contains("text") || text.contains("message") { evidence.insert("text messages") }
        if text.contains("screenshot") { evidence.insert("screenshots") }
        if text.contains("email") { evidence.insert("emails") }
        if text.contains("photo") { evidence.insert("photos") }
        if text.contains("call log") || text.contains("phone log") { evidence.insert("call logs") }
        if text.contains("school record") || text.contains("attendance") { evidence.insert("school records") }
        if text.contains("medical record") || text.contains("doctor") || text.contains("clinic") { evidence.insert("medical records") }
        if !draft.evidenceNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { evidence.insert("evidence notes") }
        for evidenceType in draft.evidenceTypes { evidence.insert(evidenceType.rawValue.lowercased()) }
        if !draft.evidenceAttachments.isEmpty { evidence.insert("attached photos or screenshots") }
        return evidence.sorted()
    }

    private func patternTags(from text: String, category: IncidentCategory, evidence: [String]) -> [PatternTag] {
        var tags = Set<PatternTag>()

        switch category {
        case .communication:
            tags.insert(.communicationIssue)
        case .school:
            tags.insert(.schoolIssue)
            if text.contains("message") || text.contains("email") || text.contains("forgot") { tags.insert(.communicationIssue) }
        case .medical:
            tags.insert(.medicalIssue)
            if text.contains("missed") && text.contains("appointment") { tags.insert(.medicalIssue) }
            if text.contains("message") || text.contains("email") || text.contains("call") { tags.insert(.communicationIssue) }
        case .schedule:
            tags.insert(.scheduleIssue)
        case .financial:
            tags.insert(.financialIssue)
        case .safety:
            tags.insert(.safetyConcern)
        case .childWellbeing:
            tags.insert(.childWellbeing)
        case .exchange:
            if text.contains("late") { tags.insert(.lateExchange) }
            if text.contains("missed") || text.contains("no show") || text.contains("did not arrive") { tags.insert(.missedExchange) }
            if text.contains("early") { tags.insert(.earlyReturn) }
        case .other:
            break
        }

        if !evidence.isEmpty { tags.insert(.evidenceAvailable) }
        return PatternTag.allCases.filter { tags.contains($0) }
    }

    private func knownFactsForDebug(
        eventType: String,
        timelineFacts: [String],
        people: [String],
        childImpact: String?,
        evidence: [String],
        patternTags: [PatternTag]
    ) -> [String] {
        var facts = ["Event type: \(eventType)"]
        facts.append(contentsOf: timelineFacts)
        if !people.isEmpty { facts.append("People/entities: \(people.joined(separator: ", "))") }
        if let childImpact { facts.append("Child impact: \(childImpact)") }
        if !evidence.isEmpty { facts.append("Evidence: \(evidence.joined(separator: ", "))") }
        if !patternTags.isEmpty { facts.append("Pattern tags: \(patternTags.map(\.displayName).joined(separator: ", "))") }
        return facts
    }

    private func missingFactsForQuestions(
        draft: IncidentDraft,
        text: String,
        category: IncidentCategory,
        timelineFacts: [String],
        people: [String],
        childImpact: String?,
        evidence: [String]
    ) -> [MissingFact] {
        var missing: [MissingFact] = []

        if timelineFacts.isEmpty {
            missing.append(MissingFact(
                id: "time",
                label: "Specific date or time",
                priority: .high,
                question: "What date and time did this event happen or become known to you?",
                whyItMatters: "A clear timeline helps the documentation stay chronological and specific."
            ))
        }

        if people.isEmpty {
            missing.append(MissingFact(
                id: "people",
                label: "People involved",
                priority: .high,
                question: "Who was directly involved or contacted about this event?",
                whyItMatters: "Identifying people involved helps keep the record factual and understandable."
            ))
        }

        if draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasLocationClue(text) {
            missing.append(MissingFact(
                id: "location",
                label: "Location",
                priority: .helpfulContext,
                question: "Where did this event happen, or where was the relevant communication or appointment connected to?",
                whyItMatters: "Location can help distinguish this event from other similar records."
            ))
        }

        switch category {
        case .medical:
            if !text.contains("clinic") && !text.contains("doctor") && !text.contains("provider") && !text.contains("hospital") {
                missing.append(MissingFact(
                    id: "medical-provider",
                    label: "Clinic or provider name",
                    priority: .high,
                    question: "What clinic or medical provider was involved?",
                    whyItMatters: "The provider name connects the summary to the original medical record."
                ))
            }
            if !text.contains("treatment") && !text.contains("medication") && !text.contains("medicine") {
                missing.append(MissingFact(
                    id: "medical-impact",
                    label: "Treatment or medication impact",
                    priority: .helpfulContext,
                    question: "Did this affect any treatment, medication, or follow-up care that you know of?",
                    whyItMatters: "This documents observable impact without speculating."
                ))
            }
        case .school:
            if !text.contains("teacher") && !text.contains("principal") && !text.contains("school office") {
                missing.append(MissingFact(
                    id: "school-contact",
                    label: "School contact or record source",
                    priority: .high,
                    question: "Who from the school contacted you, or what school record is connected to this?",
                    whyItMatters: "This identifies the source of the school information."
                ))
            }
            if !text.contains("email") && !text.contains("form") && !text.contains("permission slip") && evidence.isEmpty {
                missing.append(MissingFact(
                    id: "school-evidence",
                    label: "School record evidence",
                    priority: .helpfulContext,
                    question: "Is there a school email, form, attendance note, or other record connected to this event?",
                    whyItMatters: "This helps preserve the original source document."
                ))
            }
        case .exchange:
            if !text.contains("agreed") && !text.contains("scheduled") && !text.contains("supposed to") {
                missing.append(MissingFact(
                    id: "agreed-exchange-time",
                    label: "Agreed exchange expectation",
                    priority: .high,
                    question: "What was the agreed exchange time and location?",
                    whyItMatters: "This documents the expected arrangement before describing what occurred."
                ))
            }
            if text.contains("late") && !text.contains("arrived") {
                missing.append(MissingFact(
                    id: "actual-arrival",
                    label: "Actual arrival time",
                    priority: .high,
                    question: "Approximately what time did each person actually arrive or leave?",
                    whyItMatters: "This documents the difference between the expected and actual timeline."
                ))
            }
        default:
            break
        }

        if (text.contains("child") || text.contains("upset") || draft.childInvolved) && childImpact == nil {
            missing.append(MissingFact(
                id: "child-observation",
                label: "Child observation",
                priority: .high,
                question: "What did you personally observe about the child, if anything?",
                whyItMatters: "Direct observations are more useful than conclusions."
            ))
        }

        if hasPatternLanguage(text) && !containsRecurrenceCount(text) {
            missing.append(MissingFact(
                id: "recurrence-count",
                label: "Approximate recurrence count",
                priority: .helpfulContext,
                question: "About how many previous times do you remember this happening?",
                whyItMatters: "This helps document whether the event may be isolated or recurring without needing exact dates yet."
            ))
        }

        if evidence.isEmpty {
            missing.append(MissingFact(
                id: "evidence",
                label: "Supporting records",
                priority: .helpfulContext,
                question: "Are there any messages, emails, photos, call logs, school records, medical records, or other records connected to this?",
                whyItMatters: "This helps preserve original records alongside the written summary."
            ))
        }

        if !text.contains("witness") && !text.contains("present") && !text.contains("teacher") && !text.contains("doctor") {
            missing.append(MissingFact(
                id: "witnesses",
                label: "Witness or observer information",
                priority: .optional,
                question: "Was anyone else present or directly aware of the event?",
                whyItMatters: "This can add context about who observed or communicated the information."
            ))
        }

        return uniqueMissingFacts(missing)
    }

    private func understandingSummary(from analysis: InternalIncidentAnalysis) -> [String] {
        var summary: [String] = []
        let text = analysis.incidentText.lowercased()

        switch analysis.suggestedCategory {
        case .medical:
            if text.contains("missed") && text.contains("appointment") {
                summary.append("You reported learning about a missed medical appointment or follow-up connected to the child.")
            } else {
                summary.append("You documented a medical-related event involving care, an appointment, or medical communication.")
            }
        case .school:
            if text.contains("permission slip") || text.contains("field trip") {
                summary.append("You reported a school communication issue involving a permission slip or field trip information.")
            } else {
                summary.append("You documented a school-related communication or record issue.")
            }
        case .exchange:
            if text.contains("late") {
                summary.append("You reported an exchange where the actual timing may have differed from the expected timing.")
            } else {
                summary.append("You documented an event related to a child exchange or handoff.")
            }
        case .communication:
            if !analysis.evidenceMentioned.isEmpty {
                summary.append("You described a communication-related issue involving records such as \(analysis.evidenceMentioned.joined(separator: ", ")).")
            } else {
                summary.append("You documented a communication-related issue involving information sharing, messages, calls, emails, or response timing.")
            }
        default:
            summary.append("You documented a parenting or co-parenting event that may benefit from clearer factual organization.")
        }

        if let timingSentence = userFacingTimelineSentence(from: analysis.timelineFacts, text: text) {
            summary.append(timingSentence)
        }
        if let peopleSentence = userFacingPeopleSentence(from: analysis.people) {
            summary.append(peopleSentence)
        }
        if let childImpact = userFacingChildImpactSentence(from: analysis.childImpact) {
            summary.append(childImpact)
        }
        if !analysis.evidenceMentioned.isEmpty && analysis.suggestedCategory != .communication {
            summary.append("You mentioned possible supporting records, including \(analysis.evidenceMentioned.joined(separator: ", ")).")
        }
        if hasPatternLanguage(text) {
            summary.append("You indicated this may have happened before or could be part of a recurring issue.")
        }

        return summary
    }

    private func categoryReason(from analysis: InternalIncidentAnalysis) -> String {
        switch analysis.suggestedCategory {
        case .communication:
            return "Communication was selected because the notes focus on information sharing or communication records. Confidence: \(analysis.categoryConfidence)."
        case .medical:
            return "Medical was selected because the notes reference a medical provider, appointment, treatment, medication, or medical record. Confidence: \(analysis.categoryConfidence)."
        case .school:
            return "School was selected because the notes reference school staff, school records, forms, assignments, attendance, or school communication. Confidence: \(analysis.categoryConfidence)."
        case .exchange:
            return "Exchange was selected because the notes reference a child exchange, pickup, drop-off, handoff, or arrival timing. Confidence: \(analysis.categoryConfidence)."
        case .schedule:
            return "Schedule was selected because the notes focus on an expected date, time, plan, or scheduling change. Confidence: \(analysis.categoryConfidence)."
        case .financial:
            return "Financial was selected because the notes reference an expense, payment, receipt, invoice, or financial record. Confidence: \(analysis.categoryConfidence)."
        case .safety:
            return "Safety was selected because the notes describe a safety-related concern or immediate risk. Confidence: \(analysis.categoryConfidence)."
        case .childWellbeing:
            return "Child Wellbeing was selected because the notes describe the child's observable condition, words, behavior, or experience. Confidence: \(analysis.categoryConfidence)."
        case .other:
            return "Other was selected because the notes do not clearly fit one of the more specific documentation categories. Confidence: \(analysis.categoryConfidence)."
        }
    }

    private func userFacingTimelineSentence(from timelineFacts: [String], text: String) -> String? {
        if text.contains("after") && (text.contains("missed") || text.contains("appointment")) {
            return "You reported learning about the issue after the appointment or event had already been missed."
        }

        if text.contains("three weeks") {
            return "You reported that the appointment or event had been scheduled approximately three weeks earlier."
        }

        if text.contains("today") {
            return "You described this as something that happened or became known today."
        }

        if let time = timelineFacts
            .compactMap({ fact -> String? in
                guard fact.hasPrefix("Time mentioned: ") else { return nil }
                return fact.replacingOccurrences(of: "Time mentioned: ", with: "")
            })
            .first {
            return "You mentioned a specific time: \(time)."
        }

        return nil
    }

    private func userFacingPeopleSentence(from people: [String]) -> String? {
        let cleanedPeople = people.filter {
            $0 != "child" && $0 != "other parent"
        }

        if people.contains("child") && people.contains("other parent") {
            return "The notes reference the child and the other parent."
        }

        if !cleanedPeople.isEmpty {
            return "The notes reference \(cleanedPeople.joined(separator: ", "))."
        }

        return nil
    }

    private func userFacingChildImpactSentence(from childImpact: String?) -> String? {
        guard let childImpact else {
            return nil
        }

        if childImpact.lowercased().contains("missed appointment") {
            return "The missed appointment may be relevant to the child's care, but the notes do not state the impact yet."
        }

        if childImpact.lowercased().contains("upset") {
            return "You reported observing that the child appeared upset."
        }

        if childImpact.lowercased().contains("waiting") {
            return "You reported that the child may have been waiting during part of the event."
        }

        return childImpact
    }

    private func neutralSummary(from draft: IncidentDraft, internalAnalysis: InternalIncidentAnalysis) -> String {
        let factText = internalAnalysis.knownFacts.isEmpty ? "Not enough facts extracted yet." : internalAnalysis.knownFacts.joined(separator: "\n")
        let missingText = internalAnalysis.missingFacts.isEmpty ? "None identified" : internalAnalysis.missingFacts.map(\.label).joined(separator: ", ")
        return """
        Date/Time: \(DateFormatter.factTrailDateTime.string(from: draft.incidentDate))
        Category: \(internalAnalysis.suggestedCategory.rawValue)
        Event Type: \(internalAnalysis.eventType)
        Known Facts:
        \(factText)
        Missing Information: \(missingText)
        Child Involved: \(draft.childInvolved ? "Yes" : "No")
        """
    }

    private func buildFinalSummary(from draft: IncidentDraft, analysis: AIIncidentAnalysis?) -> String {
        var paragraphs: [String] = []
        let dateText = DateFormatter.factTrailDateTime.string(from: draft.incidentDate)
        let actorText = draft.peopleInvolved.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationText = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryText = draft.category.rawValue.lowercased()

        var opening = "On \(dateText), the reporting parent documented \(article(for: categoryText)) \(categoryText) incident."
        if !actorText.isEmpty {
            opening += " People identified in the entry include \(actorText)."
        }
        if !locationText.isEmpty {
            opening += " The event was documented as occurring at or near \(locationText)."
        }
        paragraphs.append(opening)

        let narrativeContext = narrativeContextParagraph(from: draft, analysis: analysis)
        if !narrativeContext.isEmpty {
            paragraphs.append(narrativeContext)
        }

        let answeredQuestions = draft.guidedAnswers.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !answeredQuestions.isEmpty {
            let responseText = answeredQuestions.map { answer in
                answer.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            }.joined(separator: " ")
            paragraphs.append("Additional context gathered through the guided interview: \(sentenceCase(responseText))")
        }

        if draft.childInvolved {
            paragraphs.append("The entry indicates a child was involved or directly connected to the event.")
        }

        let evidence = evidenceLine(from: draft, analysis: analysis)
        if !evidence.isEmpty {
            paragraphs.append("Supporting evidence referenced includes \(evidence).")
        }

        if !draft.patternTags.isEmpty {
            let tagText = draft.patternTags.map(\.displayName).joined(separator: ", ")
            paragraphs.append("Possible documentation tags for organizing this record include \(tagText).")
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private func evidenceLine(from draft: IncidentDraft, analysis: AIIncidentAnalysis?) -> String {
        var values = Set<String>()
        for item in analysis?.evidenceMentioned ?? [] { values.insert(item) }
        if !draft.evidenceNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { values.insert("evidence notes") }
        for type in draft.evidenceTypes { values.insert(type.rawValue.lowercased()) }
        if !draft.evidenceAttachments.isEmpty { values.insert("attached photos or screenshots") }
        return values.sorted().joined(separator: ", ")
    }

    private func narrativeContextParagraph(from draft: IncidentDraft, analysis: AIIncidentAnalysis?) -> String {
        let text = draft.originalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let category = analysis?.suggestedCategory ?? draft.category

        switch category {
        case .medical:
            var sentences: [String] = []
            if lower.contains("missed") && lower.contains("appointment") {
                sentences.append("The reporting parent documented learning that a child-related medical appointment or follow-up had been missed.")
            } else {
                sentences.append("The reporting parent documented a medical-related event involving care, an appointment, or medical communication.")
            }
            if lower.contains("call") {
                sentences.append("The original notes indicate the information was received by phone.")
            }
            if lower.contains("three weeks") || lower.contains("scheduled") {
                sentences.append("The notes indicate the appointment or event had been scheduled before the reporting parent became aware of the issue.")
            }
            if lower.contains("after") {
                sentences.append("The reporting parent indicated they learned about the issue after it had already occurred.")
            }
            return sentences.joined(separator: " ")

        case .school:
            var sentences: [String] = []
            if lower.contains("permission slip") || lower.contains("field trip") {
                sentences.append("The reporting parent documented a school-related communication issue involving a permission slip, form, or field trip information.")
            } else {
                sentences.append("The reporting parent documented a school-related communication or record issue.")
            }
            if lower.contains("teacher") || lower.contains("school") {
                sentences.append("The notes reference school staff, school records, or school communication as part of the event.")
            }
            if lower.contains("forgot") || lower.contains("not share") || lower.contains("did not share") {
                sentences.append("The notes indicate information may not have been shared with the reporting parent before action was needed.")
            }
            return sentences.joined(separator: " ")

        case .exchange:
            var sentences: [String] = []
            if lower.contains("late") {
                sentences.append("The reporting parent documented an exchange where the actual arrival time differed from the expected exchange time.")
            } else {
                sentences.append("The reporting parent documented a child exchange or handoff event.")
            }
            if lower.contains("did not message") || lower.contains("beforehand") || lower.contains("notice") {
                sentences.append("The notes indicate advance notice may not have been provided before arrival.")
            }
            if lower.contains("traffic") {
                sentences.append("The original notes report that traffic was later given as an explanation.")
            }
            if lower.contains("upset") || lower.contains("waiting") {
                sentences.append("The notes include an observation that the child appeared upset or had been waiting.")
            }
            return sentences.joined(separator: " ")

        case .communication:
            return "The reporting parent documented a communication issue involving messages, calls, emails, response timing, or information sharing."

        case .schedule:
            return "The reporting parent documented a scheduling issue involving an expected date, time, plan, or change in timing."

        case .financial:
            return "The reporting parent documented a financial issue involving an expense, payment, receipt, invoice, or related communication."

        case .safety:
            return "The reporting parent documented a safety-related concern based on the facts described in the original notes."

        case .childWellbeing:
            return "The reporting parent documented an observation related to the child's wellbeing, behavior, words, or experience."

        case .other:
            return text.isEmpty
                ? ""
                : "The reporting parent documented the event in the original notes and provided details for organization into a factual record."
        }
    }

    private func logAnalysisStart(incidentText: String, internalAnalysis: InternalIncidentAnalysis, analysis: AIIncidentAnalysis) {
        print("""

        [FactTrail AI Debug] NEW ANALYSIS STARTED
        Incident Text:
        \(incidentText)

        Structured facts extracted:
        \(internalAnalysis.knownFacts.joined(separator: "\n"))

        Detected entities:
        \(internalAnalysis.people.joined(separator: ", "))

        Detected event type:
        \(internalAnalysis.eventType)

        Suggested category:
        \(internalAnalysis.suggestedCategory.rawValue) (confidence: \(internalAnalysis.categoryConfidence))

        Missing information:
        \(internalAnalysis.missingFacts.map(\.label).joined(separator: ", "))

        Evidence detected:
        \(internalAnalysis.evidenceMentioned.joined(separator: ", "))

        Pattern tags:
        \(internalAnalysis.patternTags.map(\.rawValue).joined(separator: ", "))

        Generated questions:
        \(analysis.followUpQuestions.map { "\($0.priority.rawValue): \($0.question)" }.joined(separator: "\n"))

        END ANALYSIS
        """)
    }

    private func regexMatches(pattern: String, text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private func sentenceCase(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        let result = first.uppercased() + trimmed.dropFirst()
        return result.hasSuffix(".") ? result : result + "."
    }

    private func article(for word: String) -> String {
        guard let first = word.first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }

    private func mentionsEvidence(_ text: String) -> Bool {
        text.contains("text") || text.contains("message") || text.contains("screenshot") || text.contains("email") || text.contains("photo") || text.contains("record") || text.contains("call log")
    }

    private func hasPatternLanguage(_ text: String) -> Bool {
        text.contains("happened before") || text.contains("few times") || text.contains("again") || text.contains("always") || text.contains("multiple times") || text.contains("pattern") || text.contains("previous") || text.contains("fourth")
    }

    private func containsRecurrenceCount(_ text: String) -> Bool {
        text.contains("once") || text.contains("twice") || text.contains("three") || text.contains("four") || text.contains("five") || text.contains("times") || text.contains("1") || text.contains("2") || text.contains("3") || text.contains("4") || text.contains("5")
    }

    private func hasLocationClue(_ text: String) -> Bool {
        text.contains(" at ") || text.contains("school") || text.contains("clinic") || text.contains("hospital") || text.contains("maverik") || text.contains("office")
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func uniqueMissingFacts(_ values: [MissingFact]) -> [MissingFact] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }
}

extension MockAIService: AIServiceStatusProviding {
    var serviceMode: AIServiceMode {
        .mock
    }
}

enum AIDebugLogger {
    static func log(_ title: String, _ value: String) {
        print("[FactTrail AI Debug] \(title): \(value)")
    }
}

extension AIIncidentAnalysis {
    var legacyQuestionTexts: [String] {
        followUpQuestions.map(\.question)
    }

    var debugSummary: String {
        """
        understanding=\(understandingSummary)
        category=\(suggestedCategory.rawValue)
        reason=\(categoryReason)
        questions=\(followUpQuestions.map { "\($0.priority.rawValue): \($0.question)" })
        missing=\(missingInformation)
        evidence=\(evidenceMentioned)
        tags=\(patternTags.map(\.rawValue))
        summary=\(neutralSummary)
        debug=\(debugSnapshot?.structuredFacts ?? [])
        """
    }
}
