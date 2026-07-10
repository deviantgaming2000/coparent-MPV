import Foundation

/// One caregiver in the custody schedule — you, the co-parent, or anyone else who has
/// the kids on some days (a grandparent, etc.). `colorIndex` maps into the shared custody
/// palette in the view layer so the model stays free of SwiftUI.
struct CustodyCaregiver: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var colorIndex: Int

    /// The stable id used for "you" (distinct from any saved person's UUID).
    static let youID = "you"
}

/// A repeating parenting-time pattern anchored to a start date, plus one-off day overrides.
/// For any date it can answer who has the kids, which is what color-codes the calendar; an
/// exchange day is simply where that answer changes from the day before.
struct CustodySchedule: Codable, Equatable {
    var anchorDate: Date
    var caregivers: [CustodyCaregiver]
    /// One entry per day of the repeating cycle, each a caregiver id.
    var cycle: [String]
    /// Per-date reassignments (holiday swaps, vacations) keyed by `dateKey`.
    var overrides: [String: String]
    /// Which preset (or "custom") produced the cycle, so the setup screen can reflect it.
    var patternID: String
    /// When set, the user picked exactly which days of the repeating cycle are exchange
    /// days (indices into `cycle`). Nil means automatic: an exchange is derived wherever
    /// custody changes hands from the previous day.
    var exchangeDayIndices: [Int]?

    init(
        anchorDate: Date,
        caregivers: [CustodyCaregiver],
        cycle: [String],
        overrides: [String: String] = [:],
        patternID: String = CustodyPattern.custom.rawValue,
        exchangeDayIndices: [Int]? = nil
    ) {
        self.anchorDate = anchorDate
        self.caregivers = caregivers
        self.cycle = cycle
        self.overrides = overrides
        self.patternID = patternID
        self.exchangeDayIndices = exchangeDayIndices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anchorDate = try container.decode(Date.self, forKey: .anchorDate)
        caregivers = try container.decode([CustodyCaregiver].self, forKey: .caregivers)
        cycle = try container.decode([String].self, forKey: .cycle)
        overrides = try container.decodeIfPresent([String: String].self, forKey: .overrides) ?? [:]
        patternID = try container.decodeIfPresent(String.self, forKey: .patternID) ?? CustodyPattern.custom.rawValue
        exchangeDayIndices = try container.decodeIfPresent([Int].self, forKey: .exchangeDayIndices)
    }

    // MARK: Resolution

    /// The position of a date within the repeating cycle (nil when there is no cycle).
    func cycleIndex(on date: Date) -> Int? {
        guard !cycle.isEmpty else { return nil }
        let offset = Self.dayOffset(from: anchorDate, to: date)
        return ((offset % cycle.count) + cycle.count) % cycle.count
    }

    /// The caregiver id responsible for a given date (override first, else the cycle).
    func caregiverID(on date: Date) -> String? {
        if let overridden = overrides[Self.dateKey(for: date)] {
            return overridden
        }
        guard let index = cycleIndex(on: date) else { return nil }
        return cycle[index]
    }

    func caregiver(on date: Date) -> CustodyCaregiver? {
        guard let id = caregiverID(on: date) else { return nil }
        return caregivers.first { $0.id == id }
    }

    /// True when an exchange happens on this day. If the user picked explicit exchange
    /// days, those win; otherwise it's derived as the day custody changes hands.
    func isExchange(on date: Date) -> Bool {
        if let exchangeDayIndices {
            guard let index = cycleIndex(on: date) else { return false }
            return exchangeDayIndices.contains(index)
        }
        guard let today = caregiverID(on: date),
              // Calendar-aware "yesterday" — a fixed 86,400s stride lands on the wrong
              // day across daylight-saving transitions.
              let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return false }
        let previous = caregiverID(on: previousDay)
        return previous != nil && previous != today
    }

    /// The exchange days the automatic rule would produce, as cycle indices — used to
    /// pre-fill the editor when the user switches to picking days manually.
    var derivedExchangeIndices: Set<Int> {
        guard cycle.count > 1 else { return [] }
        var result = Set<Int>()
        for index in cycle.indices {
            let previous = cycle[(index - 1 + cycle.count) % cycle.count]
            if cycle[index] != previous { result.insert(index) }
        }
        return result
    }

    // MARK: Keys & math

    static func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func dayOffset(from start: Date, to date: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let targetDay = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
    }
}

/// The common two-parent schedules, expressed as a repeating cycle over two caregivers.
/// (Three-plus caregivers are handled with the custom pattern and per-day overrides.)
enum CustodyPattern: String, CaseIterable, Identifiable {
    case weekOnOff
    case twoTwoThree
    case twoTwoFiveFive
    case threeFourFourThree
    case everyOtherWeekend
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekOnOff: return "Week on / week off"
        case .twoTwoThree: return "2-2-3"
        case .twoTwoFiveFive: return "2-2-5-5"
        case .threeFourFourThree: return "3-4-4-3"
        case .everyOtherWeekend: return "Every other weekend"
        case .custom: return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .weekOnOff: return "Alternating full weeks"
        case .twoTwoThree: return "Two, two, three-day split"
        case .twoTwoFiveFive: return "Two, two, five, five"
        case .threeFourFourThree: return "Three, four, four, three"
        case .everyOtherWeekend: return "One primary, alternating weekends"
        case .custom: return "Paint your own week"
        }
    }

    /// Builds the repeating cycle for this pattern. `you` gets the first block; the start
    /// date the user picks lines the pattern up with real life.
    func cycle(you: String, coParent: String) -> [String] {
        let a = you
        let b = coParent
        switch self {
        case .weekOnOff:
            return Array(repeating: a, count: 7) + Array(repeating: b, count: 7)
        case .twoTwoThree:
            return [a, a, b, b, a, a, a] + [b, b, a, a, b, b, b]
        case .twoTwoFiveFive:
            return [a, a, b, b] + Array(repeating: a, count: 5) + Array(repeating: b, count: 5)
        case .threeFourFourThree:
            return [a, a, a, b, b, b, b] + [a, a, a, a, b, b, b]
        case .everyOtherWeekend:
            // Primary (you) has weekdays; co-parent gets alternating Fri–Sun. Start on a Monday.
            return [a, a, a, a, b, b, b] + Array(repeating: a, count: 7)
        case .custom:
            return []
        }
    }
}

enum CustodyScheduleStore {
    private static let key = "coparoCustodySchedule"

    static func load() -> CustodySchedule? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CustodySchedule.self, from: data)
    }

    static func save(_ schedule: CustodySchedule) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(schedule) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
