import Foundation

struct PythonEnvironment: Sendable {
    let candidatePaths: [String]
    let supportDir: URL

    init(
        candidatePaths: [String] = ["/opt/homebrew/bin/python3", "/usr/bin/python3", "/usr/local/bin/python3"],
        supportDir: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("itermplex")
    ) {
        self.candidatePaths = candidatePaths
        self.supportDir = supportDir
    }

    /// First candidate path that is an executable file, or nil.
    func discoverInterpreter() -> String? {
        let fm = FileManager.default
        for path in candidatePaths where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    var venvPythonURL: URL {
        supportDir.appendingPathComponent("venv/bin/python3")
    }

    /// Returns the venv interpreter, creating the venv and installing `iterm2` on first use.
    func ensureInterpreter() throws -> URL {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: venvPythonURL.path) {
            return venvPythonURL
        }
        guard let base = discoverInterpreter() else { throw TerminalError.pythonNotFound }
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let venvDir = supportDir.appendingPathComponent("venv")
        do {
            try Self.run(base, ["-m", "venv", venvDir.path])
        } catch {
            throw TerminalError.venvCreationFailed
        }
        do {
            try Self.run(venvPythonURL.path, ["-m", "pip", "install", "--disable-pip-version-check", "iterm2"])
        } catch {
            throw TerminalError.pipInstallFailed
        }
        return venvPythonURL
    }

    /// Runs a process to completion, discarding output, throwing on non-zero exit.
    private static func run(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw TerminalError.bridgeFailed("Command failed: \(launchPath) \(arguments.joined(separator: " "))")
        }
    }
}
