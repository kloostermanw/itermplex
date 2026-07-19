import Foundation

/// The shared secret required on every remote request and socket. Persisted in
/// UserDefaults; generated lazily on first use.
struct RemoteAccessToken {
    private let defaults: UserDefaults
    private let key = "itermplex.remote.token"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var value: String {
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        return persistNewToken()
    }

    @discardableResult
    func regenerate() -> String { persistNewToken() }

    func matches(_ candidate: String?) -> Bool {
        guard let candidate, !candidate.isEmpty else { return false }
        return candidate == value
    }

    private func persistNewToken() -> String {
        let token = Self.randomToken()
        defaults.set(token, forKey: key)
        return token
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
