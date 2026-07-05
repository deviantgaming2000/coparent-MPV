import Foundation

/// Who a caregiver is, from the user's description.
enum CustodyRole: String, Codable {
    case you
    case coParent
    case other
}

struct CustodyDraftDay: Equatable {
    var dayIndex: Int
    var caregiverLabel: String
}

struct CustodyDraftCaregiver: Equatable {
    var label: String
    var role: CustodyRole
}

struct CustodyDraftHoliday: Equatable {
    var name: String
    var caregiverLabel: String
}

/// The plain, model-agnostic shape a parser produces. `days` are ordered starting
/// on the first day of the week (Sunday), so `dayIndex 0` is Sunday.
struct CustodyDraft: Equatable {
    var cycleLengthDays: Int
    var days: [CustodyDraftDay]
    var caregivers: [CustodyDraftCaregiver]
    var startHint: String
    var holidays: [CustodyDraftHoliday]
}

struct CustodyParseResult {
    var schedule: CustodySchedule
    var summary: String
    var holidayNotes: [String]
}

/// Converts a parser's `CustodyDraft` into the app's `CustodySchedule`. Pure and
/// deterministic: the anchor is the start of the week containing `referenceDate`
/// (the preview lets the user shift weeks), day 0 of the cycle is that Sunday.
enum CustodyScheduleMapper {
    static func map(draft: CustodyDraft, existingCaregivers: [CustodyCaregiver], referenceDate: Date) -> CustodyParseResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1 // Sunday

        // Resolve caregivers: map each draft label to a CustodyCaregiver, reusing
        // existing ones by role/name and assigning fresh colors to new ones.
        var caregivers: [CustodyCaregiver] = []
        var labelToID: [String: String] = [:]
        let youCaregiver = existingCaregivers.first { $0.id == CustodyCaregiver.youID }
            ?? CustodyCaregiver(id: CustodyCaregiver.youID, name: "You", colorIndex: 0)
        // Seed from every existing caregiver's color up front so a newly-created AI
        // caregiver never reuses a color already assigned to someone in the app.
        var usedColorIndexes = Set(existingCaregivers.map { $0.colorIndex })

        func nextColorIndex() -> Int {
            var i = 0
            while usedColorIndexes.contains(i) { i += 1 }
            usedColorIndexes.insert(i)
            return i
        }

        func registerCaregiver(_ caregiver: CustodyCaregiver, label: String) {
            if !caregivers.contains(where: { $0.id == caregiver.id }) {
                caregivers.append(caregiver)
                usedColorIndexes.insert(caregiver.colorIndex)
            }
            labelToID[label.lowercased()] = caregiver.id
        }

        for draftCaregiver in draft.caregivers {
            let label = draftCaregiver.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = label.lowercased()
            if draftCaregiver.role == .you || ["me", "i", "you", "myself"].contains(lower) {
                registerCaregiver(youCaregiver, label: label)
            } else if let match = existingCaregivers.first(where: { $0.id != CustodyCaregiver.youID && $0.name.lowercased() == lower }) {
                registerCaregiver(match, label: label)
            } else {
                let caregiver = CustodyCaregiver(id: "ai-\(lower.replacingOccurrences(of: " ", with: "-"))", name: label.isEmpty ? "Co-parent" : label, colorIndex: nextColorIndex())
                registerCaregiver(caregiver, label: label)
            }
        }
        if caregivers.isEmpty { registerCaregiver(youCaregiver, label: "me") }

        func caregiverID(forLabel label: String) -> String {
            labelToID[label.lowercased()] ?? youCaregiver.id
        }

        // Build the cycle (one caregiver id per day), filling gaps with the prior day.
        let length = max(1, min(draft.cycleLengthDays, 28))
        var cycle: [String] = Array(repeating: youCaregiver.id, count: length)
        for day in draft.days where day.dayIndex >= 0 && day.dayIndex < length {
            cycle[day.dayIndex] = caregiverID(forLabel: day.caregiverLabel)
        }

        // Anchor = start of the week containing referenceDate.
        let anchorDate = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
            ?? calendar.startOfDay(for: referenceDate)

        // Holidays -> overrides (fixed holidays only; unknown ones become notes).
        var overrides: [String: String] = [:]
        var holidayNotes: [String] = []
        for holiday in draft.holidays {
            if let date = HolidayResolver.upcomingDate(named: holiday.name, onOrAfter: referenceDate, calendar: calendar) {
                overrides[CustodySchedule.dateKey(for: date)] = caregiverID(forLabel: holiday.caregiverLabel)
            } else {
                holidayNotes.append("Couldn't place \"\(holiday.name)\" automatically - add it by editing.")
            }
        }

        let schedule = CustodySchedule(
            anchorDate: anchorDate,
            caregivers: caregivers,
            cycle: cycle,
            overrides: overrides,
            patternID: CustodyPattern.custom.rawValue
        )

        return CustodyParseResult(schedule: schedule, summary: summarize(schedule: schedule, calendar: calendar), holidayNotes: holidayNotes)
    }

    /// A plain-English summary of the first week's assignments.
    private static func summarize(schedule: CustodySchedule, calendar: Calendar) -> String {
        guard !schedule.cycle.isEmpty else { return "No days assigned yet." }
        let names = Dictionary(uniqueKeysWithValues: schedule.caregivers.map { ($0.id, $0.id == CustodyCaregiver.youID ? "You" : $0.name) })
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var byCaregiver: [String: [String]] = [:]
        for (index, id) in schedule.cycle.prefix(7).enumerated() {
            byCaregiver[id, default: []].append(weekdays[index % 7])
        }
        let parts = byCaregiver.map { id, days in
            "\(names[id] ?? "Someone") has \(days.joined(separator: ", "))"
        }
        let cycleNote = schedule.cycle.count > 7 ? " Repeats every \(schedule.cycle.count) days." : " Repeats weekly."
        return parts.sorted().joined(separator: "; ") + "." + cycleNote
    }
}

/// Resolves common fixed-date and rule-based US holidays to the next occurrence.
enum HolidayResolver {
    static func upcomingDate(named rawName: String, onOrAfter reference: Date, calendar: Calendar) -> Date? {
        let name = rawName.lowercased()
        let year = calendar.component(.year, from: reference)

        func date(month: Int, day: Int, year: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
        func thanksgiving(year: Int) -> Date? {
            // 4th Thursday of November.
            guard let firstNov = date(month: 11, day: 1, year: year) else { return nil }
            let weekday = calendar.component(.weekday, from: firstNov) // 1=Sun..5=Thu
            let firstThursdayOffset = (5 - weekday + 7) % 7
            return calendar.date(from: DateComponents(year: year, month: 11, day: 1 + firstThursdayOffset + 21))
        }

        func candidate(for year: Int) -> Date? {
            if name.contains("christmas eve") { return date(month: 12, day: 24, year: year) }
            if name.contains("christmas") { return date(month: 12, day: 25, year: year) }
            if name.contains("new year") { return date(month: 1, day: 1, year: year) }
            if name.contains("independence") || name.contains("july 4") || name.contains("4th of july") || name.contains("fourth of july") { return date(month: 7, day: 4, year: year) }
            if name.contains("halloween") { return date(month: 10, day: 31, year: year) }
            if name.contains("valentine") { return date(month: 2, day: 14, year: year) }
            if name.contains("thanksgiving") { return thanksgiving(year: year) }
            return nil
        }

        let refDay = calendar.startOfDay(for: reference)
        for candidateYear in [year, year + 1] {
            if let d = candidate(for: candidateYear), calendar.startOfDay(for: d) >= refDay {
                return d
            }
        }
        return nil
    }
}

/// A keyword fallback for common patterns, used when on-device AI is unavailable.
/// Returns nil when it does not recognize the phrasing (the caller falls back to manual).
enum HeuristicCustodyDescriptionParser {
    /// Nuance keywords that mean the description is richer than a bare canonical
    /// phrase (it names a holiday, a birthday, a vacation, etc.). When any of these
    /// appear, the heuristic must not claim the description - a canonical-only draft
    /// would silently drop that detail - so it defers to the on-device model instead.
    private static let nuanceKeywords = [
        "christmas", "thanksgiving", "new year", "birthday", "holiday",
        "halloween", "easter", "vacation", "summer", "break", "july", "fourth", "4th"
    ]

    /// Self-guard: this parser only claims SIMPLE, canonical-only descriptions.
    /// It requires the description to be 8 words or fewer AND free of any nuance
    /// keyword (names, holidays, vacations, etc.) before it will match a canonical
    /// phrase. Anything richer returns nil so the caller defers to the model, which
    /// preserves names/holidays the heuristic's fixed "me"/"co-parent" draft would drop.
    static func parse(_ description: String) -> CustodyDraft? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.lowercased()

        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount <= 8 else { return nil }
        guard !nuanceKeywords.contains(where: { text.contains($0) }) else { return nil }

        let me = CustodyDraftCaregiver(label: "me", role: .you)
        let coParent = CustodyDraftCaregiver(label: "co-parent", role: .coParent)

        func days(_ pattern: [Int]) -> [CustodyDraftDay] {
            pattern.enumerated().map { CustodyDraftDay(dayIndex: $0.offset, caregiverLabel: $0.element == 0 ? "me" : "co-parent") }
        }

        if text.contains("week on") || text.contains("week off") || text.contains("alternating week") {
            let pattern = Array(repeating: 0, count: 7) + Array(repeating: 1, count: 7)
            return CustodyDraft(cycleLengthDays: 14, days: days(pattern), caregivers: [me, coParent], startHint: "this week", holidays: [])
        }
        if text.contains("2-2-3") || text.contains("two two three") || text.contains("2 2 3") {
            let pattern = [0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1]
            return CustodyDraft(cycleLengthDays: 14, days: days(pattern), caregivers: [me, coParent], startHint: "this week", holidays: [])
        }
        if text.contains("every other weekend") {
            let pattern = [0, 0, 0, 0, 1, 1, 1] + Array(repeating: 0, count: 7)
            return CustodyDraft(cycleLengthDays: 14, days: days(pattern), caregivers: [me, coParent], startHint: "this week", holidays: [])
        }
        return nil
    }
}
