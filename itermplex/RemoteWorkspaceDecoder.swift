import Foundation

struct DecodedRemoteWorkspaces: Equatable {
    var projects: [Project] = []
    var gitInfo: [UUID: GitInfo] = [:]
    var runStates: [UUID: ClaudeRunState] = [:]
    var attention: Set<UUID> = []
    var jobNames: [UUID: String] = [:]
}

enum RemoteWorkspaceDecoder {
    /// Decodes a `/control` WebSocket snapshot that the caller has already
    /// parsed into a `[String: Any]` (e.g. `RemoteWorkspaceStore.apply`, which
    /// gets there via `JSONSerialization.jsonObject`). Re-serializes to `Data`
    /// so the typed path below can run; on any failure returns an empty
    /// result rather than throwing, matching the tolerant contract this type
    /// has always had.
    static func decode(snapshot json: [String: Any]) -> DecodedRemoteWorkspaces {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else {
            return DecodedRemoteWorkspaces()
        }
        return decode(data: data)
    }

    /// Convenience for callers that already hold the raw snapshot JSON text
    /// (e.g. the serializer<->decoder round-trip test, which encodes a
    /// `WorkspaceSerializer` snapshot straight to a `String`). Avoids the
    /// pointless `String` -> `[String: Any]` -> `Data` round trip that
    /// `decode(snapshot:)` would otherwise require.
    static func decode(snapshotText text: String) -> DecodedRemoteWorkspaces {
        guard let data = text.data(using: .utf8) else { return DecodedRemoteWorkspaces() }
        return decode(data: data)
    }

    /// Shared typed-decode core. See `RemoteWireModels.swift` for the DTOs
    /// and the contract binding them to `WorkspaceSerializer`'s keys.
    private static func decode(data: Data) -> DecodedRemoteWorkspaces {
        var out = DecodedRemoteWorkspaces()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let snapshot = try? decoder.decode(ControlSnapshot.self, from: data) else { return out }

        for workspace in snapshot.workspaces.compactMap(\.base) {
            var terminals: [TerminalRef] = []
            for terminal in (workspace.terminals ?? []).compactMap(\.base) {
                let kind = TerminalKind(rawValue: terminal.kind ?? "terminal") ?? .terminal
                terminals.append(TerminalRef(id: terminal.id, label: terminal.label,
                                             sessionId: terminal.sessionId, kind: kind, slot: terminal.label))
                out.runStates[terminal.id] = (terminal.runState == "running") ? .running : .exited
                if terminal.needsAttention == true { out.attention.insert(terminal.id) }
                if let job = terminal.jobName { out.jobNames[terminal.id] = job }
            }
            out.projects.append(Self.remoteProject(id: workspace.id, name: workspace.name, terminals: terminals))
            if let git = workspace.git { out.gitInfo[workspace.id] = Self.gitInfo(from: git) }
        }
        return out
    }

    // MARK: - Remote `Project` synthesis contract
    //
    // `WorkspaceCardView` is shared between local and remote workspaces, and
    // it takes a `Project`. A remote workspace has no local folder, so this
    // builds a PLACEHOLDER `Project`: `url` is a synthetic value
    // ("/remote/<name>") that exists only to satisfy `Project`'s stored
    // `url` property and must NEVER be dereferenced (no `FileManager` calls,
    // no reading `isGitRepository`) — there is no filesystem folder at that
    // path. `configName` carries the real display name (`Project.name` reads
    // `configName` first). Git status for remote workspaces comes from the
    // separately decoded `GitInfo`, not from anything derived off `url`.
    private static func remoteProject(id: UUID, name: String, terminals: [TerminalRef]) -> Project {
        Project(id: id, url: URL(fileURLWithPath: "/remote/\(name)"), terminals: terminals, configName: name)
    }

    private static func gitInfo(from g: GitPayload) -> GitInfo {
        var info = GitInfo(branch: g.branch ?? "", behind: g.behind ?? 0, ahead: g.ahead ?? 0,
                           hasUpstream: g.hasUpstream ?? false,
                           issueNumber: g.issueNumber, prNumber: g.prNumber)
        if let baseAhead = g.baseAhead, let baseBehind = g.baseBehind {
            info.baseAhead = baseAhead
            info.baseBehind = baseBehind
            info.hasBase = true
        }
        if let s = g.issueUrl { info.issueURL = URL(string: s) }
        if let s = g.prUrl { info.prURL = URL(string: s) }
        if let c = g.checks {
            info.checks = ChecksSummary(passing: c.passing ?? 0, failing: c.failing ?? 0,
                                        cancelled: c.cancelled ?? 0, skipped: c.skipped ?? 0,
                                        pending: c.pending ?? 0)
        }
        return info
    }
}
