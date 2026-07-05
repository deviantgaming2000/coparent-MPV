import Foundation
import Observation

/// Where an account identity came from. Google is defined for parity with the
/// reference UI but is not wired to a real flow yet.
enum AccountProvider: String, Codable {
    case apple
    case google
}

/// A local account identity. There is no backend, so this only records who the
/// user is for display; it does not sync or protect data server-side.
struct AccountSession: Codable, Equatable {
    var provider: AccountProvider
    var userID: String
    var displayName: String?
    var email: String?
    var signedInAt: Date
}

/// Persists a single account session in UserDefaults.
enum AccountStore {
    static let key = "coparoAccountSession"

    static func load() -> AccountSession? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AccountSession.self, from: data)
    }

    static func save(_ session: AccountSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(session) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Observable holder for the current account, shared through the SwiftUI
/// environment. Created once at app root.
@Observable
final class AccountManager {
    var session: AccountSession?

    init() {
        session = AccountStore.load()
    }

    var isSignedIn: Bool { session != nil }
    var displayName: String? { session?.displayName }
    var email: String? { session?.email }

    /// Build and persist a session from an Apple credential. Apple returns the
    /// name and email only on the first authorization, so keep whatever is given.
    /// When a name is present and the user has no saved name yet, seed it so the
    /// greeting and profile row reflect it.
    func applyAppleCredential(userID: String, fullName: PersonNameComponents?, email: String?, at now: Date = Date()) {
        let formatter = PersonNameComponentsFormatter()
        let formattedName = fullName
            .map { formatter.string(from: $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (formattedName?.isEmpty == false) ? formattedName : nil

        let newSession = AccountSession(
            provider: .apple,
            userID: userID,
            displayName: name,
            email: email,
            signedInAt: now
        )
        session = newSession
        AccountStore.save(newSession)

        if let name {
            let existing = (UserDefaults.standard.string(forKey: "factTrailUserName") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.isEmpty {
                UserDefaults.standard.set(name, forKey: "factTrailUserName")
            }
        }
    }

    func signOut() {
        session = nil
        AccountStore.clear()
    }
}
