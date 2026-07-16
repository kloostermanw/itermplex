import Testing
import Foundation
@testable import itermplex

@Suite @MainActor struct ProjectStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    private func makeTempFolder(named name: String) -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = base.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func addingFolderAppendsProjectWithFolderName() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "my-project"))
        #expect(store.projects.count == 1)
        #expect(store.projects.first?.name == "my-project")
    }

    @Test func addingSameFolderTwiceIsDeduped() {
        let store = ProjectStore(defaults: makeDefaults())
        let folder = makeTempFolder(named: "dupe")
        store.addProject(url: folder)
        store.addProject(url: folder)
        #expect(store.projects.count == 1)
    }

    @Test func projectsPersistAcrossStoreInstances() {
        let defaults = makeDefaults()
        let a = makeTempFolder(named: "alpha")
        let b = makeTempFolder(named: "beta")
        let store1 = ProjectStore(defaults: defaults)
        store1.addProject(url: a)
        store1.addProject(url: b)
        let store2 = ProjectStore(defaults: defaults)
        #expect(store2.projects.map(\.name) == ["alpha", "beta"])
    }

    @Test func projectIdsPersistAcrossStoreInstances() {
        let defaults = makeDefaults()
        let store1 = ProjectStore(defaults: defaults)
        store1.addProject(url: makeTempFolder(named: "alpha"))
        let originalId = store1.projects[0].id
        let store2 = ProjectStore(defaults: defaults)
        #expect(store2.projects.first?.id == originalId)
    }

    @Test func removingProjectDropsItFromList() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "keep"))
        store.addProject(url: makeTempFolder(named: "drop"))
        let drop = store.projects.first { $0.name == "drop" }!
        store.remove(drop)
        #expect(store.projects.map(\.name) == ["keep"])
    }

    @Test func removalPersists() {
        let defaults = makeDefaults()
        let store1 = ProjectStore(defaults: defaults)
        store1.addProject(url: makeTempFolder(named: "keep"))
        store1.addProject(url: makeTempFolder(named: "drop"))
        store1.remove(store1.projects.first { $0.name == "drop" }!)
        let store2 = ProjectStore(defaults: defaults)
        #expect(store2.projects.map(\.name) == ["keep"])
    }

    @Test func movingReordersAndPersists() {
        let defaults = makeDefaults()
        let store1 = ProjectStore(defaults: defaults)
        store1.addProject(url: makeTempFolder(named: "first"))
        store1.addProject(url: makeTempFolder(named: "second"))
        store1.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(store1.projects.map(\.name) == ["second", "first"])
        let store2 = ProjectStore(defaults: defaults)
        #expect(store2.projects.map(\.name) == ["second", "first"])
    }

    @Test func moveBeforeReordersProjects() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "a"))
        store.addProject(url: makeTempFolder(named: "b"))
        store.addProject(url: makeTempFolder(named: "c"))
        let a = store.projects[0].id
        let c = store.projects[2].id
        store.move(id: a, before: c)
        #expect(store.projects.map(\.name) == ["b", "a", "c"])
    }

    @Test func moveBeforeSelfIsNoOp() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "a"))
        store.addProject(url: makeTempFolder(named: "b"))
        let a = store.projects[0].id
        store.move(id: a, before: a)
        #expect(store.projects.map(\.name) == ["a", "b"])
    }

    @Test func moveBeforeMissingTargetIsNoOp() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "a"))
        store.addProject(url: makeTempFolder(named: "b"))
        let a = store.projects[0].id
        store.move(id: a, before: UUID())
        #expect(store.projects.map(\.name) == ["a", "b"])
    }

    @Test func moveBeforeMissingSourceIsNoOp() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "a"))
        store.addProject(url: makeTempFolder(named: "b"))
        let b = store.projects[1].id
        store.move(id: UUID(), before: b)
        #expect(store.projects.map(\.name) == ["a", "b"])
    }

    @Test func moveToEndMovesProjectToLast() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "a"))
        store.addProject(url: makeTempFolder(named: "b"))
        store.addProject(url: makeTempFolder(named: "c"))
        let a = store.projects[0].id
        store.moveToEnd(id: a)
        #expect(store.projects.map(\.name) == ["b", "c", "a"])
    }

    @Test func moveToEndOnLastIsNoOp() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "a"))
        store.addProject(url: makeTempFolder(named: "b"))
        let b = store.projects[1].id
        store.moveToEnd(id: b)
        #expect(store.projects.map(\.name) == ["a", "b"])
    }

    @Test func moveToEndMissingIsNoOp() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "a"))
        store.addProject(url: makeTempFolder(named: "b"))
        store.moveToEnd(id: UUID())
        #expect(store.projects.map(\.name) == ["a", "b"])
    }

    @Test func toggleCollapsedFlipsFlag() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "proj"))
        #expect(store.projects[0].collapsed == false)
        store.toggleCollapsed(store.projects[0])
        #expect(store.projects[0].collapsed == true)
        store.toggleCollapsed(store.projects[0])
        #expect(store.projects[0].collapsed == false)
    }

    @Test func collapsedStatePersistsAcrossStoreInstances() {
        let defaults = makeDefaults()
        let store1 = ProjectStore(defaults: defaults)
        store1.addProject(url: makeTempFolder(named: "proj"))
        store1.toggleCollapsed(store1.projects[0])
        let store2 = ProjectStore(defaults: defaults)
        #expect(store2.projects.first?.collapsed == true)
    }

    @Test func newProjectDefaultsToExpandedAfterReload() {
        let defaults = makeDefaults()
        let store1 = ProjectStore(defaults: defaults)
        store1.addProject(url: makeTempFolder(named: "proj"))
        let store2 = ProjectStore(defaults: defaults)
        #expect(store2.projects.first?.collapsed == false)
    }

    @Test func toggleCollapsedUnknownProjectIsNoOp() {
        let store = ProjectStore(defaults: makeDefaults())
        store.addProject(url: makeTempFolder(named: "proj"))
        let ghost = Project(url: makeTempFolder(named: "ghost"))
        store.toggleCollapsed(ghost)
        #expect(store.projects[0].collapsed == false)
    }
}

@Suite @MainActor struct ProcessStoreWiringTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    /// Writes an itermplex.json with one auto-start process into a temp dir and
    /// returns the folder URL.
    private func makeWorkspace(_ processes: [String: ProcessConfig]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ItermplexConfig(name: nil, agents: [], iterm: [], processes: processes)
        _ = try ConfigFile.write(config, in: dir)
        return dir
    }

    @Test func applyingConfigDrivesSupervisor() throws {
        let launcher = FakeProcessLauncher()
        let supervisor = ProcessSupervisor(launcher: launcher)
        let store = ProjectStore(
            defaults: makeDefaults(),
            service: FakeTerminalService(),
            gitProvider: FakeGitInfoProvider(),
            processSupervisor: supervisor
        )
        let dir = try makeWorkspace(["npm": ProcessConfig(command: "npm run dev", autoStart: true)])
        store.addProject(url: dir)
        let project = try #require(store.projects.first)
        store.applyConfigChanges(for: project)
        #expect(supervisor.process(projectId: project.id, name: "npm") != nil)
    }
}
