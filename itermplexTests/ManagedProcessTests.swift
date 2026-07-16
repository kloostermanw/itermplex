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

    func launch(
        command: String,
        directory: URL,
        environment: [String: String],
        onOutput: @escaping @MainActor (String) -> Void,
        onExit: @escaping @MainActor (Int32) -> Void
    ) throws -> ProcessHandle {
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
}
