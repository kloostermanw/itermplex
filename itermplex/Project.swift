import Foundation

struct Project: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var terminals: [TerminalRef]
    var windowId: String?
    var terminalSeq: Int
    var claudeSeq: Int
    var collapsed: Bool
    var configName: String?

    /// Display name: the config file's `name` override when present, else the
    /// folder name. `configName` is re-established from the file by
    /// `reconcileWithFile` on every launch; it is not persisted directly.
    var name: String { configName ?? url.lastPathComponent }

    /// True when the folder is a git repository (has a `.git` directory or file).
    var isGitRepository: Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    init(
        id: UUID = UUID(),
        url: URL,
        terminals: [TerminalRef] = [],
        windowId: String? = nil,
        terminalSeq: Int = 0,
        claudeSeq: Int = 0,
        collapsed: Bool = false,
        configName: String? = nil
    ) {
        self.id = id
        self.url = url
        self.terminals = terminals
        self.windowId = windowId
        self.terminalSeq = terminalSeq
        self.claudeSeq = claudeSeq
        self.collapsed = collapsed
        self.configName = configName
    }
}
