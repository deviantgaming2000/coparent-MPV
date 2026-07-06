import Foundation

/// Per-entry state for the "Pick up where you left off" suggestions. An entry the
/// app flags as thin starts `pending`; the user can `setAside` (snooze it out of the
/// card) or `ignore` (dismiss it for good). Persisted in UserDefaults keyed by the
/// incident's UUID string.
enum PickUpItemState: String, Codable {
    case pending
    case setAside
    case ignored
}

/// A single suggestion shown in the Insights "Pick up where you left off" card.
struct PickUpItem: Identifiable, Equatable {
    let id: String
    let title: String
    let suggestion: String
}

enum PickUpStateStore {
    private static let key = "coparoPickUpStates"

    static func load() -> [String: PickUpItemState] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: PickUpItemState].self, from: data) else {
            return [:]
        }
        return dict
    }

    static func save(_ states: [String: PickUpItemState]) {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
