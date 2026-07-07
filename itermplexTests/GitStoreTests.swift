import Testing
import Foundation
@testable import itermplex

final class FakeGitInfoProvider: GitInfoProviding, @unchecked Sendable {
    var results: [String: GitInfo] = [:]   // keyed by standardized folder path
    func info(for folder: URL) async -> GitInfo? {
        results[folder.standardizedFileURL.path]
    }
}

@Suite @MainActor struct GitStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    private func makeTempFolder(named name: String) -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = base.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func gitInfo(behind: Int, ahead: Int, pr: Int?) -> GitInfo {
        GitInfo(branch: "feature/issue-1", behind: behind, ahead: ahead, hasUpstream: true,
                issueNumber: 1, prNumber: pr, issueURL: nil, prURL: nil)
    }

    @Test func refreshPopulatesGitInfoByProjectId() async {
        let provider = FakeGitInfoProvider()
        let store = ProjectStore(defaults: makeDefaults(), service: FakeTerminalService(), gitProvider: provider)
        let folder = makeTempFolder(named: "proj")
        store.addProject(url: folder)
        provider.results[folder.standardizedFileURL.path] = gitInfo(behind: 2, ahead: 3, pr: 9)

        await store.refreshAllGitInfo()
        let id = store.projects[0].id
        #expect(store.gitInfo[id]?.behind == 2)
        #expect(store.gitInfo[id]?.ahead == 3)
        #expect(store.gitInfo[id]?.prNumber == 9)
    }

    @Test func refreshWithNilResultClearsEntry() async {
        let provider = FakeGitInfoProvider()
        let store = ProjectStore(defaults: makeDefaults(), service: FakeTerminalService(), gitProvider: provider)
        let folder = makeTempFolder(named: "proj")
        store.addProject(url: folder)
        let id = store.projects[0].id
        provider.results[folder.standardizedFileURL.path] = gitInfo(behind: 1, ahead: 1, pr: nil)
        await store.refreshAllGitInfo()
        #expect(store.gitInfo[id] != nil)

        provider.results.removeValue(forKey: folder.standardizedFileURL.path)
        await store.refreshAllGitInfo()
        #expect(store.gitInfo[id] == nil)
    }
}
