import Testing
import Foundation
@testable import itermplex

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
}
