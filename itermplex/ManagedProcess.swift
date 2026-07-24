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
    private let restartWindow: Duration
    private let now: @MainActor () -> ContinuousClock.Instant
    /// Resolves the current `ITERMPLEX_*` variables. Re-evaluated on each launch,
    /// stop, and status probe, so git-derived values reflect the latest refresh
    /// rather than a stale snapshot from when the definition was applied.
    private let variables: @MainActor () -> [String: String]

    private var handle: ProcessHandle?
    private var stopRequested = false
    private var escalation: Task<Void, Never>?
    /// The missing-variable set most recently logged as a skipped status probe.
    /// Probes are polled repeatedly, so a skip is logged only when this set
    /// changes; it is reset once a probe actually runs, so a recurrence logs
    /// afresh instead of staying silent forever.
    private var lastSkippedStatusVars: [String]?
    /// Timestamps of recent auto-restarts, pruned to `restartWindow`. The cap
    /// counts a tight crash loop, not crashes spread across the process's life.
    private var recentRestarts: [ContinuousClock.Instant] = []

    init(
        name: String,
        config: ProcessConfig,
        directory: URL,
        launcher: ProcessLaunching,
        graceInterval: Duration = .seconds(5),
        restartWindow: Duration = .seconds(60),
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        variables: @escaping @MainActor () -> [String: String] = { [:] }
    ) {
        self.name = name
        self.config = config
        self.directory = directory
        self.launcher = launcher
        self.graceInterval = graceInterval
        self.restartWindow = restartWindow
        self.now = now
        self.variables = variables
    }

    // MARK: Controls

    func start() {
        guard state == .idle || state == .finished || state.isFailed else { return }
        stopRequested = false
        recentRestarts.removeAll() // a manual start re-enables a capped process
        launchMain()
    }

    func restart() {
        recentRestarts.removeAll()
        guard isAlive else {
            launchMain()
            return
        }
        switch config.kind {
        case .longRunning, .shortRunning:
            stopRequested = true
            // The relaunch happens once the exit lands (see handleExit's
            // pendingRestart branch).
            pendingRestart = true
            // Escalate SIGINT -> SIGTERM -> SIGKILL (as stop() does) rather than
            // a lone SIGTERM, so a process that ignores SIGTERM still exits and
            // the relaunch actually fires instead of hanging forever.
            escalateSignals()
        case .daemon:
            // A running/orphaned daemon's start command has typically already
            // exited (no handle to signal), so bringing it down means running
            // its stop command, not signaling a process. Once that stop
            // command's exit lands, settleStopped() honors pendingRestart and
            // relaunches. With no stop command there is nothing to bring
            // down, so just relaunch straight away.
            if config.stop != nil {
                pendingRestart = true
                stopRequested = true
                state = .stopping
                performStop()
            } else {
                launchMain()
            }
        }
    }

    func stop() {
        guard isAlive else { return }
        stopRequested = true
        pendingRestart = false
        state = .stopping
        performStop()
    }

    func kill() {
        stopRequested = true
        pendingRestart = false
        handle?.send(signal: SIGKILL)
    }

    /// Daemon-only: runs the `status` probe and sets running/idle by exit code.
    func probeStatus() {
        // Only block while an actual launch/stop command is in flight, or the
        // daemon is already flagged orphaned (its definition was dropped from
        // config; a status probe must not flip it back to running/idle and
        // lose that badge). A steady-state `.running` daemon must still be
        // re-probeable so we can notice if it went down externally.
        guard config.kind == .daemon, let statusCommand = config.status,
              state != .starting, state != .stopping, state != .orphaned else { return }
        let vars = variables()
        let unresolved = blocking(statusCommand, vars)
        guard unresolved.isEmpty else {
            // A probe referencing an unresolved variable would expand it to
            // empty and misreport health, so skip it and keep the last known
            // state until the variable is available (or allow_empty_vars opts
            // in). Log once per distinct missing set rather than on every poll,
            // so a permanently-absent variable is still surfaced without
            // flooding the buffer.
            if unresolved != lastSkippedStatusVars {
                lastSkippedStatusVars = unresolved
                log.append("Status probe skipped: references unset variable(s) \(unresolved.joined(separator: ", ")). Health is not being checked; set \"allow_empty_vars\": true to probe anyway.\n")
            }
            return
        }
        lastSkippedStatusVars = nil
        _ = try? launcher.launch(
            command: statusCommand, directory: directory, environment: mergedEnvironment(vars),
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

    /// Marks a passed run stale: a `.finished` process returns to `.idle`. Any
    /// other state (running, failed, ...) is left unchanged. Used by the test
    /// supervisor when the working tree changes so a green test goes neutral,
    /// while a failing test stays red until it next passes.
    func resetToIdleIfFinished() {
        if state == .finished { state = .idle }
    }

    // MARK: Internals

    private var pendingRestart = false

    private var isAlive: Bool {
        switch state { case .starting, .running, .stopping, .orphaned: return true; default: return false }
    }

    private func launchMain() {
        let vars = variables()
        let unresolved = blocking(config.command, vars)
        if !unresolved.isEmpty {
            log.append("Blocked: command references unset variable(s) \(unresolved.joined(separator: ", ")). Set \"allow_empty_vars\": true to run anyway.\n")
            state = .failed(-1)
            return
        }
        state = config.kind == .daemon ? .starting : .running
        stopRequested = false
        handle = try? launcher.launch(
            command: config.command,
            directory: directory,
            environment: mergedEnvironment(vars),
            onOutput: { [weak self] chunk in self?.log.append(chunk) },
            onExit: { [weak self] code in self?.handleExit(code) }
        )
        if handle == nil { state = .failed(-1) }
    }

    /// The definition's `env` with the current `ITERMPLEX_*` variables layered on
    /// top, so the injected values are authoritative even if `env` names one.
    private func mergedEnvironment(_ vars: [String: String]) -> [String: String] {
        config.env.merging(vars) { _, injected in injected }
    }

    /// Unresolved `ITERMPLEX_*` references in the given shell string that must
    /// block running it. Empty when the process opts into empty expansion via
    /// `allow_empty_vars`, in which case the shell runs the string with the
    /// missing values expanded to empty like any unset variable. Applied to the
    /// `command`, `stop`, and `status` strings so none of them runs blind.
    private func blocking(_ command: String, _ vars: [String: String]) -> [String] {
        guard !config.allowEmptyVars else { return [] }
        return ProcessVariables.unresolved(in: command, available: vars)
    }

    private func handleExit(_ code: Int32) {
        escalation?.cancel()
        escalation = nil
        handle = nil

        switch config.kind {
        case .daemon:
            // The start command finishing means the daemon is up (unless we asked to stop).
            // A nonzero exit means the start command itself failed, so the daemon
            // never came up.
            if stopRequested { settleStopped() }
            else if code == 0 { state = .running }
            else { state = .failed(code) }
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
        let current = now()
        // Keep only restarts inside the sliding window, so a process that
        // crashes occasionally over hours is not permanently barred from
        // restarting the way a lifetime counter would bar it.
        recentRestarts = recentRestarts.filter { $0.duration(to: current) < restartWindow }
        guard recentRestarts.count < maxRapidRestarts else { return } // crash-loop cap
        recentRestarts.append(current)
        launchMain()
    }

    /// Stop mechanics only: runs the configured stop command, or escalates
    /// signals against the live handle. Deliberately does not touch
    /// `pendingRestart` so both `stop()` (which clears it) and `restart()`
    /// (which sets it) can share this without stepping on each other.
    private func performStop() {
        guard let stopCommand = config.stop else {
            escalateSignals()
            return
        }
        let vars = variables()
        let unresolved = blocking(stopCommand, vars)
        if !unresolved.isEmpty {
            // Running a stop command with an unresolved variable could target
            // the wrong thing (an empty branch, path, ...), so don't run it
            // blind. Mirror the launch-failure fallback: signal a live handle,
            // else settle now. A daemon whose start command has already exited
            // has no handle, so its teardown does not run at all; the log below
            // says so rather than claiming a signal that never happens.
            let missing = unresolved.joined(separator: ", ")
            if handle != nil {
                log.append("Blocked: stop command references unset variable(s) \(missing). Signaling the process down instead; set \"allow_empty_vars\": true to run it.\n")
                escalateSignals()
            } else {
                log.append("Blocked: stop command references unset variable(s) \(missing). No live process to signal, so the stop command's teardown did not run; set \"allow_empty_vars\": true to run it anyway.\n")
                settleStopped()
            }
            return
        }
        do {
            _ = try launcher.launch(
                command: stopCommand, directory: directory, environment: mergedEnvironment(vars),
                onOutput: { [weak self] in self?.log.append($0) },
                onExit: { [weak self] _ in self?.settleStopped() }
            )
        } catch {
            // The stop command could not even launch. Don't leave the process
            // wedged in .stopping: signal a live handle so its exit drives
            // settleStopped(), or settle immediately when there is nothing to
            // signal (e.g. a daemon whose start command has already exited).
            log.append("Stop command failed to launch: \(error)\n")
            if handle != nil {
                escalateSignals()
            } else {
                settleStopped()
            }
        }
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
        stopRequested = false
        if pendingRestart {
            pendingRestart = false
            launchMain()
            return
        }
        state = .idle
    }
}

private extension ProcessState {
    var isFailed: Bool { if case .failed = self { return true }; return false }
}
