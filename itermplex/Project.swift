import Foundation

struct Project: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var terminals: [TerminalRef]
    var windowId: String?
    var terminalSeq: Int

    var name: String { url.lastPathComponent }

    init(
        id: UUID = UUID(),
        url: URL,
        terminals: [TerminalRef] = [],
        windowId: String? = nil,
        terminalSeq: Int = 0
    ) {
        self.id = id
        self.url = url
        self.terminals = terminals
        self.windowId = windowId
        self.terminalSeq = terminalSeq
    }
}
