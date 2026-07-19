import Foundation

struct DecodedRemoteWorkspaces: Equatable {
    var projects: [Project] = []
    var gitInfo: [UUID: GitInfo] = [:]
    var runStates: [UUID: ClaudeRunState] = [:]
    var attention: Set<UUID> = []
    var jobNames: [UUID: String] = [:]
}

enum RemoteWorkspaceDecoder {
    static func decode(snapshot json: [String: Any]) -> DecodedRemoteWorkspaces {
        var out = DecodedRemoteWorkspaces()
        guard let workspaces = json["workspaces"] as? [[String: Any]] else { return out }
        for ws in workspaces {
            guard let idString = ws["id"] as? String, let id = UUID(uuidString: idString),
                  let name = ws["name"] as? String else { continue }
            var terminals: [TerminalRef] = []
            for t in (ws["terminals"] as? [[String: Any]] ?? []) {
                guard let tidString = t["id"] as? String, let tid = UUID(uuidString: tidString),
                      let sid = t["session_id"] as? String, let label = t["label"] as? String else { continue }
                let kind = TerminalKind(rawValue: t["kind"] as? String ?? "terminal") ?? .terminal
                terminals.append(TerminalRef(id: tid, label: label, sessionId: sid, kind: kind, slot: label))
                out.runStates[tid] = (t["run_state"] as? String == "running") ? .running : .exited
                if t["needs_attention"] as? Bool == true { out.attention.insert(tid) }
                if let job = t["job_name"] as? String { out.jobNames[tid] = job }
            }
            let project = Project(id: id, url: URL(fileURLWithPath: "/remote/\(name)"),
                                  terminals: terminals, configName: name)
            out.projects.append(project)
            if let git = ws["git"] as? [String: Any] { out.gitInfo[id] = decodeGit(git) }
        }
        return out
    }

    private static func decodeGit(_ g: [String: Any]) -> GitInfo {
        var info = GitInfo(branch: g["branch"] as? String ?? "",
                           behind: g["behind"] as? Int ?? 0,
                           ahead: g["ahead"] as? Int ?? 0,
                           hasUpstream: g["has_upstream"] as? Bool ?? false,
                           issueNumber: g["issue_number"] as? Int,
                           prNumber: g["pr_number"] as? Int)
        if let ba = g["base_ahead"] as? Int, let bb = g["base_behind"] as? Int {
            info.baseAhead = ba; info.baseBehind = bb; info.hasBase = true
        }
        if let s = g["issue_url"] as? String { info.issueURL = URL(string: s) }
        if let s = g["pr_url"] as? String { info.prURL = URL(string: s) }
        if let c = g["checks"] as? [String: Any] {
            info.checks = ChecksSummary(passing: c["passing"] as? Int ?? 0,
                                        failing: c["failing"] as? Int ?? 0,
                                        cancelled: c["cancelled"] as? Int ?? 0,
                                        skipped: c["skipped"] as? Int ?? 0,
                                        pending: c["pending"] as? Int ?? 0)
        }
        return info
    }
}
