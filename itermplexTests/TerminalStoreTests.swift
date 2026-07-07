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
    var focusReturns = true
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

    func focus(sessionId: String) async throws -> Bool {
        if let error = errorToThrow { throw error }
        focusCalls.append(sessionId)
        return focusReturns
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

        fake.focusReturns = true
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

        fake.focusReturns = false
        await store.activate(store.projects[0].terminals[0], in: store.projects[0])
        #expect(fake.focusCalls == ["sess-A"])
        #expect(fake.openCalls.count == 2)
        #expect(store.projects[0].terminals[0].sessionId == "sess-B")
        #expect(store.projects[0].windowId == "win-2")
        #expect(store.projects[0].terminals[0].label == "Terminal 1") // label unchanged
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
}
