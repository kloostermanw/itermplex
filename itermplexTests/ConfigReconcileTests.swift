import Testing
import Foundation
@testable import itermplex

@Suite struct ConfigReconcileTests {
    @Test func buildsConfigFromRowsPreservingOrder() {
        let rows = [
            TerminalRef(label: "Claude 1", sessionId: "s1", kind: .claude, slot: "claude1"),
            TerminalRef(label: "Terminal 1", sessionId: "s2", kind: .terminal, slot: "Terminal 1"),
            TerminalRef(label: "fix bug", sessionId: "s3", kind: .claude, slot: "claude2"),
        ]
        let config = ConfigReconcile.config(from: rows, name: "acme")
        #expect(config.name == "acme")
        #expect(config.agents.map(\.slot) == ["claude1", "claude2"])
        #expect(config.iterm == ["Terminal 1"])
    }

    @Test func importCreatesEmptyRowsInFileOrder() {
        let config = ItermplexConfig(
            name: nil,
            agents: [.init(slot: "claude1", type: "claude")],
            iterm: ["Terminal 1"]
        )
        let result = ConfigReconcile.apply(config, to: [])
        #expect(result.terminals.map(\.slot) == ["claude1", "Terminal 1"])
        #expect(result.terminals[0].kind == .claude)
        #expect(result.terminals[0].label == "claude1")
        #expect(result.terminals[0].sessionId == "")
        #expect(result.terminals[1].kind == .terminal)
        #expect(result.localOnly.isEmpty)
    }

    @Test func matchPreservesExistingRefIdSessionAndLabel() {
        let existing = TerminalRef(label: "fix auth", sessionId: "live-1", kind: .claude, slot: "claude1")
        let config = ItermplexConfig(name: nil, agents: [.init(slot: "claude1", type: "claude")], iterm: [])
        let result = ConfigReconcile.apply(config, to: [existing])
        #expect(result.terminals.count == 1)
        #expect(result.terminals[0].id == existing.id)
        #expect(result.terminals[0].sessionId == "live-1")
        #expect(result.terminals[0].label == "fix auth")
    }

    @Test func removedRunningRowKeptAsLocalOnly() {
        let running = TerminalRef(label: "Claude 2", sessionId: "live-2", kind: .claude, slot: "claude2")
        let config = ItermplexConfig(name: nil, agents: [], iterm: [])
        let result = ConfigReconcile.apply(config, to: [running])
        #expect(result.terminals.map(\.slot) == ["claude2"])
        #expect(result.localOnly == [running.id])
    }

    @Test func removedEmptyRowDropped() {
        let empty = TerminalRef(label: "claude2", sessionId: "", kind: .claude, slot: "claude2")
        let config = ItermplexConfig(name: nil, agents: [], iterm: [])
        let result = ConfigReconcile.apply(config, to: [empty])
        #expect(result.terminals.isEmpty)
        #expect(result.localOnly.isEmpty)
    }

    @Test func localOnlyRowsAppendedAfterFileRows() {
        let running = TerminalRef(label: "Claude 9", sessionId: "live", kind: .claude, slot: "claude9")
        let config = ItermplexConfig(
            name: nil,
            agents: [.init(slot: "claude1", type: "claude")],
            iterm: ["Terminal 1"]
        )
        let result = ConfigReconcile.apply(config, to: [running])
        #expect(result.terminals.map(\.slot) == ["claude1", "Terminal 1", "claude9"])
    }
}
