import Foundation
import Observation

/// One supervised process: owns its state machine, output buffer, and controls.
/// Uses an injected `ProcessLaunching` so it is testable without spawning real
/// processes. All mutation happens on the main actor.
@MainActor
@Observable
final class ManagedProcess: Identifiable {
    let id = UUID()
    let name: String
    private(set) var config: ProcessConfig
    private(set) var state: ProcessState = .idle
    private(set) var log = ProcessLogBuffer()

    private let directory: URL
    private let launcher: ProcessLaunching
    private let graceInterval: Duration
    private let maxRapidRestarts = 3

    private var handle: ProcessHandle?
    private var stopRequested = false
    private var escalation: Task<Void, Never>?
    private var restartCount = 0

    init(
        name: String,
        config: ProcessConfig,
        directory: URL,
        launcher: ProcessLaunching,
        graceInterval: Duration = .seconds(5)
    ) {
        self.name = name
        self.config = config
        self.directory = directory
        self.launcher = launcher
        self.graceInterval = graceInterval
    }

    // MARK: Controls

    func start() {
        guard state == .idle || state == .finished || state.isFailed else { return }
        stopRequested = false
        launchMain()
    }

    func restart() {
        restartCount = 0
        if isAlive {
            stopRequested = true
            handle?.send(signal: SIGTERM)
            // The relaunch happens once the exit lands (see handleExit).
            pendingRestart = true
        } else {
            launchMain()
        }
    }

    func stop() {
        guard isAlive else { return }
        stopRequested = true
        pendingRestart = false
        state = .stopping
        if let stopCommand = config.stop {
            _ = try? launcher.launch(
                command: stopCommand, directory: directory, environment: config.env,
                onOutput: { [weak self] in self?.log.append($0) },
                onExit: { [weak self] _ in self?.settleStopped() }
            )
        } else {
            escalateSignals()
        }
    }

    func kill() {
        stopRequested = true
        pendingRestart = false
        handle?.send(signal: SIGKILL)
    }

    /// Daemon-only: runs the `status` probe and sets running/idle by exit code.
    func probeStatus() {
        // Only block while an actual launch/stop command is in flight; a
        // steady-state `.running` daemon must still be re-probeable so we can
        // notice if it went down externally.
        guard config.kind == .daemon, let statusCommand = config.status,
              state != .starting, state != .stopping else { return }
        _ = try? launcher.launch(
            command: statusCommand, directory: directory, environment: config.env,
            onOutput: { _ in },
            onExit: { [weak self] code in self?.state = (code == 0) ? .running : .idle }
        )
    }

    func updateDefinition(_ config: ProcessConfig) {
        self.config = config
    }

    func markOrphaned() {
        if isAlive { state = .orphaned }
    }

    // MARK: Internals

    private var pendingRestart = false

    private var isAlive: Bool {
        switch state { case .starting, .running, .stopping, .orphaned: return true; default: return false }
    }

    private func launchMain() {
        state = config.kind == .daemon ? .starting : .running
        stopRequested = false
        handle = try? launcher.launch(
            command: config.command,
            directory: directory,
            environment: config.env,
            onOutput: { [weak self] chunk in self?.log.append(chunk) },
            onExit: { [weak self] code in self?.handleExit(code) }
        )
        if handle == nil { state = .failed(-1) }
    }

    private func handleExit(_ code: Int32) {
        escalation?.cancel()
        escalation = nil
        handle = nil

        switch config.kind {
        case .daemon:
            // The start command finishing means the daemon is up (unless we asked to stop).
            if stopRequested { settleStopped() }
            else { state = .running }
        case .longRunning, .shortRunning:
            if pendingRestart {
                pendingRestart = false
                launchMain()
                return
            }
            if stopRequested {
                settleStopped()
                return
            }
            if code == 0 { state = .finished } else { state = .failed(code) }
            if config.autoRestart, config.kind == .longRunning, code != 0 {
                autoRestart()
            }
        }
    }

    private func autoRestart() {
        restartCount += 1
        guard restartCount <= maxRapidRestarts else { return } // crash-loop cap
        launchMain()
    }

    private func escalateSignals() {
        handle?.send(signal: SIGINT)
        escalation = Task { [weak self, graceInterval] in
            guard let self else { return }
            try? await Task.sleep(for: graceInterval)
            if Task.isCancelled { return }
            if self.isAlive { self.handle?.send(signal: SIGTERM) }
            try? await Task.sleep(for: graceInterval)
            if Task.isCancelled { return }
            if self.isAlive { self.handle?.send(signal: SIGKILL) }
        }
    }

    private func settleStopped() {
        escalation?.cancel()
        escalation = nil
        handle = nil
        state = .idle
        stopRequested = false
    }
}

private extension ProcessState {
    var isFailed: Bool { if case .failed = self { return true }; return false }
}
