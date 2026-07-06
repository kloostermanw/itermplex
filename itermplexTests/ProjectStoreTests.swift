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
}
