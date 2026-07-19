import Testing
import Foundation
@testable import itermplex

@MainActor
@Suite struct ProjectStoreChangesTests {
    private func makeStore() -> ProjectStore {
        ProjectStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                     service: FakeTerminalService(), gitProvider: RecordingProviderStub())
    }
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func yieldsWhenProjectsChange() async {
        let store = makeStore()
        let (id, stream) = store.workspaceChanges()
        defer { store.cancelWorkspaceChanges(id) }
        var iterator = stream.makeAsyncIterator()
        store.addProject(url: tempDir())          // mutate a tracked property
        let value: Void? = await iterator.next()
        #expect(value != nil)
    }
}

// Minimal provider so the store can be built.
final class RecordingProviderStub: GitInfoProviding, @unchecked Sendable {
    func gitSync(for folder: URL) async -> GitSync? { nil }
    func pullRequestNumber(for folder: URL, branch: String) async -> Int? { nil }
    func ciChecks(for folder: URL, prNumber: Int) async -> ChecksSummary? { nil }
}
