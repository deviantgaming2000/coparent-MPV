import Foundation
import Observation

/// Where an account identity came from. Google is defined for parity with the
/// reference UI but is not wired to a real flow yet.
enum AccountProvider: String, Codable {
    case apple
    case google
    case email
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

    /// Whether a local email account has been created on this device.
    var hasLocalAccount: Bool { LocalCredentialStore.load() != nil }

    /// Creates a local email account (Keychain-stored, salted-hashed password) and
    /// signs in. No backend and no email verification — this is a device-local profile.
    func createEmailAccount(email: String, password: String, displayName: String?, at now: Date = Date()) throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), normalized.contains(".") else { throw EmailAuthError.invalidEmail }
        guard password.count >= 6 else { throw EmailAuthError.shortPassword }
        if LocalCredentialStore.load() != nil { throw EmailAuthError.accountExists }

        let salt = LocalCredentialStore.makeSalt()
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = (name?.isEmpty == false) ? name : nil
        LocalCredentialStore.save(
            LocalCredential(
                email: normalized,
                displayName: cleanName,
                salt: salt,
                passwordHash: LocalCredentialStore.hash(password: password, salt: salt)
            )
        )
        applyEmailSession(email: normalized, displayName: cleanName, at: now)
    }

    /// Signs in against the locally-stored credential.
    func signInWithEmail(email: String, password: String, at now: Date = Date()) throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let credential = LocalCredentialStore.load(), credential.email == normalized else {
            throw EmailAuthError.noAccount
        }
        guard LocalCredentialStore.hash(password: password, salt: credential.salt) == credential.passwordHash else {
            throw EmailAuthError.wrongPassword
        }
        applyEmailSession(email: normalized, displayName: credential.displayName, at: now)
    }

    private func applyEmailSession(email: String, displayName: String?, at now: Date) {
        let newSession = AccountSession(
            provider: .email,
            userID: email,
            displayName: displayName,
            email: email,
            signedInAt: now
        )
        session = newSession
        AccountStore.save(newSession)

        if let displayName {
            let existing = (UserDefaults.standard.string(forKey: "factTrailUserName") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.isEmpty {
                UserDefaults.standard.set(displayName, forKey: "factTrailUserName")
            }
        }
    }

    func signOut() {
        session = nil
        AccountStore.clear()
    }
}
