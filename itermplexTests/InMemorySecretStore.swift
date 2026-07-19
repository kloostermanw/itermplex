import Foundation
@testable import itermplex

/// Dictionary-backed `SecretStore` so tests never touch the real Keychain.
final class InMemorySecretStore: SecretStore {
    private var storage: [String: String] = [:]

    func secret(for key: String) -> String? { storage[key] }
    func setSecret(_ value: String, for key: String) { storage[key] = value }
    func removeSecret(for key: String) { storage.removeValue(forKey: key) }
}
