import Foundation

struct TerminalHandle: Equatable, Sendable {
    let sessionId: String
    let windowId: String
}

enum TerminalError: LocalizedError, Equatable {
    case iTermNotInstalled
    case apiDisabled
    case automationDenied
    case pythonNotFound
    case venvCreationFailed
    case pipInstallFailed
    case bridgeFailed(String)

    var errorDescription: String? {
        switch self {
        case .iTermNotInstalled:
            return "iTerm2 is not installed."
        case .apiDisabled:
            return "Enable the Python API in iTerm2: Settings → General → Magic → Enable Python API."
        case .automationDenied:
            return "Allow itermplex to control iTerm in System Settings → Privacy & Security → Automation."
        case .pythonNotFound:
            return "Python 3 is required but was not found."
        case .venvCreationFailed:
            return "Could not create the Python environment for itermplex."
        case .pipInstallFailed:
            return "Could not install the iterm2 Python package (check your network)."
        case .bridgeFailed(let message):
            return message
        }
    }
}

struct FocusResult: Equatable, Sendable {
    let found: Bool
    let jobName: String?
}

protocol TerminalService: Sendable {
    /// - Parameter badge: When non-nil, set as the session's iTerm2 badge text
    ///   (independent of the session/tab name). Nil leaves the badge untouched.
    func open(folder: URL, existingWindowId: String?, command: String?, badge: String?) async throws -> TerminalHandle
    func focus(sessionId: String) async throws -> FocusResult
    func send(sessionId: String, text: String) async throws
    func close(sessionId: String) async throws
}
