import Foundation

struct Project: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var terminals: [TerminalRef]
    var windowId: String?
    var terminalSeq: Int

    var name: String { url.lastPathComponent }

    /// True when the folder is a git repository (has a `.git` directory or file).
    var isGitRepository: Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

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
