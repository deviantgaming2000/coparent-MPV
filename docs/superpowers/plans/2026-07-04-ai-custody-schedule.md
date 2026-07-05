# AI-Parsed Custody Schedule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user describe their custody schedule in natural language (typed or dictated) and have an on-device AI turn it into the app's existing `CustodySchedule`, shown in a preview to confirm before it color-codes the calendar.

**Architecture:** A pure Foundation mapping layer converts an AI-shaped `CustodyDraft` into a `CustodySchedule` (fully unit-testable without the model). A thin `OnDeviceCustodyParser` uses iOS 26 Foundation Models with guided generation to produce that draft, with a keyword heuristic fallback. A SwiftUI describe-then-preview flow drives it, and the existing `CustodyScheduleView` becomes the manual editor and fallback.

**Tech Stack:** Swift, SwiftUI, Foundation Models (`import FoundationModels`, `LanguageModelSession`, `@Generable`), existing `CustodySchedule`/`CustodyScheduleStore`/`CustodyPalette`, existing `SpeechTranscriber` for dictation.

## Global Constraints

- Never use an em dash. Use a plain dash "-" in comments and UI copy.
- New Swift files go in the `coparent MPV/` folder (a `PBXFileSystemSynchronizedRootGroup` that auto-includes them). Do not edit the `.pbxproj`.
- The AI is on-device only. No API key, no network, no backend. No custody data leaves the phone.
- Reuse the existing model unchanged: `CustodySchedule(anchorDate:caregivers:cycle:overrides:patternID:)`, `CustodyCaregiver(id:name:colorIndex:)` with `CustodyCaregiver.youID == "you"`, `CustodySchedule.dateKey(for:)`, `CustodyScheduleStore.load()/save(_:)/clear()`, `CustodyPalette.color(_:)`, `CustodyPattern`.
- Colors resolve through `FactTrailTheme` / `CustodyPalette`; never hardcode hex except where those APIs already do.
- Scope is whole-day assignments plus one-off fixed-holiday overrides. No partial-day. Do not guess personal dates (e.g. birthdays) - surface them as notes.
- `CustodyScheduleMapper.swift` MUST import only `Foundation` (no SwiftUI, no FoundationModels) so it compiles and unit-tests standalone.
- Xcode build (the app-level check):
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "/Users/mikehansen/Desktop/coparent MPV/coparent MPV.xcodeproj" -scheme "coparent MPV" -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
  ```
  Pass = `** BUILD SUCCEEDED **`. Use `dangerouslyDisableSandbox: true` on the build Bash call if a sandbox error occurs.
- Foundation Models does not run on a plain simulator (availability is `.unavailable` there), so the simulator exercises the fallback path; the on-device path is verified on a physical Apple-Intelligence device. State this where relevant.

---

## File Structure

- Create `coparent MPV/CustodyScheduleMapper.swift` - Foundation-only. `CustodyDraft`, `CustodyRole`, `CustodyParseResult`, `CustodyScheduleMapper.map(...)`, fixed-holiday resolution, `HeuristicCustodyDescriptionParser.parse(...)`. Unit-tested with `swiftc`.
- Create `coparent MPV/CustodyScheduleParser.swift` - imports FoundationModels. `CustodyScheduleParsing` protocol, `@Generable` types, `OnDeviceCustodyParser`, `HeuristicCustodyParser`, `CustodyScheduleParserFactory`. Build-verified.
- Create `coparent MPV/CustodyDescribeView.swift` - the describe-then-preview SwiftUI flow.
- Modify `coparent MPV/CustodyScheduleView.swift` - add an optional `initialSchedule` for pre-filled manual editing.
- Modify `coparent MPV/SettingsView.swift` - the Custody row opens the new flow.
- Modify `coparent MPV/OnboardingFlow.swift` - the onboarding custody step opens the new flow.

---

## Task 1: Mapping layer + heuristic parser (pure Foundation, unit-tested)

**Files:**
- Create: `coparent MPV/CustodyScheduleMapper.swift`
- Test (scratch): `/tmp/custody_test/main.swift`

**Interfaces:**
- Produces:
  - `enum CustodyRole: String { case you, coParent, other }`
  - `struct CustodyDraftDay { var dayIndex: Int; var caregiverLabel: String }`
  - `struct CustodyDraftCaregiver { var label: String; var role: CustodyRole }`
  - `struct CustodyDraftHoliday { var name: String; var caregiverLabel: String }`
  - `struct CustodyDraft { var cycleLengthDays: Int; var days: [CustodyDraftDay]; var caregivers: [CustodyDraftCaregiver]; var startHint: String; var holidays: [CustodyDraftHoliday] }`
  - `struct CustodyParseResult { var schedule: CustodySchedule; var summary: String; var holidayNotes: [String] }`
  - `enum CustodyScheduleMapper { static func map(draft: CustodyDraft, existingCaregivers: [CustodyCaregiver], referenceDate: Date) -> CustodyParseResult }`
  - `enum HeuristicCustodyDescriptionParser { static func parse(_ description: String) -> CustodyDraft? }`

- [ ] **Step 1: Write the mapper and heuristic**

Create `coparent MPV/CustodyScheduleMapper.swift`:

```swift
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
        var usedColorIndexes = Set<Int>()

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
    static func parse(_ description: String) -> CustodyDraft? {
        let text = description.lowercased()
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
```

- [ ] **Step 2: Write the failing test**

Create the directory and file `/tmp/custody_test/main.swift`:

```swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); exit(1) }
}

let cal = Calendar(identifier: .gregorian)
let ref = cal.date(from: DateComponents(year: 2026, month: 7, day: 4))!
let you = CustodyCaregiver(id: CustodyCaregiver.youID, name: "Alex", colorIndex: 0)
let jordan = CustodyCaregiver(id: "p1", name: "Jordan", colorIndex: 1)

// 1. Week on / week off from a draft, "me" resolves to you, Jordan matched by name.
let weekPattern = (0..<14).map { CustodyDraftDay(dayIndex: $0, caregiverLabel: $0 < 7 ? "me" : "Jordan") }
let draft = CustodyDraft(
    cycleLengthDays: 14,
    days: weekPattern,
    caregivers: [CustodyDraftCaregiver(label: "me", role: .you), CustodyDraftCaregiver(label: "Jordan", role: .coParent)],
    startHint: "this week",
    holidays: [CustodyDraftHoliday(name: "Christmas", caregiverLabel: "me")]
)
let result = CustodyScheduleMapper.map(draft: draft, existingCaregivers: [you, jordan], referenceDate: ref)

check(result.schedule.cycle.count == 14, "cycle length 14")
check(result.schedule.cycle[0] == CustodyCaregiver.youID, "day 0 is you")
check(result.schedule.cycle[7] == "p1", "day 7 is Jordan")

// 2. Anchor is the start of the week (Sunday) containing 2026-07-04 (a Saturday) -> 2026-06-28.
let anchorComps = cal.dateComponents([.year, .month, .day], from: result.schedule.anchorDate)
check(anchorComps.year == 2026 && anchorComps.month == 6 && anchorComps.day == 28, "anchor is Sun 2026-06-28, got \(anchorComps)")

// 3. Christmas override maps to 2026-12-25 assigned to you.
check(result.schedule.overrides["2026-12-25"] == CustodyCaregiver.youID, "Christmas override for you")

// 4. New Year from July resolves to NEXT year (2027-01-01).
let ny = HolidayResolver.upcomingDate(named: "New Year's Day", onOrAfter: ref, calendar: cal)!
let nyc = cal.dateComponents([.year, .month, .day], from: ny)
check(nyc.year == 2027 && nyc.month == 1 && nyc.day == 1, "New Year resolves to 2027-01-01, got \(nyc)")

// 5. Thanksgiving 2026 is the 4th Thursday of November = 2026-11-26.
let tg = HolidayResolver.upcomingDate(named: "Thanksgiving", onOrAfter: ref, calendar: cal)!
let tgc = cal.dateComponents([.year, .month, .day], from: tg)
check(tgc.year == 2026 && tgc.month == 11 && tgc.day == 26, "Thanksgiving 2026-11-26, got \(tgc)")

// 6. Unknown holiday becomes a note, not an override.
let draft2 = CustodyDraft(cycleLengthDays: 7, days: [], caregivers: [CustodyDraftCaregiver(label: "me", role: .you)], startHint: "", holidays: [CustodyDraftHoliday(name: "her birthday", caregiverLabel: "me")])
let result2 = CustodyScheduleMapper.map(draft: draft2, existingCaregivers: [you], referenceDate: ref)
check(result2.schedule.overrides.isEmpty, "unknown holiday not added as override")
check(result2.holidayNotes.count == 1, "unknown holiday surfaced as a note")

// 7. Heuristic recognizes "week on week off".
let heur = HeuristicCustodyDescriptionParser.parse("We do week on week off.")
check(heur != nil && heur!.cycleLengthDays == 14, "heuristic parses week on/off")

// 8. Heuristic returns nil for unrecognized text.
check(HeuristicCustodyDescriptionParser.parse("some rambling with no pattern") == nil, "heuristic nil on unknown")

print("ALL PASS")
```

Run it (expected to FAIL because the mapper file is not yet compiled together / any mistakes surface):
```
cd "/Users/mikehansen/Desktop/coparent MPV"
mkdir -p /tmp/custody_test
# (write the test file above to /tmp/custody_test/main.swift)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx swiftc "coparent MPV/CustodySchedule.swift" "coparent MPV/CustodyScheduleMapper.swift" /tmp/custody_test/main.swift -o /tmp/custody_test/run && /tmp/custody_test/run
```
Expected before the mapper is correct: a compile error or a `FAIL:` line. After Step 1's code is in place, this should be run in Step 3.

- [ ] **Step 3: Run the test to verify it passes**

Run the same command as Step 2.
Expected: compiles and prints `ALL PASS`.
If a `FAIL:` line prints, fix `CustodyScheduleMapper.swift` (not the test) until it passes.

- [ ] **Step 4: Verify the app still builds**

Run the Xcode build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **` (the new Foundation-only file compiles into the app too).

- [ ] **Step 5: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/CustodyScheduleMapper.swift"
git commit -m "Add pure custody schedule mapper and heuristic parser with tests"
```

---

## Task 2: On-device parser + factory (Foundation Models)

**Files:**
- Create: `coparent MPV/CustodyScheduleParser.swift`

**Interfaces:**
- Consumes: `CustodyDraft`, `CustodyParseResult`, `CustodyScheduleMapper.map(...)`, `HeuristicCustodyDescriptionParser.parse(...)`, `CustodyCaregiver` (Task 1 / existing).
- Produces:
  - `protocol CustodyScheduleParsing { func parse(description: String, existingCaregivers: [CustodyCaregiver], referenceDate: Date) async throws -> CustodyParseResult? }`
  - `struct OnDeviceCustodyParser: CustodyScheduleParsing`
  - `struct HeuristicCustodyParser: CustodyScheduleParsing`
  - `enum CustodyScheduleParserFactory { static func make() -> any CustodyScheduleParsing; static var isOnDeviceAvailable: Bool }`

- [ ] **Step 1: Create the parser file**

Create `coparent MPV/CustodyScheduleParser.swift`:

```swift
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
            caregivers: gen.caregivers.map { CustodyDraftCaregiver(label: $0.label, role: CustodyRole(rawValue: $0.role) ?? .other) },
            startHint: gen.startHint,
            holidays: gen.holidays.map { CustodyDraftHoliday(name: $0.name, caregiverLabel: $0.caregiverLabel) }
        )
    }
}

// MARK: - Heuristic fallback parser

struct HeuristicCustodyParser: CustodyScheduleParsing {
    func parse(description: String, existingCaregivers: [CustodyCaregiver], referenceDate: Date) async throws -> CustodyParseResult? {
        guard let draft = HeuristicCustodyDescriptionParser.parse(description) else { return nil }
        return CustodyScheduleMapper.map(draft: draft, existingCaregivers: existingCaregivers, referenceDate: referenceDate)
    }
}

// MARK: - Factory

enum CustodyScheduleParserFactory {
    static var isOnDeviceAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func make() -> any CustodyScheduleParsing {
        isOnDeviceAvailable ? OnDeviceCustodyParser() : HeuristicCustodyParser()
    }
}
```

Note on the Foundation Models API: the framework is new. If the build reports a signature mismatch on `LanguageModelSession`, `Instructions`, `session.respond(to:generating:)`, `@Guide`, or `SystemLanguageModel.default.availability`, adjust the exact call to match the SDK in Xcode while preserving this structure (a guided-generation call returning `GenCustodySchedule`, plus an availability check). Report any such adjustment.

- [ ] **Step 2: Build**

Run the Xcode build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/CustodyScheduleParser.swift"
git commit -m "Add on-device custody parser with Foundation Models and heuristic fallback"
```

---

## Task 3: Describe + Preview flow, and pre-fillable manual editor

**Files:**
- Create: `coparent MPV/CustodyDescribeView.swift`
- Modify: `coparent MPV/CustodyScheduleView.swift`

**Interfaces:**
- Consumes: `CustodyScheduleParserFactory`, `CustodyParseResult`, `CustodyScheduleMapper` (Tasks 1-2); `CustodySchedule`, `CustodyScheduleStore`, `CustodyPalette`, `CustodyScheduleView`, `SpeechTranscriber`, `FactTrailTheme` (existing).
- Produces: `struct CustodyDescribeView: View` presented from the menu and onboarding (Task 4).

- [ ] **Step 1: Add an optional pre-fill to the manual editor**

In `coparent MPV/CustodyScheduleView.swift`, add a stored property and use it in `loadState`. Change the property block near the top of the struct (after `let onTurnOff: () -> Void`, line 23) to add:

```swift
    /// When set, the editor starts from this schedule instead of the saved one
    /// (used to hand an AI-produced schedule to the manual editor for tweaking).
    var initialSchedule: CustodySchedule? = nil
```

Then in `loadState()` (line 293), replace the line `let existing = CustodyScheduleStore.load()` with:

```swift
        let existing = initialSchedule ?? CustodyScheduleStore.load()
```

Leave the rest of `loadState` unchanged. Because `initialSchedule` has a default, existing call sites keep working.

- [ ] **Step 2: Create the describe + preview flow**

Create `coparent MPV/CustodyDescribeView.swift`:

```swift
import SwiftUI

struct CustodyDescribeView: View {
    let userName: String
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Stage { case describe, preview }
    @State private var stage: Stage = .describe
    @State private var text: String = ""
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var result: CustodyParseResult?
    @State private var anchorDate: Date = Date()
    @State private var showingManualEditor = false

    @State private var speechTranscriber = SpeechTranscriber()
    @State private var voiceBaseNotes = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch stage {
                case .describe: describeSection
                case .preview: previewSection
                }
            }
            .padding(20)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Custody schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadExisting)
        .onDisappear { speechTranscriber.stopTranscribing() }
        .onChange(of: speechTranscriber.transcript) { _, newTranscript in
            text = mergedNotes(base: voiceBaseNotes, transcript: newTranscript)
        }
        .sheet(isPresented: $showingManualEditor, onDismiss: { onSaved(); dismiss() }) {
            NavigationStack {
                CustodyScheduleView(
                    userName: userName,
                    onSave: { CustodyScheduleStore.save($0) },
                    onTurnOff: { CustodyScheduleStore.clear() },
                    initialSchedule: result?.schedule
                )
            }
        }
    }

    // MARK: Describe

    private var describeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Describe your custody schedule in your own words, and Coparo will map it onto your calendar. You can review it before anything is saved.")
                .font(.system(size: 14))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("e.g. I have the kids Monday to Wednesday and every other weekend. My co-parent Jordan has them the rest. I get them Christmas.")
                        .font(.system(size: 15))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(6)
            }
            .background(FactTrailTheme.surface(for: colorScheme))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                Button(action: toggleDictation) {
                    HStack(spacing: 8) {
                        Image(systemName: speechTranscriber.isRecording ? "stop.circle.fill" : "mic.fill")
                        Text(speechTranscriber.isRecording ? "Stop" : "Dictate")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(speechTranscriber.isRecording ? .red : FactTrailTheme.aiAccent(for: colorScheme))
                }
                .buttonStyle(.plain)
                if speechTranscriber.isRecording {
                    Text("Listening...")
                        .font(.system(size: 12))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }
                Spacer()
            }

            if let speechError = speechTranscriber.errorMessage {
                Text(speechError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            Button(action: runParse) {
                HStack(spacing: 8) {
                    if isParsing { ProgressView().tint(.white) }
                    Text(isParsing ? "Mapping..." : "Map my schedule")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)

            Button("Set it up manually instead") { showingManualEditor = true }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                .buttonStyle(.plain)
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var previewSection: some View {
        if let result {
            VStack(alignment: .leading, spacing: 18) {
                Text("Here's what we heard")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

                Text(result.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

                previewGrid(schedule: scheduleWithAnchor(result.schedule))

                ForEach(result.holidayNotes, id: \.self) { note in
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }

                HStack {
                    Text("Starts the week of")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Spacer()
                    DatePicker("", selection: $anchorDate, displayedComponents: .date).labelsHidden()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }

                Button(action: save) { Text("Save schedule").frame(maxWidth: .infinity) }
                    .buttonStyle(FactTrailPrimaryButtonStyle())

                Button("Edit manually") { showingManualEditor = true }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                Button("Re-describe") { stage = .describe }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func previewGrid(schedule: CustodySchedule) -> some View {
        let start = Calendar.current.startOfDay(for: anchorDate)
        let days = (0..<14).map { Calendar.current.date(byAdding: .day, value: $0, to: start) ?? start }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(days, id: \.self) { day in
                let caregiver = schedule.caregiver(on: day)
                let color = CustodyPalette.color(caregiver?.colorIndex ?? 0)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(caregiver == nil ? FactTrailTheme.mutedText(for: colorScheme) : color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.opacity(caregiver == nil ? 0 : 0.16)))
            }
        }
    }

    // MARK: Logic

    private func loadExisting() {
        if let existing = CustodyScheduleStore.load() {
            result = CustodyParseResult(schedule: existing, summary: "Your current schedule.", holidayNotes: [])
            anchorDate = existing.anchorDate
            stage = .preview
        }
    }

    private func scheduleWithAnchor(_ schedule: CustodySchedule) -> CustodySchedule {
        var copy = schedule
        copy.anchorDate = anchorDate
        return copy
    }

    private func runParse() {
        errorMessage = nil
        isParsing = true
        let description = text
        let caregivers = CustodyDescribeView.currentCaregivers(youName: youName)
        Task { @MainActor in
            defer { isParsing = false }
            do {
                let parser = CustodyScheduleParserFactory.make()
                if let parsed = try await parser.parse(description: description, existingCaregivers: caregivers, referenceDate: Date()) {
                    result = parsed
                    anchorDate = parsed.schedule.anchorDate
                    stage = .preview
                } else {
                    errorMessage = "I couldn't quite get that. Try rephrasing, or set it up manually."
                }
            } catch {
                errorMessage = "I couldn't map that right now. You can set it up manually."
            }
        }
    }

    private func save() {
        guard let result else { return }
        CustodyScheduleStore.save(scheduleWithAnchor(result.schedule))
        onSaved()
        dismiss()
    }

    private var youName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : trimmed
    }

    /// You plus everyone in My people, matching the manual editor's caregiver list.
    static func currentCaregivers(youName: String) -> [CustodyCaregiver] {
        var result: [CustodyCaregiver] = [CustodyCaregiver(id: CustodyCaregiver.youID, name: youName, colorIndex: 0)]
        for (offset, person) in PeopleStore.load().enumerated() {
            result.append(CustodyCaregiver(id: person.id.uuidString, name: person.name, colorIndex: offset + 1))
        }
        return result
    }

    // MARK: Dictation

    // Mirrors the Add-note sheet in ContentView.swift exactly: startTranscribing()
    // is async and runs in a Task; the transcriber owns `isRecording` and updates
    // `transcript` live, which the .onChange above merges into the text field.
    private func toggleDictation() {
        if speechTranscriber.isRecording {
            speechTranscriber.stopTranscribing()
        } else {
            errorMessage = nil
            voiceBaseNotes = text
            Task { await speechTranscriber.startTranscribing() }
        }
    }

    private func mergedNotes(base: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return base }
        let cleanedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBase.isEmpty else { return cleanedTranscript }
        return "\(cleanedBase) \(cleanedTranscript)"
    }
}
```

`SpeechTranscriber` is confirmed to expose `@Observable`, `var transcript`, `var errorMessage`, `var isRecording`, `func startTranscribing() async`, and `func stopTranscribing()` - the code above matches those exactly.

- [ ] **Step 3: Build**

Run the Xcode build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify on the simulator**

Since `CustodyDescribeView` is not wired into navigation until Task 4, verify by building only here. Full navigation is verified in Task 4. Confirm the build has no warnings from the new file.

- [ ] **Step 5: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/CustodyDescribeView.swift" "coparent MPV/CustodyScheduleView.swift"
git commit -m "Add custody describe-and-preview flow; make manual editor pre-fillable"
```

---

## Task 4: Wire the flow into the menu and onboarding

**Files:**
- Modify: `coparent MPV/SettingsView.swift`
- Modify: `coparent MPV/OnboardingFlow.swift`

**Interfaces:**
- Consumes: `CustodyDescribeView(userName:onSaved:)` (Task 3).

- [ ] **Step 1: Point the menu Custody row at the new flow**

In `coparent MPV/SettingsView.swift`, find the Custody schedule row (currently a `SettingsRow(... destination: CustodyScheduleView(userName: userName, onSave: { CustodyScheduleStore.save($0) }, onTurnOff: { CustodyScheduleStore.clear() }))`, near line 133). Replace its `destination:` with the new flow:

```swift
                        SettingsRow(systemImage: "calendar", label: "Custody schedule", destination: CustodyDescribeView(userName: userName))
```

- [ ] **Step 2: Point the onboarding custody step at the new flow**

In `coparent MPV/OnboardingFlow.swift`, find `OnboardingCustodyStep`'s sheet that presents `CustodyScheduleView` (in the `.sheet(isPresented: $showingSetup)` block). Replace the sheet content so "Yes, let's add it" opens the describe flow instead:

```swift
        .sheet(isPresented: $showingSetup) {
            NavigationStack {
                CustodyDescribeView(userName: userName)
            }
            .onDisappear { onContinue() }
        }
```

Leave the rest of `OnboardingCustodyStep` unchanged (the `userName` property and the choice rows already exist from the earlier custody task).

- [ ] **Step 3: Build**

Run the Xcode build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify on the simulator**

Install and launch. Open the menu -> Custody schedule. Verify:
- With no schedule saved: the describe screen shows, with the text field, a Dictate button, "Map my schedule", and "Set it up manually instead".
- Typing a recognizable phrase (for example "week on week off") and tapping "Map my schedule" produces a preview with a colored two-week grid (the simulator uses the heuristic fallback since on-device AI is unavailable there). Saving returns and the Timeline calendar shows the colors.
- "Edit manually" opens the existing editor pre-filled; "Re-describe" returns to the text.
- With a schedule already saved: reopening Custody schedule starts on the preview of the current schedule.
- Onboarding: reach the custody step, tap "Yes, let's add it", and confirm the describe flow appears and advances the wizard on dismiss.
- On a physical Apple-Intelligence device, a free-form description (for example "I have them Monday through Wednesday and every other weekend, my ex Jordan has them otherwise, I get Christmas") maps correctly. Note this is device-only.

- [ ] **Step 5: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/SettingsView.swift" "coparent MPV/OnboardingFlow.swift"
git commit -m "Open the AI custody describe flow from the menu and onboarding"
```

---

## Final verification

- [ ] Run the mapper tests once more (`/tmp/custody_test/run`) and confirm `ALL PASS`.
- [ ] On the simulator, walk the full menu flow: describe a heuristic-recognized schedule, preview, adjust the start week, save, and confirm the Timeline calendar coloring and exchange marks.
- [ ] On a physical Apple-Intelligence device: describe a free-form schedule with a holiday, confirm the preview and saved calendar, then edit manually and confirm the change persists.
- [ ] Confirm the manual editor and "Turn off schedule" still work (regression), and that a device without Apple Intelligence falls back cleanly (heuristic or manual), never blocking.
