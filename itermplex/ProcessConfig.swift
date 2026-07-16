import Foundation

/// How a process runs and is stopped. Raw values are the on-disk `kind` strings.
enum ProcessKind: String, Codable, Equatable {
    case longRunning = "long_running"
    case daemon
    case shortRunning = "short_running"
}

/// One process definition from `itermplex.json`. Read-only in the app: the file
/// is the source of truth, so this type only decodes (it is still `Codable` for
/// symmetry and tests).
struct ProcessConfig: Codable, Equatable {
    var command: String
    var kind: ProcessKind
    var stop: String?
    var status: String?
    var autoStart: Bool
    var autoRestart: Bool
    var restartWhenChanged: [String]
    var env: [String: String]

    init(
        command: String,
        kind: ProcessKind = .longRunning,
        stop: String? = nil,
        status: String? = nil,
        autoStart: Bool = false,
        autoRestart: Bool = false,
        restartWhenChanged: [String] = [],
        env: [String: String] = [:]
    ) {
        self.command = command
        self.kind = kind
        self.stop = stop
        self.status = status
        self.autoStart = autoStart
        self.autoRestart = autoRestart
        self.restartWhenChanged = restartWhenChanged
        self.env = env
    }

    private enum CodingKeys: String, CodingKey {
        case command, kind, stop, status
        case autoStart = "auto_start"
        case autoRestart = "auto_restart"
        case restartWhenChanged = "restart_when_changed"
        case env
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        command = try c.decode(String.self, forKey: .command)
        kind = try c.decodeIfPresent(ProcessKind.self, forKey: .kind) ?? .longRunning
        stop = try c.decodeIfPresent(String.self, forKey: .stop)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        autoRestart = try c.decodeIfPresent(Bool.self, forKey: .autoRestart) ?? false
        restartWhenChanged = try c.decodeIfPresent([String].self, forKey: .restartWhenChanged) ?? []
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
    }
}
