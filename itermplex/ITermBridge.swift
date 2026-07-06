import Foundation
import AppKit

struct ITermBridge: TerminalService {
    private let pythonEnvironment: PythonEnvironment
    private let iTermBundleId = "com.googlecode.iterm2"

    init(pythonEnvironment: PythonEnvironment = PythonEnvironment()) {
        self.pythonEnvironment = pythonEnvironment
    }

    func open(folder: URL, existingWindowId: String?) async throws -> TerminalHandle {
        var args = ["open", folder.path]
        if let windowId = existingWindowId {
            args += ["--window", windowId]
        }
        let json = try runBridge(args)
        guard let sessionId = json["session_id"] as? String,
              let windowId = json["window_id"] as? String else {
            throw TerminalError.bridgeFailed("Unexpected bridge output for open.")
        }
        await activateITerm()
        return TerminalHandle(sessionId: sessionId, windowId: windowId)
    }

    func focus(sessionId: String) async throws -> Bool {
        let json = try runBridge(["focus", sessionId])
        let found = (json["found"] as? Bool) ?? false
        if found { await activateITerm() }
        return found
    }

    func close(sessionId: String) async throws {
        _ = try runBridge(["close", sessionId])
    }

    // MARK: - Helpers

    private func runBridge(_ arguments: [String]) throws -> [String: Any] {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleId) != nil else {
            throw TerminalError.iTermNotInstalled
        }
        let python = try pythonEnvironment.ensureInterpreter()
        guard let script = Bundle.main.url(forResource: "iterm_bridge", withExtension: "py") else {
            throw TerminalError.bridgeFailed("Bridge script missing from app bundle.")
        }
        let cookie = try requestCookie()
        let result = try runProcess(
            executable: python.path,
            arguments: [script.path] + arguments,
            extraEnvironment: ["ITERM2_COOKIE": cookie]
        )
        if result.status != 0 {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.lowercased().contains("connect") {
                throw TerminalError.apiDisabled
            }
            throw TerminalError.bridgeFailed(message.isEmpty ? "iTerm2 bridge failed." : message)
        }
        guard let data = result.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TerminalError.bridgeFailed("Could not parse bridge output.")
        }
        return object
    }

    private func requestCookie() throws -> String {
        let result = try runProcess(
            executable: "/usr/bin/osascript",
            arguments: ["-e", "tell application \"iTerm2\" to request cookie"],
            extraEnvironment: [:]
        )
        let cookie = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !cookie.isEmpty else {
            throw TerminalError.automationDenied
        }
        return cookie
    }

    @MainActor
    private func activateITerm() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleId) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        extraEnvironment: [String: String]
    ) throws -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in extraEnvironment { environment[key] = value }
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }
}
