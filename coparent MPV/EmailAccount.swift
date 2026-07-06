import Foundation
import CryptoKit
import Security

/// A locally-stored email account credential. There is NO backend: this only proves
/// the user re-typed the password they set, on this device. It does not sync, verify
/// the email address, or protect the on-device data — iOS device security does that.
struct LocalCredential: Codable {
    var email: String
    var displayName: String?
    var salt: String
    var passwordHash: String
}

/// Stores the single local account credential in the iOS Keychain.
enum LocalCredentialStore {
    private static let service = "com.coparo.localaccount"
    private static let account = "primary"

    static func load() -> LocalCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let credential = try? JSONDecoder().decode(LocalCredential.self, from: data) else {
            return nil
        }
        return credential
    }

    static func save(_ credential: LocalCredential) {
        guard let data = try? JSONEncoder().encode(credential) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func makeSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(password: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data((salt + password).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum EmailAuthError: LocalizedError {
    case invalidEmail
    case shortPassword
    case accountExists
    case noAccount
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Enter a valid email address."
        case .shortPassword: return "Password must be at least 6 characters."
        case .accountExists: return "An account already exists on this device. Log in instead."
        case .noAccount: return "No account found for that email on this device."
        case .wrongPassword: return "That password doesn't match."
        }
    }
}
