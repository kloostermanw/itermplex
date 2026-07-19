import Testing
import Foundation
@testable import itermplex

/// Minimal `GitInfoProviding` fake for the round-trip test below. Distinct
/// from `GitStoreTests.FakeGitInfoProvider` (which hardcodes `owner`/`repo`
/// to `nil`) because this test needs `issueURL`/`prURL` to actually resolve,
/// which requires a non-nil owner/repo.
private final class RoundTripGitInfoProvider: GitInfoProviding, @unchecked Sendable {
    var sync: GitSync
    var prNumber: Int?
    var checks: ChecksSummary?

    init(sync: GitSync, prNumber: Int?, checks: ChecksSummary?) {
        self.sync = sync
        self.prNumber = prNumber
        self.checks = checks
    }

    func gitSync(for folder: URL) async -> GitSync? { sync }
    func pullRequestNumber(for folder: URL, branch: String) async -> Int? { prNumber }
    func ciChecks(for folder: URL, prNumber: Int) async -> ChecksSummary? { checks }
}

@MainActor
@Suite struct RemoteWorkspaceDecoderTests {
    @Test func decodesWorkspacesGitAndTerminals() {
        let termId = UUID().uuidString
        let wsId = UUID().uuidString
        let snapshot: [String: Any] = [
            "type": "snapshot",
            "workspaces": [[
                "id": wsId, "name": "demo",
                "git": ["branch": "main", "ahead": 1, "behind": 0, "has_upstream": true,
                        "checks": ["passing": 2, "failing": 0, "cancelled": 0, "skipped": 0, "pending": 1, "summary": ""]],
                "terminals": [[
                    "id": termId, "session_id": "s1", "label": "shell", "kind": "terminal",
                    "run_state": "running", "needs_attention": true, "job_name": "vim",
                    "project_id": wsId, "project_name": "demo",
                ]],
            ]],
        ]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.projects.count == 1)
        #expect(out.projects[0].name == "demo")
        #expect(out.projects[0].terminals.first?.sessionId == "s1")
        let pid = out.projects[0].id
        #expect(out.gitInfo[pid]?.branch == "main")
        #expect(out.gitInfo[pid]?.checks?.pending == 1)
        let tid = out.projects[0].terminals[0].id
        #expect(out.runStates[tid] == .running)
        #expect(out.attention.contains(tid))
        #expect(out.jobNames[tid] == "vim")
    }

    // MARK: - Round trip: WorkspaceSerializer -> RemoteWorkspaceDecoder
    //
    // Builds a real `ProjectStore`, serializes it with the server's
    // `WorkspaceSerializer` (the actual producer used by `RemoteServer`), and
    // decodes the result back with `RemoteWorkspaceDecoder`. This is the test
    // that catches a key rename on either side: the DTOs in
    // `RemoteWireModels.swift` only work if their property names line up
    // with `WorkspaceSerializer`'s emitted keys, and this test fails loudly
    // (wrong/missing values) if they ever drift apart.

    @Test func roundTripsThroughSerializerAndDecoder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let provider = RoundTripGitInfoProvider(
            sync: GitSync(branch: "feature/round-trip", behind: 2, ahead: 5, hasUpstream: true,
                         upstreamRef: "origin/feature/round-trip", baseAhead: 1, baseBehind: 3,
                         hasBase: true, baseRef: "main", owner: "acme", repo: "widgets", issueNumber: 29),
            prNumber: 42,
            checks: ChecksSummary(passing: 3, failing: 1, cancelled: 0, skipped: 2, pending: 1)
        )
        let store = ProjectStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                 service: FakeTerminalService(), gitProvider: provider)
        store.addProject(url: folder)
        let project = store.projects[0]

        await store.refreshAllGitInfo()

        let ref = try await store.openSessionThrowing(for: project, command: "claude", kind: .claude)
        store.handle(.job(sessionId: ref.sessionId, jobName: "2.1.203")) // claude version string: running
        store.handle(.bell(sessionId: ref.sessionId))

        let workspacesValue = WorkspaceSerializer(store: store).workspaces()
        guard case let .object(members) = workspacesValue, let list = members["workspaces"] else {
            Issue.record("WorkspaceSerializer did not produce a workspaces array")
            return
        }
        // Same envelope shape RemoteServer's /control socket sends.
        let envelope = JSONValue.object(["type": .string("snapshot"), "workspaces": list])
        let text = envelope.encodedString()

        let decoded = RemoteWorkspaceDecoder.decode(snapshotText: text)

        #expect(decoded.projects.count == 1)
        let decodedProject = try #require(decoded.projects.first)
        #expect(decodedProject.id == project.id)
        #expect(decodedProject.name == project.name)
        #expect(decodedProject.terminals.count == 1)
        let decodedRef = try #require(decodedProject.terminals.first)
        #expect(decodedRef.id == ref.id)
        #expect(decodedRef.sessionId == ref.sessionId)
        #expect(decodedRef.label == ref.label)
        #expect(decodedRef.kind == .claude)

        let expected = try #require(store.gitInfo[project.id])
        let gitInfo = try #require(decoded.gitInfo[project.id])
        #expect(gitInfo.branch == expected.branch)
        #expect(gitInfo.ahead == expected.ahead)
        #expect(gitInfo.behind == expected.behind)
        #expect(gitInfo.hasUpstream == expected.hasUpstream)
        #expect(gitInfo.baseAhead == expected.baseAhead)
        #expect(gitInfo.baseBehind == expected.baseBehind)
        #expect(gitInfo.hasBase == expected.hasBase)
        #expect(gitInfo.issueNumber == expected.issueNumber)
        #expect(gitInfo.prNumber == expected.prNumber)
        #expect(gitInfo.issueURL == expected.issueURL)
        #expect(expected.issueURL != nil) // sanity: the field under test is actually populated
        #expect(gitInfo.prURL == expected.prURL)
        #expect(expected.prURL != nil)
        #expect(gitInfo.checks == expected.checks)
        #expect(expected.checks != nil)

        #expect(decoded.runStates[ref.id] == .running)
        #expect(decoded.attention.contains(ref.id))
        #expect(decoded.jobNames[ref.id] == "2.1.203")
    }

    // MARK: - Defensive branches

    @Test func workspaceMissingIdIsSkipped() {
        let snapshot: [String: Any] = ["workspaces": [["name": "no-id"]]]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.projects.isEmpty)
    }

    @Test func workspaceMissingNameIsSkipped() {
        let snapshot: [String: Any] = ["workspaces": [["id": UUID().uuidString]]]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.projects.isEmpty)
    }

    @Test func workspaceWithInvalidUUIDIsSkipped() {
        let snapshot: [String: Any] = ["workspaces": [["id": "not-a-uuid", "name": "bad-id"]]]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.projects.isEmpty)
    }

    @Test func terminalMissingSessionIdIsSkipped() {
        let wsId = UUID().uuidString
        let snapshot: [String: Any] = [
            "workspaces": [[
                "id": wsId, "name": "demo",
                "terminals": [["id": UUID().uuidString, "label": "shell"]],
            ]],
        ]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.projects.count == 1)
        #expect(out.projects[0].terminals.isEmpty)
    }

    @Test func terminalWithInvalidUUIDIsSkipped() {
        let wsId = UUID().uuidString
        let snapshot: [String: Any] = [
            "workspaces": [[
                "id": wsId, "name": "demo",
                "terminals": [["id": "not-a-uuid", "session_id": "s1", "label": "shell"]],
            ]],
        ]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.projects.count == 1)
        #expect(out.projects[0].terminals.isEmpty)
    }

    @Test func missingRunStateDefaultsToExited() {
        let wsId = UUID().uuidString
        let tid = UUID().uuidString
        let snapshot: [String: Any] = [
            "workspaces": [[
                "id": wsId, "name": "demo",
                "terminals": [["id": tid, "session_id": "s1", "label": "shell"]],
            ]],
        ]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.runStates[UUID(uuidString: tid)!] == .exited)
    }

    @Test func explicitExitedRunStateStaysExited() {
        let wsId = UUID().uuidString
        let tid = UUID().uuidString
        let snapshot: [String: Any] = [
            "workspaces": [[
                "id": wsId, "name": "demo",
                "terminals": [["id": tid, "session_id": "s1", "label": "shell", "run_state": "exited"]],
            ]],
        ]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.runStates[UUID(uuidString: tid)!] == .exited)
    }

    @Test func invalidKindFallsBackToTerminal() {
        let wsId = UUID().uuidString
        let tid = UUID().uuidString
        let snapshot: [String: Any] = [
            "workspaces": [[
                "id": wsId, "name": "demo",
                "terminals": [["id": tid, "session_id": "s1", "label": "shell", "kind": "not-a-kind"]],
            ]],
        ]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.projects[0].terminals.first?.kind == .terminal)
    }

    @Test func workspaceWithNoGitBlockHasNoGitInfo() {
        let wsId = UUID().uuidString
        let snapshot: [String: Any] = ["workspaces": [["id": wsId, "name": "demo"]]]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.projects.count == 1)
        #expect(out.gitInfo[UUID(uuidString: wsId)!] == nil)
    }

    @Test func baseAheadWithoutBaseBehindLeavesHasBaseFalse() {
        let wsId = UUID().uuidString
        let snapshot: [String: Any] = [
            "workspaces": [[
                "id": wsId, "name": "demo",
                "git": ["branch": "main", "ahead": 0, "behind": 0, "has_upstream": false, "base_ahead": 4],
            ]],
        ]
        let out = RemoteWorkspaceDecoder.decode(snapshot: snapshot)
        #expect(out.gitInfo[UUID(uuidString: wsId)!]?.hasBase == false)
    }
}
