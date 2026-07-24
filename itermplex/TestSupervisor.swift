import Foundation
import Observation

/// Owns the test-processes of every workspace and reconciles them against the
/// on-disk `tests` definitions. Tests are run-to-completion checks executed by a
/// `ManagedProcess` in `short_running` mode; this type keeps them separate from
/// the regular process rows and adds manual run / run-all controls. The file is
/// the source of truth; this type never writes definitions back. Staleness (a
/// passing test going neutral when the working tree changes) is added in a later
/// task via `applyWorkingTreeFingerprint`.
@MainActor
@Observable
final class TestSupervisor {
    private var byProject: [UUID: [ManagedProcess]] = [:]
    private let launcher: ProcessLaunching

    init(launcher: ProcessLaunching = PTYProcessLauncher()) {
        self.launcher = launcher
    }

    func tests(for projectId: UUID) -> [ManagedProcess] {
        (byProject[projectId] ?? []).sorted { $0.name < $1.name }
    }

    func test(projectId: UUID, name: String) -> ManagedProcess? {
        byProject[projectId]?.first { $0.name == name }
    }

    /// A test is a `short_running` process. Maps a `TestConfig` to the
    /// `ProcessConfig` the runner understands.
    private func processConfig(_ def: TestConfig) -> ProcessConfig {
        ProcessConfig(command: def.command, kind: .shortRunning, env: def.env, allowEmptyVars: def.allowEmptyVars)
    }

    /// Reconciles test definitions for one workspace: adds new, updates existing,
    /// drops removed. Tests are not daemons and never auto-start, so a removed
    /// definition is simply dropped (any in-flight run is torn down).
    func apply(
        _ config: ItermplexConfig?,
        projectId: UUID,
        directory: URL,
        variables: @escaping @MainActor () -> [String: String] = { [:] }
    ) {
        let defined = config?.tests ?? [:]
        let current = byProject[projectId] ?? []

        var kept: [ManagedProcess] = []
        for test in current {
            if let def = defined[test.name] {
                test.updateDefinition(processConfig(def))
                kept.append(test)
            } else {
                test.kill() // drop: stop any in-flight run
            }
        }

        let existingNames = Set(kept.map(\.name))
        for (name, def) in defined where !existingNames.contains(name) {
            kept.append(ManagedProcess(
                name: name, config: processConfig(def), directory: directory,
                launcher: launcher, variables: variables
            ))
        }

        byProject[projectId] = kept
    }

    func run(projectId: UUID, name: String) {
        test(projectId: projectId, name: name)?.start()
    }

    func runAll(projectId: UUID) {
        for test in byProject[projectId] ?? [] { test.start() }
    }

    /// A `TestConfig` never defines a `stop` command, so `kill()` alone is the
    /// full teardown (unlike `ProcessSupervisor`, which also runs `stop()` for
    /// daemons).
    func removeWorkspace(_ projectId: UUID) {
        byProject[projectId]?.forEach { $0.kill() }
        byProject[projectId] = nil
    }
}
