import Foundation
import FoundationModels

/// Turns a natural-language description into a CustodyParseResult, or nil when it
/// cannot (the caller then routes to the manual editor).
protocol CustodyScheduleParsing {
    func parse(description: String, existingCaregivers: [CustodyCaregiver], referenceDate: Date) async throws -> CustodyParseResult?
}

// MARK: - Guided-generation output types

@Generable
struct GenCustodySchedule {
    @Guide(description: "Number of days in the repeating cycle. Use 7 for a weekly pattern or 14 for a two-week pattern.")
    var cycleLengthDays: Int

    @Guide(description: "One entry per day of the cycle, ordered starting on Sunday (index 0 = Sunday, 1 = Monday, and so on). For a 14-day cycle, index 7 is the second Sunday.")
    var days: [GenCustodyDay]

    @Guide(description: "Everyone who has the children on some days.")
    var caregivers: [GenCustodyCaregiver]

    @Guide(description: "When the pattern starts, e.g. 'this week' or 'next Monday'.")
    var startHint: String

    @Guide(description: "Only holidays the user explicitly mentioned. Leave empty if none.")
    var holidays: [GenCustodyHoliday]
}

@Generable
struct GenCustodyDay {
    @Guide(description: "Zero-based day index within the cycle.")
    var dayIndex: Int
    @Guide(description: "The caregiver label who has the children this day. Must match one of the caregiver labels.")
    var caregiverLabel: String
}

@Generable
struct GenCustodyCaregiver {
    @Guide(description: "How this caregiver is referred to, e.g. 'me', 'Jordan', 'grandma'.")
    var label: String
    @Guide(description: "One of: you, coParent, other. Use 'you' for the person describing the schedule (me/I).")
    var role: String
}

@Generable
struct GenCustodyHoliday {
    @Guide(description: "The holiday name the user mentioned, e.g. 'Christmas', 'July 4th'.")
    var name: String
    @Guide(description: "The caregiver label who has the children that day.")
    var caregiverLabel: String
}

// MARK: - On-device parser

struct OnDeviceCustodyParser: CustodyScheduleParsing {
    func parse(description: String, existingCaregivers: [CustodyCaregiver], referenceDate: Date) async throws -> CustodyParseResult? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: Instructions("""
        You convert a co-parent's plain-language description of their custody schedule into a structured, whole-day schedule.
        Assign each day of the repeating cycle to exactly one caregiver.
        Days are ordered starting on Sunday (index 0 = Sunday).
        Use the role 'you' for the person describing the schedule (words like me, I, my).
        "Week on, week off" (and "alternating weeks") means one caregiver has all seven days of the first week and the other caregiver has all seven days of the next week - it does NOT mean the caregivers alternate individual days.
        Only include holidays the user explicitly names. Do not invent dates or people.
        """))

        let response = try await session.respond(to: trimmed, generating: GenCustodySchedule.self)
        let draft = OnDeviceCustodyParser.draft(from: response.content)
        return CustodyScheduleMapper.map(draft: draft, existingCaregivers: existingCaregivers, referenceDate: referenceDate)
    }

    /// Converts the model's Generable output into the plain CustodyDraft the mapper consumes.
    static func draft(from gen: GenCustodySchedule) -> CustodyDraft {
        CustodyDraft(
            cycleLengthDays: gen.cycleLengthDays,
            days: gen.days.map { CustodyDraftDay(dayIndex: $0.dayIndex, caregiverLabel: $0.caregiverLabel) },
            caregivers: gen.caregivers.map { CustodyDraftCaregiver(label: $0.label, role: role(from: $0.role)) },
            startHint: gen.startHint,
            holidays: gen.holidays.map { CustodyDraftHoliday(name: $0.name, caregiverLabel: $0.caregiverLabel) }
        )
    }

    /// Normalizes the model's free-form role string (e.g. "co-parent", "Co Parent")
    /// before mapping it to `CustodyRole`, since `CustodyRole(rawValue:)` alone only
    /// matches the exact raw value "coParent".
    private static func role(from raw: String) -> CustodyRole {
        let normalized = raw.lowercased().filter { $0.isLetter }
        switch normalized {
        case "you", "me", "myself", "i": return .you
        case "coparent", "coparents", "parent": return .coParent
        default: return .other
        }
    }
}

// MARK: - Heuristic fallback parser

struct HeuristicCustodyParser: CustodyScheduleParsing {
    func parse(description: String, existingCaregivers: [CustodyCaregiver], referenceDate: Date) async throws -> CustodyParseResult? {
        guard let draft = HeuristicCustodyDescriptionParser.parse(description) else { return nil }
        return CustodyScheduleMapper.map(draft: draft, existingCaregivers: existingCaregivers, referenceDate: referenceDate)
    }
}

// MARK: - Composed parser

/// Tries the deterministic heuristic first (for simple, canonical phrases it
/// recognizes) and falls through to the on-device model for everything else.
struct HeuristicThenOnDeviceParser: CustodyScheduleParsing {
    func parse(description: String, existingCaregivers: [CustodyCaregiver], referenceDate: Date) async throws -> CustodyParseResult? {
        if let draft = HeuristicCustodyDescriptionParser.parse(description) {
            return CustodyScheduleMapper.map(draft: draft, existingCaregivers: existingCaregivers, referenceDate: referenceDate)
        }
        return try await OnDeviceCustodyParser().parse(description: description, existingCaregivers: existingCaregivers, referenceDate: referenceDate)
    }
}

// MARK: - Factory

enum CustodyScheduleParserFactory {
    static var isOnDeviceAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func make() -> any CustodyScheduleParsing {
        isOnDeviceAvailable ? HeuristicThenOnDeviceParser() : HeuristicCustodyParser()
    }
}
