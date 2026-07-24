import Foundation
import Observation

enum ClaudeRunState: Equatable {
    case running
    case exited
}

/// Errors surfaced by `ProjectStore`'s programmatic (MCP-facing) helpers.
enum StoreError: LocalizedError, Equatable {
    case unknownProject
    case unknownSession
    case terminal(String)

    var errorDescription: String? {
        switch self {
        case .unknownProject: return "No workspace has that id."
        case .unknownSession: return "No tracked terminal has that session id."
        case let .terminal(message): return message
        }
    }
}

@MainActor
@Observable
final class ProjectStore {
    private(set) var projects: [Project] = []
    var lastError: String?
    private(set) var gitInfo: [UUID: GitInfo] = [:]
    private(set) var attention: Set<UUID> = []
    private(set) var jobNames: [UUID: String] = [:]

    /// Subscribers to `workspaceChanges()`, keyed by subscription id.
    private var changeSubscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
    /// Whether `armChangeTracking()` currently has an active `withObservationTracking`
    /// registration pending; avoids re-arming redundantly.
    private var changeTrackingArmed = false

    /// Terminal ids that are tracked locally but absent from the on-disk config
    /// (kept alive after an external removal). Cleared when the config is written.
    private(set) var localOnlyTerminals: Set<UUID> = []

    /// The exact bytes last read from or written to each workspace's config file,
    /// used to ignore the app's own writes when the watcher fires.
    private var lastConfigData: [UUID: Data] = [:]

    /// Workspaces whose on-disk config differs from what the app last saw; drives
    /// the "config changed" affordance on the card.
    private(set) var configChangedOnDisk: Set<UUID> = []

    private var watchers: [UUID: ConfigWatcher] = [:]

    /// One `.git` watcher per workspace, giving snappy local git feedback
    /// alongside the poll. Started for every workspace; a no-op for non-repos.
    private var gitWatchers: [UUID: GitDirWatcher] = [:]

    /// Foreground job names that mean "no agent running, just a shell".
    /// Confirmed/extended by the design spike (Task 0).
    static let shellJobNames: Set<String> = [
        "zsh", "-zsh", "bash", "-bash", "fish", "-fish",
        "sh", "-sh", "tcsh", "-tcsh", "login", "dash", "-dash"
    ]

    func isShell(_ jobName: String) -> Bool {
        Self.shellJobNames.contains(jobName)
    }

    private let defaults: UserDefaults
    private let service: TerminalService
    private let gitProvider: GitInfoProviding
    let processes: ProcessSupervisor
    let testSupervisor: TestSupervisor
    private let storageKey = "itermplex.projects.bookmarks"
    private let badgeKey = "itermplex.showWorkspaceBadge"
    private let intervalsKey = "itermplex.checkIntervals"
    private let remoteEnabledKey = "itermplex.remote.enabled"
    private let mcpPortKey = "itermplex.mcpPort"
    private let remotePortKey = "itermplex.remotePort"

    /// Allowed range for the configurable server ports (unprivileged, valid TCP).
    static let portRange = 1024...65535
    private var refreshTask: Task<Void, Never>?
    private var schedule = CheckSchedule()

    /// Cached owner/repo per workspace, set by the gitSync check and read by the
    /// pullRequest/ciChecks checks (and the issue/PR URL composition) so those
    /// checks do not need to re-derive it themselves.
    private var ownerRepo: [UUID: (String?, String?)] = [:]

    /// When on, newly opened (or reopened) sessions get the workspace name as an
    /// iTerm2 badge. Off by default. Persisted; changing it affects future
    /// sessions only (existing sessions are not retroactively updated).
    var showWorkspaceBadge: Bool {
        didSet {
            guard showWorkspaceBadge != oldValue else { return }
            defaults.set(showWorkspaceBadge, forKey: badgeKey)
        }
    }

    /// Tier durations (seconds) for periodic checks. Clamped to valid ranges and
    /// persisted. Changing it takes effect on the next scheduler tick.
    var checkIntervals: CheckIntervals {
        didSet {
            let clamped = checkIntervals.clamped()
            if clamped != checkIntervals { checkIntervals = clamped; return } // re-enter with clamped value
            guard checkIntervals != oldValue else { return }
            defaults.set([checkIntervals.fast, checkIntervals.normal, checkIntervals.slow], forKey: intervalsKey)
        }
    }

    /// Whether the opt-in LAN remote terminal server runs. Off by default and
    /// persisted. `ContentView` starts/stops `RemoteServer` in response.
    var remoteEnabled: Bool {
        didSet {
            guard remoteEnabled != oldValue else { return }
            defaults.set(remoteEnabled, forKey: remoteEnabledKey)
        }
    }

    /// Port for the loopback MCP server. Clamped to `portRange` and persisted.
    /// Changing it takes effect when the MCP host is next (re)started.
    var mcpPort: Int {
        didSet {
            let clamped = Self.clampPort(mcpPort)
            if clamped != mcpPort { mcpPort = clamped; return }
            guard mcpPort != oldValue else { return }
            defaults.set(mcpPort, forKey: mcpPortKey)
        }
    }

    /// Port for the LAN remote terminal server. Clamped to `portRange` and
    /// persisted. Changing it takes effect when the server is next (re)started.
    var remotePort: Int {
        didSet {
            let clamped = Self.clampPort(remotePort)
            if clamped != remotePort { remotePort = clamped; return }
            guard remotePort != oldValue else { return }
            defaults.set(remotePort, forKey: remotePortKey)
        }
    }

    /// The shared secret required on every remote request and socket.
    let remoteToken: RemoteAccessToken

    /// Last error from starting the remote server (e.g. the port is in use), or
    /// nil when it started cleanly. Shown in Settings; not persisted.
    var remoteStartupError: String?

    private static func clampPort(_ port: Int) -> Int {
        min(max(port, portRange.lowerBound), portRange.upperBound)
    }

    private struct StoredProject: Codable {
        var id: UUID
        var bookmark: Data
        var terminals: [TerminalRef]
        var terminalSeq: Int
        var claudeSeq: Int
        var windowId: String?
        var collapsed: Bool

        init(id: UUID, bookmark: Data, terminals: [TerminalRef], terminalSeq: Int, claudeSeq: Int, windowId: String?, collapsed: Bool) {
            self.id = id
            self.bookmark = bookmark
            self.terminals = terminals
            self.terminalSeq = terminalSeq
            self.claudeSeq = claudeSeq
            self.windowId = windowId
            self.collapsed = collapsed
        }

        private enum CodingKeys: String, CodingKey {
            case id, bookmark, terminals, terminalSeq, claudeSeq, windowId, collapsed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Legacy records predate persisted ids; mint one so workspace ids
            // are stable from this launch onward.
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            bookmark = try container.decode(Data.self, forKey: .bookmark)
            terminals = try container.decode([TerminalRef].self, forKey: .terminals)
            terminalSeq = try container.decode(Int.self, forKey: .terminalSeq)
            claudeSeq = try container.decodeIfPresent(Int.self, forKey: .claudeSeq) ?? 0
            windowId = try container.decodeIfPresent(String.self, forKey: .windowId)
            collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        }
    }

    init(
        defaults: UserDefaults = .standard,
        service: TerminalService = ITermBridge(),
        gitProvider: GitInfoProviding = GitInfoService(),
        processSupervisor: ProcessSupervisor = ProcessSupervisor(),
        testSupervisor: TestSupervisor = TestSupervisor()
    ) {
        self.defaults = defaults
        self.service = service
        self.gitProvider = gitProvider
        self.processes = processSupervisor
        self.testSupervisor = testSupervisor
        self.showWorkspaceBadge = defaults.bool(forKey: badgeKey)
        if let arr = defaults.array(forKey: intervalsKey) as? [Int], arr.count == 3 {
            self.checkIntervals = CheckIntervals(fast: arr[0], normal: arr[1], slow: arr[2]).clamped()
        } else {
            self.checkIntervals = .default
        }
        self.remoteEnabled = defaults.bool(forKey: remoteEnabledKey)
        let storedMCPPort = defaults.integer(forKey: mcpPortKey)
        self.mcpPort = storedMCPPort == 0 ? MCPServerHost.defaultPort : Self.clampPort(storedMCPPort)
        let storedRemotePort = defaults.integer(forKey: remotePortKey)
        self.remotePort = storedRemotePort == 0 ? RemoteServer.defaultPort : Self.clampPort(storedRemotePort)
        self.remoteToken = RemoteAccessToken(defaults: defaults)
        load()
    }

    /// Registers a new subscriber for the coalesced workspace change signal. The
    /// returned stream yields once per change to `projects`, `gitInfo`, `attention`,
    /// or `jobNames`, letting a caller (e.g. the remote control channel) push a
    /// fresh snapshot without polling. Call `cancelWorkspaceChanges(_:)` with the
    /// returned id when done to release the subscription.
    func workspaceChanges() -> (id: UUID, stream: AsyncStream<Void>) {
        let id = UUID()
        let stream = AsyncStream<Void> { continuation in
            changeSubscribers[id] = continuation
        }
        if !changeTrackingArmed { changeTrackingArmed = true; armChangeTracking() }
        return (id, stream)
    }

    /// Unregisters a subscription previously created by `workspaceChanges()`.
    func cancelWorkspaceChanges(_ id: UUID) {
        changeSubscribers[id]?.finish()
        changeSubscribers[id] = nil
    }

    /// Observes the store's own sidebar-relevant properties. `withObservationTracking`
    /// fires `onChange` once when any accessed property next mutates; re-arm to keep
    /// observing. This turns Observation into a broadcast signal without editing
    /// every mutation site.
    private func armChangeTracking() {
        withObservationTracking {
            _ = projects
            _ = gitInfo
            _ = attention
            _ = jobNames
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                for continuation in self.changeSubscribers.values { continuation.yield(()) }
                if !self.changeSubscribers.isEmpty { self.armChangeTracking() } else { self.changeTrackingArmed = false }
            }
        }
    }

    func addProject(url: URL) {
        let standardized = url.standardizedFileURL
        guard !projects.contains(where: {
            $0.url.standardizedFileURL.path == standardized.path
        }) else { return }
        guard (try? standardized.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil
        )) != nil else { return }
        projects.append(Project(url: standardized))
        save()
        guard let added = projects.last else { return }
        if ConfigFile.exists(in: added.url) {
            reconcileWithFile(added.id)
            startWatching(added)
        }
        startGitWatching(added)
    }

    func remove(_ project: Project) {
        let terminalIds = project.terminals.map(\.id)
        projects.removeAll { $0.id == project.id }
        gitInfo[project.id] = nil
        for id in terminalIds {
            attention.remove(id)
            jobNames[id] = nil
        }
        stopWatching(project.id)
        stopGitWatching(project.id)
        processes.removeWorkspace(project.id)
        testSupervisor.removeWorkspace(project.id)
        lastConfigData[project.id] = nil
        configChangedOnDisk.remove(project.id)
        schedule.forget(projectId: project.id)
        ownerRepo[project.id] = nil
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        projects.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    func move(id: UUID, before targetId: UUID) {
        guard id != targetId,
              let from = projects.firstIndex(where: { $0.id == id }),
              projects.contains(where: { $0.id == targetId }) else { return }
        let item = projects.remove(at: from)
        guard let insertAt = projects.firstIndex(where: { $0.id == targetId }) else { return }
        projects.insert(item, at: insertAt)
        save()
    }

    func moveToEnd(id: UUID) {
        guard let from = projects.firstIndex(where: { $0.id == id }),
              from != projects.count - 1 else { return }
        let item = projects.remove(at: from)
        projects.append(item)
        save()
    }

    func openTerminal(for project: Project) async {
        await openSession(for: project, command: nil, kind: .terminal)
    }

    func openClaude(for project: Project) async {
        await openSession(for: project, command: "claude", kind: .claude)
    }

    private func openSession(for project: Project, command: String?, kind: TerminalKind) async {
        do {
            _ = try await openSessionThrowing(for: project, command: command, kind: kind)
        } catch {
            lastError = (error as? TerminalError)?.errorDescription
                ?? (error as? StoreError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Opens a session and returns the new terminal ref, propagating failures
    /// instead of routing them to `lastError`. The UI paths use
    /// `openSession`; the MCP router uses this.
    @discardableResult
    func openSessionThrowing(for project: Project, command: String?, kind: TerminalKind) async throws -> TerminalRef {
        guard let preIndex = projects.firstIndex(where: { $0.id == project.id }) else {
            throw StoreError.unknownProject
        }
        let folder = projects[preIndex].url
        let existingWindowId = projects[preIndex].windowId
        let badge = showWorkspaceBadge ? projects[preIndex].name : nil
        let handle: TerminalHandle
        do {
            handle = try await service.open(
                folder: folder, existingWindowId: existingWindowId, command: command, badge: badge
            )
        } catch {
            throw StoreError.terminal((error as? TerminalError)?.errorDescription ?? error.localizedDescription)
        }
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            throw StoreError.unknownProject
        }
        let label: String
        switch kind {
        case .terminal:
            projects[index].terminalSeq += 1
            label = "Terminal \(projects[index].terminalSeq)"
        case .claude:
            projects[index].claudeSeq += 1
            label = "Claude \(projects[index].claudeSeq)"
        }
        projects[index].windowId = handle.windowId
        let ref = TerminalRef(label: label, sessionId: handle.sessionId, kind: kind)
        projects[index].terminals.append(ref)
        save()
        emitConfig(for: projects[index].id)
        return ref
    }

    /// Focuses a tracked session by its iTerm2 session id. Throws
    /// `unknownSession` if no tracked terminal owns that id.
    @discardableResult
    func focus(sessionId: String) async throws -> FocusResult {
        guard let (p, t) = indexOfSession(sessionId) else { throw StoreError.unknownSession }
        let refId = projects[p].terminals[t].id
        attention.remove(refId)
        do {
            return try await service.focus(sessionId: sessionId)
        } catch {
            throw StoreError.terminal((error as? TerminalError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Closes a tracked session in iTerm2 and drops its ref from the store.
    func closeSession(sessionId: String) async throws {
        guard let (p, t) = indexOfSession(sessionId) else { throw StoreError.unknownSession }
        let refId = projects[p].terminals[t].id
        do {
            try await service.close(sessionId: sessionId)
        } catch {
            throw StoreError.terminal((error as? TerminalError)?.errorDescription ?? error.localizedDescription)
        }
        guard let (np, _) = indexOfSession(sessionId) else { return }
        projects[np].terminals.removeAll { $0.id == refId }
        attention.remove(refId)
        jobNames[refId] = nil
        localOnlyTerminals.remove(refId)
        save()
        emitConfig(for: projects[np].id)
    }

    func activate(_ ref: TerminalRef, in project: Project) async {
        guard let prePIndex = projects.firstIndex(where: { $0.id == project.id }),
              let preTIndex = projects[prePIndex].terminals.firstIndex(where: { $0.id == ref.id }) else { return }
        let sessionId = projects[prePIndex].terminals[preTIndex].sessionId
        let kind = projects[prePIndex].terminals[preTIndex].kind
        let folder = projects[prePIndex].url
        let existingWindowId = projects[prePIndex].windowId
        let badge = showWorkspaceBadge ? projects[prePIndex].name : nil
        attention.remove(ref.id)
        do {
            let result = try await service.focus(sessionId: sessionId)
            if result.found {
                // Live session: if it's a Claude row but claude is no longer
                // the foreground job (shell prompt / None jobName), re-run it.
                if kind == .claude, !claudeIsRunning(jobName: result.jobName) {
                    try await service.send(sessionId: sessionId, text: "claude\n")
                }
            } else {
                let command: String? = kind == .claude ? "claude" : nil
                let handle = try await service.open(
                    folder: folder, existingWindowId: existingWindowId, command: command, badge: badge
                )
                guard let pIndex = projects.firstIndex(where: { $0.id == project.id }),
                      let tIndex = projects[pIndex].terminals.firstIndex(where: { $0.id == ref.id }) else { return }
                projects[pIndex].windowId = handle.windowId
                projects[pIndex].terminals[tIndex].sessionId = handle.sessionId
                save()
            }
        } catch {
            lastError = (error as? TerminalError)?.errorDescription ?? error.localizedDescription
        }
    }

    func handle(_ event: MonitorEvent) {
        switch event {
        case .title(let sessionId, let name):
            guard let (p, t) = indexOfSession(sessionId) else { return }
            if projects[p].terminals[t].kind == .claude, !name.isEmpty,
               projects[p].terminals[t].label != name {
                projects[p].terminals[t].label = name
                save()
            }
        case .bell(let sessionId):
            guard let (p, t) = indexOfSession(sessionId) else { return }
            attention.insert(projects[p].terminals[t].id)
        case .job(let sessionId, let jobName):
            guard let (p, t) = indexOfSession(sessionId) else { return }
            jobNames[projects[p].terminals[t].id] = jobName
        case .terminated(let sessionId):
            guard let (p, t) = indexOfSession(sessionId) else { return }
            jobNames[projects[p].terminals[t].id] = ""
        }
    }

    /// Claude counts as running when the foreground job is a non-empty,
    /// non-shell name (the spike showed claude reports its version string,
    /// while a bare shell reports None/"" or a shell name).
    func claudeIsRunning(jobName: String?) -> Bool {
        guard let job = jobName, !job.isEmpty else { return false }
        return !isShell(job)
    }

    func runState(for ref: TerminalRef) -> ClaudeRunState {
        // No job info yet (monitor inactive or event not arrived): stay
        // optimistic so rows don't all read "exited" when monitoring is off.
        guard let job = jobNames[ref.id] else { return .running }
        return claudeIsRunning(jobName: job) ? .running : .exited
    }

    func clearAttention(_ ref: TerminalRef) {
        attention.remove(ref.id)
    }

    private func indexOfSession(_ sessionId: String) -> (Int, Int)? {
        for (p, project) in projects.enumerated() {
            if let t = project.terminals.firstIndex(where: { $0.sessionId == sessionId }) {
                return (p, t)
            }
        }
        return nil
    }

    func rename(_ ref: TerminalRef, in project: Project, to label: String) {
        guard let pIndex = projects.firstIndex(where: { $0.id == project.id }),
              let tIndex = projects[pIndex].terminals.firstIndex(where: { $0.id == ref.id }) else { return }
        projects[pIndex].terminals[tIndex].label = label
        if projects[pIndex].terminals[tIndex].kind == .terminal {
            projects[pIndex].terminals[tIndex].slot = label
        }
        save()
        emitConfig(for: projects[pIndex].id)
    }

    func removeTerminal(_ ref: TerminalRef, in project: Project) {
        guard let pIndex = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[pIndex].terminals.removeAll { $0.id == ref.id }
        attention.remove(ref.id)
        jobNames[ref.id] = nil
        localOnlyTerminals.remove(ref.id)
        save()
        emitConfig(for: project.id)
    }

    func toggleCollapsed(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].collapsed.toggle()
        let nowExpanded = !projects[index].collapsed
        save()
        if nowExpanded {
            let id = project.id
            for kind in CheckKind.allCases { schedule.reset(ScheduleKey(projectId: id, kind: kind)) }
            Task { await runDueChecks(now: Date()) }
        }
    }

    func closeTerminal(_ ref: TerminalRef, in project: Project) async {
        guard let prePIndex = projects.firstIndex(where: { $0.id == project.id }),
              let preTIndex = projects[prePIndex].terminals.firstIndex(where: { $0.id == ref.id }) else { return }
        let sessionId = projects[prePIndex].terminals[preTIndex].sessionId
        do {
            try await service.close(sessionId: sessionId)
            guard let pIndex = projects.firstIndex(where: { $0.id == project.id }) else { return }
            projects[pIndex].terminals.removeAll { $0.id == ref.id }
            localOnlyTerminals.remove(ref.id)
            save()
            emitConfig(for: project.id)
        } catch {
            lastError = (error as? TerminalError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - MCP helpers

    /// Sends raw text to a known session by its iTerm2 session id. Throws
    /// `unknownSession` if no tracked terminal owns that id.
    func sendText(_ text: String, toSessionId sessionId: String) async throws {
        guard indexOfSession(sessionId) != nil else { throw StoreError.unknownSession }
        do {
            try await service.send(sessionId: sessionId, text: text)
        } catch {
            throw StoreError.terminal((error as? TerminalError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Reads recent rendered output for a known session.
    func readOutput(sessionId: String, maxLines: Int) async throws -> String {
        guard indexOfSession(sessionId) != nil else { throw StoreError.unknownSession }
        do {
            return try await service.readOutput(sessionId: sessionId, maxLines: maxLines)
        } catch {
            throw StoreError.terminal((error as? TerminalError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Restarts a tracked session: closes the current session and opens a
    /// fresh one in the same window, re-running the kind's command (`claude`
    /// for claude rows). The terminal ref keeps its id, label, and kind; its
    /// `sessionId` is updated to the new session. Returns the updated ref.
    @discardableResult
    func restart(sessionId: String) async throws -> TerminalRef {
        guard let (p, t) = indexOfSession(sessionId) else { throw StoreError.unknownSession }
        let kind = projects[p].terminals[t].kind
        let folder = projects[p].url
        let existingWindowId = projects[p].windowId
        let badge = showWorkspaceBadge ? projects[p].name : nil
        let command: String? = kind == .claude ? "claude" : nil
        do {
            try? await service.close(sessionId: sessionId)
            let handle = try await service.open(
                folder: folder, existingWindowId: existingWindowId, command: command, badge: badge
            )
            guard let (np, nt) = indexOfSession(sessionId) else { throw StoreError.unknownSession }
            let oldId = projects[np].terminals[nt].id
            projects[np].windowId = handle.windowId
            projects[np].terminals[nt].sessionId = handle.sessionId
            attention.remove(oldId)
            jobNames[oldId] = nil
            save()
            return projects[np].terminals[nt]
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.terminal((error as? TerminalError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// True when a workspace's CI checks have pending/running entries.
    private func ciPending(_ projectId: UUID) -> Bool {
        (gitInfo[projectId]?.checks?.pending ?? 0) > 0
    }

    /// Builds the (key, tier) candidates for one workspace from live context.
    private func candidates(for project: Project) -> [(key: ScheduleKey, tier: CheckTier)] {
        let collapsed = project.collapsed
        let attention = attention.contains(project.id)
        return CheckKind.allCases.map { kind in
            let tier = checkTier(for: kind, collapsed: collapsed,
                                 ciPending: ciPending(project.id), needsAttention: attention)
            return (ScheduleKey(projectId: project.id, kind: kind), tier)
        }
    }

    /// The testable core of the scheduler: run every check that is due at `now`.
    func runDueChecks(now: Date) async {
        let all = projects.flatMap { candidates(for: $0) }
        let due = schedule.due(candidates: all, intervals: checkIntervals, now: now)
        // Record now up front so a slow check does not immediately re-fire next tick.
        for key in due { schedule.record(key, at: now) }
        for key in due { await run(key) }
    }

    /// Runs a single check and merges its slice into gitInfo (or process status).
    private func run(_ key: ScheduleKey) async {
        guard let url = projects.first(where: { $0.id == key.projectId })?.url else { return }
        switch key.kind {
        case .gitSync:
            guard let sync = await gitProvider.gitSync(for: url) else { gitInfo[key.projectId] = nil; return }
            ownerRepo[key.projectId] = (sync.owner, sync.repo)
            var info = gitInfo[key.projectId] ?? GitInfo(
                branch: "", behind: 0, ahead: 0, hasUpstream: false,
                upstreamRef: nil, baseAhead: 0, baseBehind: 0, hasBase: false, baseRef: nil,
                issueNumber: nil, prNumber: nil, issueURL: nil, prURL: nil, checks: nil
            )
            info.branch = sync.branch
            info.behind = sync.behind; info.ahead = sync.ahead; info.hasUpstream = sync.hasUpstream; info.upstreamRef = sync.upstreamRef
            info.baseAhead = sync.baseAhead; info.baseBehind = sync.baseBehind; info.hasBase = sync.hasBase; info.baseRef = sync.baseRef
            info.issueNumber = sync.issueNumber
            info.issueURL = Self.issueURL(owner: sync.owner, repo: sync.repo, issue: sync.issueNumber)
            info.prURL = Self.prURL(owner: sync.owner, repo: sync.repo, pr: info.prNumber)
            gitInfo[key.projectId] = info
        case .pullRequest:
            guard var info = gitInfo[key.projectId], !info.branch.isEmpty else { return }
            let pr = await gitProvider.pullRequestNumber(for: url, branch: info.branch)
            info.prNumber = pr
            let or = ownerRepo[key.projectId]
            info.prURL = Self.prURL(owner: or?.0, repo: or?.1, pr: pr)
            if pr == nil { info.checks = nil }
            gitInfo[key.projectId] = info
        case .ciChecks:
            guard var info = gitInfo[key.projectId], let pr = info.prNumber else { return }
            info.checks = await gitProvider.ciChecks(for: url, prNumber: pr)
            gitInfo[key.projectId] = info
        case .processStatus:
            processes.refreshStatusesForWorkspace(key.projectId)
        case .workingTree:
            guard let fingerprint = await gitProvider.workingTreeFingerprint(for: url) else { return }
            forwardWorkingTreeFingerprint(fingerprint, projectId: key.projectId)
        }
    }

    /// Forwards a freshly-computed working-tree fingerprint to the test
    /// supervisor, which stales any passing test whose baseline differs.
    func forwardWorkingTreeFingerprint(_ fingerprint: String, projectId: UUID) {
        testSupervisor.applyWorkingTreeFingerprint(fingerprint, projectId: projectId)
    }

    /// A local `.git` change (commit, checkout, branch edit) was observed by the
    /// watcher: mark the git-sync check due and run due checks now so branch and
    /// ahead/behind state update immediately instead of on the next poll. Only
    /// git-sync is poked; PR/CI stay on their poll cadence so frequent local
    /// commits do not trigger network lookups. A no-op for unknown workspaces.
    func gitDirDidChange(_ projectId: UUID, now: Date = Date()) async {
        guard projects.contains(where: { $0.id == projectId }) else { return }
        schedule.reset(ScheduleKey(projectId: projectId, kind: .gitSync))
        await runDueChecks(now: now)
    }

    /// Manual/Instant "run everything now": resets every schedule key so all
    /// checks are due, then runs them.
    func refreshAllGitInfo() async {
        for project in projects {
            for kind in CheckKind.allCases { schedule.reset(ScheduleKey(projectId: project.id, kind: kind)) }
        }
        await runDueChecks(now: Date())
    }

    static func issueURL(owner: String?, repo: String?, issue: Int?) -> URL? {
        guard let owner, let repo, let issue else { return nil }
        return URL(string: "https://github.com/\(owner)/\(repo)/issues/\(issue)")
    }
    static func prURL(owner: String?, repo: String?, pr: Int?) -> URL? {
        guard let owner, let repo, let pr else { return nil }
        return URL(string: "https://github.com/\(owner)/\(repo)/pull/\(pr)")
    }

    /// The `ITERMPLEX_*` variables exposed to a workspace's process commands.
    /// Workspace path and name are always present; git-derived values appear
    /// only when known (they lag a refresh and are absent for non-repos), so a
    /// command referencing one is blocked until its value is available (unless
    /// the process opts into `allow_empty_vars`).
    func processVariables(for projectId: UUID) -> [String: String] {
        guard let project = projects.first(where: { $0.id == projectId }) else { return [:] }
        var vars: [String: String] = [
            "ITERMPLEX_WORKSPACE_PATH": project.url.path,
            "ITERMPLEX_WORKSPACE_NAME": project.name,
        ]
        if let info = gitInfo[projectId] {
            if !info.branch.isEmpty { vars["ITERMPLEX_BRANCH"] = info.branch }
            if let upstream = info.upstreamRef { vars["ITERMPLEX_UPSTREAM"] = upstream }
            if let base = info.baseRef { vars["ITERMPLEX_BASE_BRANCH"] = base }
            if let issue = info.issueNumber { vars["ITERMPLEX_ISSUE_NUMBER"] = String(issue) }
            if let pr = info.prNumber { vars["ITERMPLEX_PR_NUMBER"] = String(pr) }
        }
        if let (owner, repo) = ownerRepo[projectId] {
            if let owner { vars["ITERMPLEX_OWNER"] = owner }
            if let repo { vars["ITERMPLEX_REPO"] = repo }
        }
        return vars
    }

    func startPeriodicRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runDueChecks(now: Date())
                let tick = await self?.checkIntervals.fast ?? 15
                try? await Task.sleep(nanoseconds: UInt64(tick) * 1_000_000_000)
            }
        }
    }

    // MARK: - Config sync

    func isSyncEnabled(_ project: Project) -> Bool {
        ConfigFile.exists(in: project.url)
    }

    /// Writes the workspace's current rows to a new `itermplex.json`, turning
    /// sync on. Records the written bytes so the watcher ignores this write.
    func enableConfigSync(for project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let config = ConfigReconcile.config(
            from: projects[index].terminals,
            name: projects[index].configName,
            processes: projects[index].configProcesses,
            tests: projects[index].configTests
        )
        do {
            lastConfigData[project.id] = try ConfigFile.write(config, in: projects[index].url)
            startWatching(projects[index])
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Rewrites the config file to mirror the workspace's current rows, but only
    /// when sync is on and the content actually changed. Clears local-only marks
    /// for the rewritten rows (they are now present in the file again).
    private func emitConfig(for projectId: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        let project = projects[index]
        guard ConfigFile.exists(in: project.url) else { return }
        let config = ConfigReconcile.config(
            from: project.terminals, name: project.configName, processes: project.configProcesses,
            tests: project.configTests
        )
        guard let data = try? config.encoded() else { return }
        if lastConfigData[projectId] == data { return }
        do {
            lastConfigData[projectId] = try ConfigFile.write(config, in: project.url)
            localOnlyTerminals.subtract(project.terminals.map(\.id))
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reads the workspace config and applies it to the current rows, preserving
    /// live sessions and keeping running rows dropped by the file as local-only.
    /// No-op when the file is absent (sync off).
    @discardableResult
    func reconcileWithFile(_ projectId: UUID) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return false }
        let url = projects[index].url
        let config: ItermplexConfig?
        do {
            config = try ConfigFile.read(in: url)
        } catch {
            lastError = error.localizedDescription
            return false
        }
        guard let config else { return false }
        let result = ConfigReconcile.apply(config, to: projects[index].terminals)
        projects[index].terminals = result.terminals
        projects[index].configName = config.name
        projects[index].configProcesses = config.processes
        projects[index].configTests = config.tests
        processes.apply(config, projectId: projectId, directory: url) { [weak self] in
            self?.processVariables(for: projectId) ?? [:]
        }
        testSupervisor.apply(config, projectId: projectId, directory: url) { [weak self] in
            self?.processVariables(for: projectId) ?? [:]
        }
        localOnlyTerminals.formUnion(result.localOnly)
        lastConfigData[projectId] = ConfigFile.rawData(in: url)
        save()
        return true
    }

    private func startWatching(_ project: Project) {
        guard watchers[project.id] == nil, ConfigFile.exists(in: project.url) else { return }
        let id = project.id
        let watcher = ConfigWatcher(folder: project.url) { [weak self] in
            self?.configFileDidChange(id)
        }
        watchers[id] = watcher
        watcher.start()
    }

    private func stopWatching(_ projectId: UUID) {
        watchers[projectId]?.stop()
        watchers[projectId] = nil
    }

    private func startGitWatching(_ project: Project) {
        guard gitWatchers[project.id] == nil else { return }
        let id = project.id
        let watcher = GitDirWatcher(workspace: project.url) { [weak self] in
            Task { await self?.gitDirDidChange(id) }
        }
        gitWatchers[id] = watcher
        watcher.start()
    }

    private func stopGitWatching(_ projectId: UUID) {
        gitWatchers[projectId]?.stop()
        gitWatchers[projectId] = nil
    }

    /// Watcher callback. If the file was deleted, forgets the last-seen bytes
    /// and clears the signal, but leaves the folder watcher armed so a later
    /// external re-create is still detected; otherwise raises the change
    /// signal when the on-disk bytes differ from what we last saw.
    func configFileDidChange(_ projectId: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        let url = projects[index].url
        guard ConfigFile.exists(in: url) else {
            lastConfigData[projectId] = nil
            configChangedOnDisk.remove(projectId)
            return
        }
        if ConfigFile.rawData(in: url) != lastConfigData[projectId] {
            configChangedOnDisk.insert(projectId)
        }
    }

    /// User applied a detected change: reconcile rows from the file and clear the
    /// signal.
    func applyConfigChanges(for project: Project) {
        if reconcileWithFile(project.id) {
            configChangedOnDisk.remove(project.id)
        }
    }

    private func load() {
        guard let dataArray = defaults.array(forKey: storageKey) as? [Data] else { return }
        let decoder = JSONDecoder()
        var loaded: [Project] = []
        for data in dataArray {
            guard let record = try? decoder.decode(StoredProject.self, from: data) else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: record.bookmark, options: [],
                relativeTo: nil, bookmarkDataIsStale: &isStale
            ) else { continue }
            loaded.append(Project(
                id: record.id,
                url: url.standardizedFileURL,
                terminals: record.terminals,
                windowId: record.windowId,
                terminalSeq: record.terminalSeq,
                claudeSeq: record.claudeSeq,
                collapsed: record.collapsed
            ))
        }
        projects = loaded
        for project in projects {
            if ConfigFile.exists(in: project.url) {
                reconcileWithFile(project.id)
                startWatching(project)
            }
            startGitWatching(project)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        let dataArray: [Data] = projects.compactMap { project in
            guard let bookmark = try? project.url.bookmarkData(
                options: [], includingResourceValuesForKeys: nil, relativeTo: nil
            ) else { return nil }
            let record = StoredProject(
                id: project.id,
                bookmark: bookmark,
                terminals: project.terminals,
                terminalSeq: project.terminalSeq,
                claudeSeq: project.claudeSeq,
                windowId: project.windowId,
                collapsed: project.collapsed
            )
            return try? encoder.encode(record)
        }
        defaults.set(dataArray, forKey: storageKey)
    }
}
