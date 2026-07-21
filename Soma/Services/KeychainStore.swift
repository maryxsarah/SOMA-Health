import Foundation
import Security

/// Everything needed to resume a Supabase Auth session without signing in
/// again. Kept in Keychain, never UserDefaults.
struct StoredSession: Codable {
    let userID: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Minimal Security-framework wrapper. Only stores/reads/clears a single
/// session value -- V1 has nothing else that needs Keychain-grade privacy.
final class KeychainStore {
    private let service = "com.soma.app.supabase-session"
    private let account = "session"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func load() -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
