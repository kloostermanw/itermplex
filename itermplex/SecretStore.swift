import Foundation
import Security

/// Abstraction over a place to stash small secrets (e.g. remote connection tokens),
/// so production code can use the Keychain while tests use an in-memory stand-in.
protocol SecretStore {
    func secret(for key: String) -> String?
    func setSecret(_ value: String, for key: String)
    func removeSecret(for key: String)
}

/// Keychain-backed `SecretStore`. Stores each secret as a generic password item under a
/// fixed service, keyed by `account`. Best-effort: any Keychain failure is swallowed
/// (returns nil / no-ops) rather than crashing the app.
struct KeychainSecretStore: SecretStore {
    private let service = "eu.kloosterman.itermplex.remote"

    private func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func secret(for key: String) -> String? {
        var attributes = query(for: key)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let base = query(for: key)

        if secret(for: key) != nil {
            let attributes: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        } else {
            var addQuery = base
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func removeSecret(for key: String) {
        SecItemDelete(query(for: key) as CFDictionary)
    }
}
