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
}
