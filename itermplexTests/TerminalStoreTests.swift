import Testing
import Foundation
@testable import itermplex

private struct LegacyRef: Codable {
    var id: UUID
    var label: String
    var sessionId: String
}

private struct LegacyStored: Codable {
    var bookmark: Data
    var terminals: [LegacyRef]
    var terminalSeq: Int
    var windowId: String?
}

final class FakeTerminalService: TerminalService, @unchecked Sendable {
    var openCalls: [(folder: URL, existingWindowId: String?, command: String?)] = []
    var focusCalls: [String] = []
    var closeCalls: [String] = []
    var handles: [TerminalHandle] = []
    var focusResult = FocusResult(found: true, jobName: nil)
    var sendCalls: [(sessionId: String, text: String)] = []
    var errorToThrow: TerminalError?
    private var openIndex = 0

    func open(folder: URL, existingWindowId: String?, command: String?) async throws -> TerminalHandle {
        if let error = errorToThrow { throw error }
        openCalls.append((folder, existingWindowId, command))
        let handle = openIndex < handles.count
            ? handles[openIndex]
            : TerminalHandle(sessionId: "sess-\(openIndex + 1)", windowId: "win-1")
        openIndex += 1
        return handle
    }

    func focus(sessionId: String) async throws -> FocusResult {
        if let error = errorToThrow { throw error }
        focusCalls.append(sessionId)
        return focusResult
    }

    func send(sessionId: String, text: String) async throws {
        if let error = errorToThrow { throw error }
        sendCalls.append((sessionId, text))
    }

    func close(sessionId: String) async throws {
        if let error = errorToThrow { throw error }
        closeCalls.append(sessionId)
    }
}

@Suite @MainActor struct TerminalStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    private func makeTempFolder(named name: String) -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = base.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func newProjectHasNoTerminals() {
        let project = Project(url: URL(fileURLWithPath: "/tmp/x"))
        #expect(project.terminals.isEmpty)
        #expect(project.windowId == nil)
        #expect(project.terminalSeq == 0)
        #expect(project.claudeSeq == 0)
    }

    @Test func decodesLegacyTerminalRefWithoutKind() throws {
        let json = Data("""
        {"id":"\(UUID().uuidString)","label":"Terminal 1","sessionId":"sess-A"}
        """.utf8)
        let ref = try JSONDecoder().decode(TerminalRef.self, from: json)
        #expect(ref.kind == .terminal)
        #expect(ref.label == "Terminal 1")
        #expect(ref.sessionId == "sess-A")
    }

    @Test func encodesAndDecodesClaudeKind() throws {
        let ref = TerminalRef(label: "Claude 1", sessionId: "s", kind: .claude)
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(TerminalRef.self, from: data)
        #expect(decoded.kind == .claude)
    }

    @Test func openTerminalAppendsNumberedRefsAndTracksWindow() async {
        let fake = FakeTerminalService()
        fake.handles = [
            TerminalHandle(sessionId: "sess-A", windowId: "win-1"),
            TerminalHandle(sessionId: "sess-B", windowId: "win-1"),
        ]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))

        await store.openTerminal(for: store.projects[0])
        #expect(store.projects[0].terminals.map(\.label) == ["Terminal 1"])
        #expect(store.projects[0].terminals[0].sessionId == "sess-A")
        #expect(store.projects[0].windowId == "win-1")
        #expect(store.projects[0].terminalSeq == 1)

        await store.openTerminal(for: store.projects[0])
        #expect(store.projects[0].terminals.map(\.label) == ["Terminal 1", "Terminal 2"])
        #expect(fake.openCalls.count == 2)
        #expect(fake.openCalls[1].existingWindowId == "win-1")
    }

    @Test func openClaudeAppendsClaudeRefAndRunsClaude() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))

        await store.openClaude(for: store.projects[0])
        #expect(store.projects[0].terminals.map(\.label) == ["Claude 1"])
        #expect(store.projects[0].terminals[0].kind == .claude)
        #expect(store.projects[0].terminals[0].sessionId == "sess-A")
        #expect(store.projects[0].claudeSeq == 1)
        #expect(fake.openCalls.count == 1)
        #expect(fake.openCalls[0].command == "claude")
    }

    @Test func openTerminalPassesNilCommand() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))

        await store.openTerminal(for: store.projects[0])
        #expect(store.projects[0].terminals[0].kind == .terminal)
        #expect(fake.openCalls[0].command == nil)
    }

    @Test func terminalAndClaudeUseIndependentNumbering() async {
        let fake = FakeTerminalService()
        fake.handles = [
            TerminalHandle(sessionId: "s1", windowId: "win-1"),
            TerminalHandle(sessionId: "s2", windowId: "win-1"),
            TerminalHandle(sessionId: "s3", windowId: "win-1"),
            TerminalHandle(sessionId: "s4", windowId: "win-1"),
        ]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))

        await store.openTerminal(for: store.projects[0])
        await store.openClaude(for: store.projects[0])
        await store.openTerminal(for: store.projects[0])
        await store.openClaude(for: store.projects[0])
        #expect(store.projects[0].terminals.map(\.label)
            == ["Terminal 1", "Claude 1", "Terminal 2", "Claude 2"])
    }

    @Test func terminalsPersistAcrossStoreInstances() async {
        let defaults = makeDefaults()
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store1 = ProjectStore(defaults: defaults, service: fake)
        store1.addProject(url: makeTempFolder(named: "proj"))
        await store1.openTerminal(for: store1.projects[0])

        let store2 = ProjectStore(defaults: defaults, service: FakeTerminalService())
        #expect(store2.projects.count == 1)
        #expect(store2.projects[0].terminals.map(\.label) == ["Terminal 1"])
        #expect(store2.projects[0].terminals[0].sessionId == "sess-A")
        #expect(store2.projects[0].windowId == "win-1")
        #expect(store2.projects[0].terminalSeq == 1)
    }

    @Test func failedOpenSetsLastErrorAndLeavesModelUnchanged() async {
        let fake = FakeTerminalService()
        fake.errorToThrow = .apiDisabled
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))

        await store.openTerminal(for: store.projects[0])
        #expect(store.projects[0].terminals.isEmpty)
        #expect(store.lastError == TerminalError.apiDisabled.errorDescription)
    }

    @Test func activateLiveSessionOnlyFocuses() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openTerminal(for: store.projects[0])

        fake.focusResult = FocusResult(found: true, jobName: nil)
        await store.activate(store.projects[0].terminals[0], in: store.projects[0])
        #expect(fake.focusCalls == ["sess-A"])
        #expect(fake.openCalls.count == 1) // no reopen
    }

    @Test func activateDeadSessionReopensAndRebinds() async {
        let fake = FakeTerminalService()
        fake.handles = [
            TerminalHandle(sessionId: "sess-A", windowId: "win-1"),
            TerminalHandle(sessionId: "sess-B", windowId: "win-2"),
        ]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openTerminal(for: store.projects[0])

        fake.focusResult = FocusResult(found: false, jobName: nil)
        await store.activate(store.projects[0].terminals[0], in: store.projects[0])
        #expect(fake.focusCalls == ["sess-A"])
        #expect(fake.openCalls.count == 2)
        #expect(store.projects[0].terminals[0].sessionId == "sess-B")
        #expect(store.projects[0].windowId == "win-2")
        #expect(store.projects[0].terminals[0].label == "Terminal 1") // label unchanged
    }

    @Test func activateClaudeInShellRestartsClaude() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openClaude(for: store.projects[0])

        fake.focusResult = FocusResult(found: true, jobName: "zsh")
        await store.activate(store.projects[0].terminals[0], in: store.projects[0])
        #expect(fake.sendCalls.count == 1)
        #expect(fake.sendCalls[0] == ("sess-A", "claude\n"))
        #expect(fake.openCalls.count == 1) // no reopen; session was alive
    }

    @Test func activateClaudeWhileRunningDoesNotRestart() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openClaude(for: store.projects[0])

        fake.focusResult = FocusResult(found: true, jobName: "2.1.203") // claude version
        await store.activate(store.projects[0].terminals[0], in: store.projects[0])
        #expect(fake.sendCalls.isEmpty)
    }

    @Test func activateClaudeWithNilJobRestarts() async {
        // Bare shell reports jobName == nil (no shell integration); treat as exited.
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openClaude(for: store.projects[0])

        fake.focusResult = FocusResult(found: true, jobName: nil)
        await store.activate(store.projects[0].terminals[0], in: store.projects[0])
        #expect(fake.sendCalls.count == 1)
        #expect(fake.sendCalls[0] == ("sess-A", "claude\n"))
    }

    @Test func activateDeadClaudeReopensRunningClaude() async {
        let fake = FakeTerminalService()
        fake.handles = [
            TerminalHandle(sessionId: "sess-A", windowId: "win-1"),
            TerminalHandle(sessionId: "sess-B", windowId: "win-1"),
        ]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openClaude(for: store.projects[0])

        fake.focusResult = FocusResult(found: false, jobName: nil)
        await store.activate(store.projects[0].terminals[0], in: store.projects[0])
        #expect(fake.openCalls.count == 2)
        #expect(fake.openCalls[1].command == "claude")
        #expect(store.projects[0].terminals[0].sessionId == "sess-B")
    }

    @Test func activateDeadTerminalReopensPlainShell() async {
        let fake = FakeTerminalService()
        fake.handles = [
            TerminalHandle(sessionId: "sess-A", windowId: "win-1"),
            TerminalHandle(sessionId: "sess-B", windowId: "win-1"),
        ]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openTerminal(for: store.projects[0])

        fake.focusResult = FocusResult(found: false, jobName: nil)
        await store.activate(store.projects[0].terminals[0], in: store.projects[0])
        #expect(fake.openCalls.count == 2)
        #expect(fake.openCalls[1].command == nil)
    }

    @Test func renameChangesLabelAndPersists() async {
        let defaults = makeDefaults()
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store1 = ProjectStore(defaults: defaults, service: fake)
        store1.addProject(url: makeTempFolder(named: "proj"))
        await store1.openTerminal(for: store1.projects[0])

        store1.rename(store1.projects[0].terminals[0], in: store1.projects[0], to: "server")
        #expect(store1.projects[0].terminals[0].label == "server")

        let store2 = ProjectStore(defaults: defaults, service: FakeTerminalService())
        #expect(store2.projects[0].terminals[0].label == "server")
    }

    @Test func removeTerminalForgetsWithoutClosing() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openTerminal(for: store.projects[0])

        store.removeTerminal(store.projects[0].terminals[0], in: store.projects[0])
        #expect(store.projects[0].terminals.isEmpty)
        #expect(fake.closeCalls.isEmpty)
    }

    @Test func closeTerminalClosesSessionThenForgets() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openTerminal(for: store.projects[0])

        await store.closeTerminal(store.projects[0].terminals[0], in: store.projects[0])
        #expect(fake.closeCalls == ["sess-A"])
        #expect(store.projects[0].terminals.isEmpty)
    }

    @Test func closeTerminalFailureKeepsRef() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openTerminal(for: store.projects[0])

        fake.errorToThrow = .bridgeFailed("boom")
        await store.closeTerminal(store.projects[0].terminals[0], in: store.projects[0])
        #expect(store.projects[0].terminals.count == 1)
        #expect(store.lastError == "boom")
    }

    @Test func renameToNonEmptyLabelUpdatesRef() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openTerminal(for: store.projects[0])
        store.rename(store.projects[0].terminals[0], in: store.projects[0], to: "api")
        #expect(store.projects[0].terminals[0].label == "api")
    }

    @Test func loadsLegacyProjectWithoutClaudeSeqOrKind() throws {
        let defaults = makeDefaults()
        let folder = makeTempFolder(named: "proj")
        let bookmark = try folder.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil
        )
        let legacy = LegacyStored(
            bookmark: bookmark,
            terminals: [LegacyRef(id: UUID(), label: "Terminal 1", sessionId: "sess-A")],
            terminalSeq: 1,
            windowId: "win-1"
        )
        let data = try JSONEncoder().encode(legacy)
        // Storage key is private to ProjectStore; kept in sync intentionally.
        defaults.set([data], forKey: "itermplex.projects.bookmarks")

        let store = ProjectStore(defaults: defaults, service: FakeTerminalService())
        #expect(store.projects.count == 1)
        #expect(store.projects[0].terminals.map(\.label) == ["Terminal 1"])
        #expect(store.projects[0].terminals[0].kind == .terminal)
        #expect(store.projects[0].terminalSeq == 1)
        #expect(store.projects[0].claudeSeq == 0)
    }

    @Test func titleEventUpdatesClaudeLabel() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openClaude(for: store.projects[0])

        store.handle(.title(sessionId: "sess-A", name: "refactor parser"))
        #expect(store.projects[0].terminals[0].label == "refactor parser")
    }

    @Test func titleEventIgnoredForTerminalKind() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openTerminal(for: store.projects[0])

        store.handle(.title(sessionId: "sess-A", name: "should not apply"))
        #expect(store.projects[0].terminals[0].label == "Terminal 1")
    }

    @Test func titleEventForUnknownSessionIgnored() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openClaude(for: store.projects[0])

        store.handle(.title(sessionId: "nope", name: "x"))
        #expect(store.projects[0].terminals[0].label == "Claude 1")
    }

    @Test func bellEventAddsAttentionAndActivateClears() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        fake.focusResult = FocusResult(found: true, jobName: "node")
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openClaude(for: store.projects[0])
        let ref = store.projects[0].terminals[0]

        store.handle(.bell(sessionId: "sess-A"))
        #expect(store.attention.contains(ref.id))

        await store.activate(ref, in: store.projects[0])
        #expect(!store.attention.contains(ref.id))
    }

    @Test func jobEventDrivesRunState() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openClaude(for: store.projects[0])
        let ref = store.projects[0].terminals[0]

        #expect(store.runState(for: ref) == .running) // no info yet -> optimistic
        store.handle(.job(sessionId: "sess-A", jobName: "2.1.203")) // claude version string
        #expect(store.runState(for: ref) == .running)
        store.handle(.job(sessionId: "sess-A", jobName: "zsh"))
        #expect(store.runState(for: ref) == .exited)
        store.handle(.job(sessionId: "sess-A", jobName: "")) // bare shell, no shell integration
        #expect(store.runState(for: ref) == .exited)
    }

    @Test func terminatedEventMarksExitedAndKeepsRef() async {
        let fake = FakeTerminalService()
        fake.handles = [TerminalHandle(sessionId: "sess-A", windowId: "win-1")]
        let store = ProjectStore(defaults: makeDefaults(), service: fake)
        store.addProject(url: makeTempFolder(named: "proj"))
        await store.openClaude(for: store.projects[0])
        let ref = store.projects[0].terminals[0]

        store.handle(.terminated(sessionId: "sess-A"))
        #expect(store.runState(for: ref) == .exited)
        #expect(store.projects[0].terminals.count == 1)
    }
}
