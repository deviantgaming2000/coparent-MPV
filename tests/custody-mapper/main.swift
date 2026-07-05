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

// 9. Guard: bare canonical phrase "week on week off" still matches (<= 8 words, no nuance keywords).
let guardSimple = HeuristicCustodyDescriptionParser.parse("week on week off")
check(guardSimple != nil, "bare 'week on week off' still matches the heuristic")

// 10. Guard: canonical phrase plus a nuance keyword (Christmas) must defer to the model (nil).
let guardNuance = HeuristicCustodyDescriptionParser.parse("week on week off and I get Christmas")
check(guardNuance == nil, "canonical phrase + nuance keyword defers to the model (nil)")

// 11. Guard: a long (>8 word) description containing a canonical phrase must defer to the model (nil).
let guardLong = HeuristicCustodyDescriptionParser.parse("We generally do week on week off but sometimes it changes depending on work travel")
check(guardLong == nil, "long (>8 word) description with canonical phrase defers to the model (nil)")

// 12. Color-index seeding: existing caregivers you(0)+Jordan(1)+Sam(2); a draft naming a new
// "Taylor" caregiver must be assigned a colorIndex NOT already used by an existing caregiver.
let sam = CustodyCaregiver(id: "p2", name: "Sam", colorIndex: 2)
let draft3 = CustodyDraft(
    cycleLengthDays: 7,
    days: [CustodyDraftDay(dayIndex: 0, caregiverLabel: "Taylor")],
    caregivers: [CustodyDraftCaregiver(label: "me", role: .you), CustodyDraftCaregiver(label: "Taylor", role: .other)],
    startHint: "this week",
    holidays: []
)
let result3 = CustodyScheduleMapper.map(draft: draft3, existingCaregivers: [you, jordan, sam], referenceDate: ref)
let taylor = result3.schedule.caregivers.first { $0.name == "Taylor" }
check(taylor != nil, "Taylor caregiver created")
check(![0, 1, 2].contains(taylor!.colorIndex), "Taylor's colorIndex (\(taylor!.colorIndex)) does not collide with existing caregivers' colors {0,1,2}")

print("ALL PASS")
