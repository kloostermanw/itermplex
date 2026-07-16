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
}
