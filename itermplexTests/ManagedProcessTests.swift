import Testing
import Foundation
@testable import itermplex

@MainActor
final class FakeHandle: @preconcurrency ProcessHandle, @unchecked Sendable {
    private(set) var signals: [Int32] = []
    func send(signal: Int32) { signals.append(signal) }
}

@MainActor
final class FakeLaunch: @unchecked Sendable {
    let command: String
    let onOutput: @MainActor (String) -> Void
    let onExit: @MainActor (Int32) -> Void
    let handle = FakeHandle()
    init(command: String, onOutput: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) {
        self.command = command
        self.onOutput = onOutput
        self.onExit = onExit
    }
}

@MainActor
final class FakeProcessLauncher: @preconcurrency ProcessLaunching, @unchecked Sendable {
    private(set) var launches: [FakeLaunch] = []
    /// Exit code delivered synchronously at launch for one-shot commands
    /// (status probes, stop commands). When nil, the launch stays "running".
    var immediateExit: [String: Int32] = [:]
    /// Commands whose launch throws, simulating a spawn/PTY failure.
    var failingCommands: Set<String> = []

    func launch(
        command: String,
        directory: URL,
        environment: [String: String],
        onOutput: @escaping @MainActor (String) -> Void,
        onExit: @escaping @MainActor (Int32) -> Void
    ) throws -> ProcessHandle {
        if failingCommands.contains(command) { throw ProcessLaunchError.spawnFailed(1) }
        let launch = FakeLaunch(command: command, onOutput: onOutput, onExit: onExit)
        launches.append(launch)
        if let code = immediateExit[command] {
            onExit(code)
        }
        return launch.handle
    }

    var last: FakeLaunch { launches.last! }
}

@MainActor
@Suite struct ManagedProcessTests {
    let dir = URL(fileURLWithPath: "/tmp")

    @Test func shortRunningSuccessBecomesFinished() {
        let launcher = FakeProcessLauncher()
        let p = ManagedProcess(name: "t", config: ProcessConfig(command: "phpunit", kind: .shortRunning), directory: dir, launcher: launcher)
        p.start()
        #expect(p.state == .running)
        launcher.last.onOutput("OK\n")
        launcher.last.onExit(0)
        #expect(p.state == .finished)
        #expect(p.log.lines == ["OK"])
    }

    @Test func shortRunningFailureCarriesExitCode() {
        let launcher = FakeProcessLauncher()
        let p = ManagedProcess(name: "t", config: ProcessConfig(command: "phpunit", kind: .shortRunning), directory: dir, launcher: launcher)
        p.start()
        launcher.last.onExit(3)
        #expect(p.state == .failed(3))
    }

    @Test func longRunningStopWithoutStopCommandSendsSIGINT() {
        let launcher = FakeProcessLauncher()
        let p = ManagedProcess(name: "npm", config: ProcessConfig(command: "npm run dev", kind: .longRunning), directory: dir, launcher: launcher, graceInterval: .zero)
        p.start()
        p.stop()
        #expect(p.state == .stopping)
        #expect(launcher.last.handle.signals.first == SIGINT)
    }

    @Test func longRunningStopWithStopCommandRunsIt() {
        let launcher = FakeProcessLauncher()
        launcher.immediateExit["sail stop"] = 0
        let p = ManagedProcess(name: "queue", config: ProcessConfig(command: "sail queue", kind: .longRunning, stop: "sail stop"), directory: dir, launcher: launcher, graceInterval: .zero)
        p.start()
        p.stop()
        #expect(launcher.launches.map(\.command).contains("sail stop"))
    }

    @Test func daemonStartBecomesRunningWhenStartExitsZero() {
        let launcher = FakeProcessLauncher()
        launcher.immediateExit["sail up -d"] = 0
        let p = ManagedProcess(name: "sail", config: ProcessConfig(command: "sail up -d", kind: .daemon, stop: "sail down"), directory: dir, launcher: launcher)
        p.start()
        #expect(p.state == .running)
    }

    @Test func daemonStartFailureBecomesFailed() {
        let launcher = FakeProcessLauncher()
        launcher.immediateExit["sail up -d"] = 2
        let p = ManagedProcess(name: "sail", config: ProcessConfig(command: "sail up -d", kind: .daemon, stop: "sail down"), directory: dir, launcher: launcher)
        p.start()
        #expect(p.state == .failed(2))
    }

    @Test func orphanedDaemonUnaffectedByStatusProbe() {
        let launcher = FakeProcessLauncher()
        launcher.immediateExit["sail up -d"] = 0
        let up = ProcessConfig(command: "sail up -d", kind: .daemon, stop: "sail down", status: "sail ps")
        let p = ManagedProcess(name: "sail", config: up, directory: dir, launcher: launcher)
        p.start()
        #expect(p.state == .running)
        p.markOrphaned()
        #expect(p.state == .orphaned)
        launcher.immediateExit["sail ps"] = 1
        p.probeStatus()
        #expect(p.state == .orphaned)
    }

    @Test func daemonStatusProbeSetsRunningOrIdle() {
        let launcher = FakeProcessLauncher()
        let up = ProcessConfig(command: "sail up -d", kind: .daemon, stop: "sail down", status: "sail ps")
        let p = ManagedProcess(name: "sail", config: up, directory: dir, launcher: launcher)
        launcher.immediateExit["sail ps"] = 0
        p.probeStatus()
        #expect(p.state == .running)
        launcher.immediateExit["sail ps"] = 1
        p.probeStatus()
        #expect(p.state == .idle)
    }

    @Test func killSendsSIGKILL() {
        let launcher = FakeProcessLauncher()
        let p = ManagedProcess(name: "npm", config: ProcessConfig(command: "npm run dev", kind: .longRunning), directory: dir, launcher: launcher)
        p.start()
        p.kill()
        #expect(launcher.last.handle.signals.contains(SIGKILL))
    }

    @Test func autoRestartRestartsOnUnexpectedExit() {
        let launcher = FakeProcessLauncher()
        let p = ManagedProcess(name: "npm", config: ProcessConfig(command: "npm run dev", kind: .longRunning, autoRestart: true), directory: dir, launcher: launcher)
        p.start()
        #expect(launcher.launches.count == 1)
        launcher.last.onExit(1) // crash
        #expect(launcher.launches.count == 2) // relaunched
        #expect(p.state == .running)
    }

    @Test func daemonRestartBringsDownThenRelaunches() {
        let launcher = FakeProcessLauncher()
        launcher.immediateExit["sail up -d"] = 0
        launcher.immediateExit["sail down"] = 0
        let p = ManagedProcess(name: "sail", config: ProcessConfig(command: "sail up -d", kind: .daemon, stop: "sail down"), directory: dir, launcher: launcher)
        p.start()
        #expect(p.state == .running)
        p.restart()
        #expect(launcher.launches.map(\.command).contains("sail down"))
        #expect(launcher.launches.filter { $0.command == "sail up -d" }.count == 2)
        #expect(p.state == .running)
    }

    @Test func daemonRestartWithoutStopCommandJustRelaunches() {
        let launcher = FakeProcessLauncher()
        launcher.immediateExit["sail up -d"] = 0
        let p = ManagedProcess(name: "sail", config: ProcessConfig(command: "sail up -d", kind: .daemon), directory: dir, launcher: launcher)
        p.start()
        #expect(p.state == .running)
        p.restart()
        #expect(launcher.launches.filter { $0.command == "sail up -d" }.count == 2)
        #expect(p.state == .running)
    }

    @Test func userStopSuppressesAutoRestart() {
        let launcher = FakeProcessLauncher()
        let p = ManagedProcess(name: "npm", config: ProcessConfig(command: "npm run dev", kind: .longRunning, autoRestart: true), directory: dir, launcher: launcher, graceInterval: .zero)
        p.start()
        p.stop()
        launcher.last.onExit(0) // exits due to the stop
        #expect(launcher.launches.count == 1) // not relaunched
        #expect(p.state == .idle)
    }

    @Test func longRunningRestartEscalatesThenRelaunches() {
        let launcher = FakeProcessLauncher()
        let p = ManagedProcess(name: "npm", config: ProcessConfig(command: "npm run dev", kind: .longRunning), directory: dir, launcher: launcher, graceInterval: .zero)
        p.start()
        #expect(launcher.launches.count == 1)
        p.restart()
        // Escalates (SIGINT first) rather than a lone SIGTERM, so a process that
        // ignores SIGTERM still exits.
        #expect(launcher.last.handle.signals.first == SIGINT)
        launcher.last.onExit(0) // process exits from the signal
        #expect(launcher.launches.count == 2) // relaunched once the exit lands
        #expect(p.state == .running)
    }

    @Test func longRunningStopCommandLaunchFailureEscalatesSignals() {
        let launcher = FakeProcessLauncher()
        launcher.failingCommands = ["stop.sh"]
        let p = ManagedProcess(name: "srv", config: ProcessConfig(command: "server", kind: .longRunning, stop: "stop.sh"), directory: dir, launcher: launcher, graceInterval: .zero)
        p.start()
        p.stop()
        // With a live handle, a failed stop command falls back to signalling it.
        #expect(launcher.last.handle.signals.first == SIGINT)
        #expect(p.state == .stopping)
    }

    @Test func crashLoopCapStopsRapidRestarts() {
        let launcher = FakeProcessLauncher()
        let clock = ContinuousClock.now
        let p = ManagedProcess(
            name: "npm", config: ProcessConfig(command: "npm run dev", kind: .longRunning, autoRestart: true),
            directory: dir, launcher: launcher, restartWindow: .seconds(60), now: { clock }
        )
        p.start()
        #expect(launcher.launches.count == 1)
        // Three rapid crashes within the window each relaunch; the fourth is capped.
        launcher.last.onExit(1); #expect(launcher.launches.count == 2)
        launcher.last.onExit(1); #expect(launcher.launches.count == 3)
        launcher.last.onExit(1); #expect(launcher.launches.count == 4)
        launcher.last.onExit(1)
        #expect(launcher.launches.count == 4) // capped, not relaunched
        #expect(p.state == .failed(1))
        // A manual start re-enables it.
        p.start()
        #expect(launcher.launches.count == 5)
    }

    @Test func crashesOutsideWindowDoNotHitCap() {
        let launcher = FakeProcessLauncher()
        var clock = ContinuousClock.now
        let p = ManagedProcess(
            name: "npm", config: ProcessConfig(command: "npm run dev", kind: .longRunning, autoRestart: true),
            directory: dir, launcher: launcher, restartWindow: .seconds(60), now: { clock }
        )
        p.start()
        // Four crashes spread far apart (window elapses between each) never cap.
        for expected in 2...5 {
            launcher.last.onExit(1)
            #expect(launcher.launches.count == expected)
            clock = clock.advanced(by: .seconds(120))
        }
    }
}
