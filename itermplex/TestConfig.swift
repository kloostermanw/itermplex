import Foundation

/// One test-process definition from the `tests` section of `itermplex.json`. A
/// test is a run-to-completion check: exit 0 = pass, non-zero = fail. Read-only
/// in the app (the file is the source of truth); `Codable` for symmetry/tests.
struct TestConfig: Codable, Equatable {
    var command: String
    var env: [String: String]
    /// When false (the default), a command that references an `ITERMPLEX_*`
    /// variable with no value is blocked rather than run with the variable
    /// expanding to empty. Set true to opt into empty expansion.
    var allowEmptyVars: Bool

    init(command: String, env: [String: String] = [:], allowEmptyVars: Bool = false) {
        self.command = command
        self.env = env
        self.allowEmptyVars = allowEmptyVars
    }

    private enum CodingKeys: String, CodingKey {
        case command, env
        case allowEmptyVars = "allow_empty_vars"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        command = try c.decode(String.self, forKey: .command)
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        allowEmptyVars = try c.decodeIfPresent(Bool.self, forKey: .allowEmptyVars) ?? false
    }
}
