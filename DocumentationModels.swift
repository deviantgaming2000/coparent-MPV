import Foundation

struct FinalDocumentationSummary: Codable, Equatable {
    let summary: String
    let completeness: DocumentationCompleteness
}

struct DocumentationCompleteness: Codable, Equatable {
    let score: Int
    let completedItems: [String]
    let missingItems: [String]

    var status: String {
        switch score {
        case 90...100:
            return "Completed"
        case 70..<90:
            return "Mostly Complete"
        case 45..<70:
            return "Needs More Detail"
        default:
            return "Incomplete"
        }
    }
}

enum DocumentationCompletenessCalculator {
    static func calculate(draft: IncidentDraft, analysis: AIIncidentAnalysis?) -> DocumentationCompleteness {
        var completed: [String] = []
        var missing: [String] = []

        addCheck(
            hasValue(draft.originalNotes),
            completedLabel: "Original notes",
            missingLabel: "Original notes",
            completed: &completed,
            missing: &missing
        )
        addCheck(
            true,
            completedLabel: "Date",
            missingLabel: "Date",
            completed: &completed,
            missing: &missing
        )
        addCheck(
            hasSpecificTime(in: draft),
            completedLabel: "Time",
            missingLabel: "Specific time",
            completed: &completed,
            missing: &missing
        )
        addCheck(
            true,
            completedLabel: "Category",
            missingLabel: "Category",
            completed: &completed,
            missing: &missing
        )
        addCheck(
            hasValue(draft.finalDocumentation?.summary),
            completedLabel: "Chronological summary",
            missingLabel: "Chronological final summary",
            completed: &completed,
            missing: &missing
        )
        addCheck(
            hasEvidence(draft: draft, analysis: analysis),
            completedLabel: "Evidence referenced",
            missingLabel: "Evidence referenced",
            completed: &completed,
            missing: &missing
        )
        addCheck(
            draft.childInvolved || mentionsChild(in: draft.originalNotes) || mentionsChild(in: draft.guidedAnswers.map(\.answer).joined(separator: " ")),
            completedLabel: "Child observations",
            missingLabel: "Child observations, if applicable",
            completed: &completed,
            missing: &missing
        )
        addCheck(
            draft.guidedAnswers.contains { hasValue($0.answer) },
            completedLabel: "Follow-up responses",
            missingLabel: "Follow-up responses",
            completed: &completed,
            missing: &missing
        )
        addCheck(
            hasValue(draft.peopleInvolved) || draft.originalNotes.lowercased().contains("parent"),
            completedLabel: "People involved",
            missingLabel: "People involved",
            completed: &completed,
            missing: &missing
        )
        addCheck(
            hasValue(draft.location) || draft.originalNotes.lowercased().contains(" at "),
            completedLabel: "Location",
            missingLabel: "Location",
            completed: &completed,
            missing: &missing
        )

        let total = completed.count + missing.count
        let score = total == 0 ? 0 : Int((Double(completed.count) / Double(total) * 100).rounded())

        return DocumentationCompleteness(
            score: min(max(score, 0), 100),
            completedItems: completed,
            missingItems: missing
        )
    }

    private static func addCheck(
        _ condition: Bool,
        completedLabel: String,
        missingLabel: String,
        completed: inout [String],
        missing: inout [String]
    ) {
        if condition {
            completed.append(completedLabel)
        } else {
            missing.append(missingLabel)
        }
    }

    private static func hasValue(_ value: String?) -> Bool {
        !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func hasSpecificTime(in draft: IncidentDraft) -> Bool {
        let text = [draft.originalNotes, draft.guidedAnswers.map(\.answer).joined(separator: " ")].joined(separator: " ").lowercased()
        return text.contains(":") || text.contains("am") || text.contains("pm")
    }

    private static func hasEvidence(draft: IncidentDraft, analysis: AIIncidentAnalysis?) -> Bool {
        hasValue(draft.evidenceNotes)
        || !draft.evidenceTypes.isEmpty
        || !draft.evidenceAttachments.isEmpty
        || !(analysis?.evidenceMentioned.isEmpty ?? true)
    }

    private static func mentionsChild(in text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("child") || lower.contains("son") || lower.contains("daughter") || lower.contains("kid")
    }
}
