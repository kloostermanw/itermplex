import Testing
import Foundation
@testable import itermplex

@MainActor @Suite struct ConfigSyncStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    private func tempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func enableConfigSyncWritesCurrentRows() async throws {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "s1", windowId: "w1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        store.addProject(url: folder)
        await store.openClaude(for: store.projects[0])

        #expect(store.isSyncEnabled(store.projects[0]) == false)
        store.enableConfigSync(for: store.projects[0])
        #expect(store.isSyncEnabled(store.projects[0]) == true)

        let config = try ConfigFile.read(in: folder)
        #expect(config?.agents.map(\.slot) == ["Claude 1"])
    }

    @Test func structuralChangeWritesFileWhenEnabled() async throws {
        let fake = FakeTerminalService()
        fake.handles = [
            TerminalHandle(sessionId: "s1", windowId: "w1"),
            TerminalHandle(sessionId: "s2", windowId: "w1"),
        ]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        store.addProject(url: folder)
        store.enableConfigSync(for: store.projects[0])

        await store.openTerminal(for: store.projects[0])
        var config = try ConfigFile.read(in: folder)
        #expect(config?.iterm == ["Terminal 1"])

        store.rename(store.projects[0].terminals[0], in: store.projects[0], to: "server")
        config = try ConfigFile.read(in: folder)
        #expect(config?.iterm == ["server"])
    }

    @Test func noFileMeansNoWrite() async throws {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "s1", windowId: "w1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        store.addProject(url: folder)

        await store.openTerminal(for: store.projects[0])
        #expect(ConfigFile.exists(in: folder) == false)
    }

    @Test func addingWorkspaceWithFileScaffoldsRows() throws {
        let store = ProjectStore(defaults: makeDefaults(), service: FakeTerminalService())
        let folder = tempFolder()
        try ConfigFile.write(
            ItermplexConfig(
                name: nil,
                agents: [.init(slot: "claude1", type: "claude")],
                iterm: ["Terminal 1"]
            ),
            in: folder
        )
        store.addProject(url: folder)
        #expect(store.projects[0].terminals.map(\.slot) == ["claude1", "Terminal 1"])
        #expect(store.projects[0].terminals[0].kind == .claude)
        #expect(store.projects[0].terminals[0].sessionId == "")
    }

    @Test func reconcileKeepsRunningRowRemovedFromFileAsLocalOnly() async throws {
        let fake = FakeTerminalService()
        fake.handles = [
            TerminalHandle(sessionId: "s1", windowId: "w1"),
            TerminalHandle(sessionId: "s2", windowId: "w1"),
        ]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        store.addProject(url: folder)
        store.enableConfigSync(for: store.projects[0])
        await store.openClaude(for: store.projects[0]) // slot "Claude 1", session s1
        await store.openClaude(for: store.projects[0]) // slot "Claude 2", session s2

        // Simulate an external edit that drops Claude 2.
        try ConfigFile.write(
            ItermplexConfig(name: nil, agents: [.init(slot: "Claude 1", type: "claude")], iterm: []),
            in: folder
        )
        let dropped = store.projects[0].terminals[1].id
        store.reconcileWithFile(store.projects[0].id)

        #expect(store.projects[0].terminals.map(\.slot) == ["Claude 1", "Claude 2"])
        #expect(store.localOnlyTerminals.contains(dropped))
    }

    @Test func importedRowOpensOnActivate() async throws {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "opened-1", windowId: "w1")]
        fake.focusResult = FocusResult(found: false, jobName: nil)
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        try ConfigFile.write(
            ItermplexConfig(name: nil, agents: [], iterm: ["Terminal 1"]),
            in: folder
        )
        store.addProject(url: folder)

        await store.activate(store.projects[0].terminals[0], in: store.projects[0])
        #expect(store.projects[0].terminals[0].sessionId == "opened-1")
    }

    @Test func changeSignalSetWhenDiskDiffersAndClearedOnApply() async throws {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "s1", windowId: "w1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        store.addProject(url: folder)
        store.enableConfigSync(for: store.projects[0])
        let id = store.projects[0].id

        // External edit adds a terminal, then simulate the watcher firing.
        try ConfigFile.write(
            ItermplexConfig(name: nil, agents: [], iterm: ["Terminal 1"]),
            in: folder
        )
        store.configFileDidChange(id)
        #expect(store.configChangedOnDisk.contains(id))

        store.applyConfigChanges(for: store.projects[0])
        #expect(store.configChangedOnDisk.contains(id) == false)
        #expect(store.projects[0].terminals.map(\.slot) == ["Terminal 1"])
    }

    @Test func ownWriteDoesNotRaiseSignal() async throws {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "s1", windowId: "w1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        store.addProject(url: folder)
        store.enableConfigSync(for: store.projects[0])
        let id = store.projects[0].id

        await store.openTerminal(for: store.projects[0]) // app write updates lastConfigData
        store.configFileDidChange(id)
        #expect(store.configChangedOnDisk.contains(id) == false)
    }

    @Test func fileDeleteDisablesSync() async throws {
        let store = ProjectStore(defaults: makeDefaults(), service: FakeTerminalService())
        let folder = tempFolder()
        store.addProject(url: folder)
        store.enableConfigSync(for: store.projects[0])
        let id = store.projects[0].id

        try FileManager.default.removeItem(at: ConfigFile.url(in: folder))
        store.configFileDidChange(id)
        #expect(store.isSyncEnabled(store.projects[0]) == false)
        #expect(store.configChangedOnDisk.contains(id) == false)
    }

    @Test func configNameOverridesFolderName() throws {
        let store = ProjectStore(defaults: makeDefaults(), service: FakeTerminalService())
        let folder = tempFolder()
        try ConfigFile.write(
            ItermplexConfig(name: "laravel-test", agents: [], iterm: []),
            in: folder
        )
        store.addProject(url: folder)
        #expect(store.projects[0].name == "laravel-test")
    }

    @Test func noConfigNameUsesFolderName() throws {
        let store = ProjectStore(defaults: makeDefaults(), service: FakeTerminalService())
        let folder = tempFolder()
        try ConfigFile.write(
            ItermplexConfig(name: nil, agents: [], iterm: []),
            in: folder
        )
        store.addProject(url: folder)
        #expect(store.projects[0].name == folder.lastPathComponent)
    }

    @Test func committedNameSurvivesStructuralChange() async throws {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "s1", windowId: "w1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        try ConfigFile.write(
            ItermplexConfig(name: "keep-me", agents: [], iterm: ["Terminal 1"]),
            in: folder
        )
        store.addProject(url: folder)

        await store.openTerminal(for: store.projects[0])

        let config = try ConfigFile.read(in: folder)
        #expect(config?.name == "keep-me")
    }

    @Test func enableThenReconcileRoundTripsName() async throws {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "s1", windowId: "w1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        try ConfigFile.write(
            ItermplexConfig(name: "round-trip", agents: [], iterm: []),
            in: folder
        )
        store.addProject(url: folder)

        await store.openTerminal(for: store.projects[0])
        let config = try ConfigFile.read(in: folder)
        #expect(config?.name == "round-trip")
        #expect(store.projects[0].name == "round-trip")
    }

    @Test func recreatedFileAfterDeleteRaisesSignalAgain() async throws {
        let store = ProjectStore(defaults: makeDefaults(), service: FakeTerminalService())
        let folder = tempFolder()
        store.addProject(url: folder)
        store.enableConfigSync(for: store.projects[0])
        let id = store.projects[0].id

        try FileManager.default.removeItem(at: ConfigFile.url(in: folder))
        store.configFileDidChange(id)
        #expect(store.configChangedOnDisk.contains(id) == false)

        try ConfigFile.write(
            ItermplexConfig(name: nil, agents: [], iterm: ["Terminal 1"]),
            in: folder
        )
        store.configFileDidChange(id)
        #expect(store.configChangedOnDisk.contains(id))
    }

    @Test func applyDoesNotClearSignalWhenFileMalformed() async throws {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "s1", windowId: "w1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        store.addProject(url: folder)
        store.enableConfigSync(for: store.projects[0])
        let id = store.projects[0].id

        try ConfigFile.write(
            ItermplexConfig(name: nil, agents: [], iterm: ["Terminal 1"]),
            in: folder
        )
        store.configFileDidChange(id)
        #expect(store.configChangedOnDisk.contains(id))

        try Data("{ not json".utf8).write(to: ConfigFile.url(in: folder))
        store.applyConfigChanges(for: store.projects[0])
        #expect(store.configChangedOnDisk.contains(id))
        #expect(store.lastError != nil)
    }

    @Test func renamingClaudeKeepsSlotStable() async throws {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "s1", windowId: "w1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        let folder = tempFolder()
        store.addProject(url: folder)
        await store.openClaude(for: store.projects[0])

        let ref = store.projects[0].terminals[0]
        store.rename(ref, in: store.projects[0], to: "fix bug")

        #expect(store.projects[0].terminals[0].label == "fix bug")
        #expect(store.projects[0].terminals[0].slot == "Claude 1")
    }

    @Test func workspaceCardAcceptsSyncParameters() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "s1", windowId: "w1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: tempFolder())
        let project = store.projects[0]
        _ = WorkspaceCardView(
            project: project,
            collapsed: false,
            gitInfo: nil,
            runState: { store.runState(for: $0) },
            needsAttention: { store.attention.contains($0.id) },
            syncEnabled: store.isSyncEnabled(project),
            configChanged: store.configChangedOnDisk.contains(project.id),
            isLocalOnly: { store.localOnlyTerminals.contains($0.id) },
            onActivate: { _ in },
            onRenameTerminal: { _ in },
            onRemoveTerminal: { _ in },
            onCloseTerminal: { _ in },
            onOpenTerminal: {},
            onOpenClaude: {},
            onRemoveProject: {},
            onToggleCollapsed: {},
            onEnableSync: {},
            onApplyConfig: {},
            processes: [],
            onProcessStart: { _ in },
            onProcessStop: { _ in },
            onProcessRestart: { _ in },
            onProcessKill: { _ in },
            onOpenProcessLog: { _ in }
        )
    }
}
