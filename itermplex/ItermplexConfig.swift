import Foundation

/// Value model for the committed `itermplex.json` file. Pure: it knows how to
/// parse and emit itself and holds no I/O or app state.
struct ItermplexConfig: Codable, Equatable {
    struct Agent: Codable, Equatable {
        var slot: String
        var type: String
    }

    var name: String?
    var agents: [Agent]
    var iterm: [String]
    var processes: [String: ProcessConfig]?
    var tests: [String: TestConfig]?

    init(name: String?, agents: [Agent], iterm: [String], processes: [String: ProcessConfig]? = nil, tests: [String: TestConfig]? = nil) {
        self.name = name
        self.agents = agents
        self.iterm = iterm
        self.processes = processes
        self.tests = tests
    }

    static func parse(_ data: Data) throws -> ItermplexConfig {
        try JSONDecoder().decode(ItermplexConfig.self, from: data)
    }

    /// Pretty, key-sorted JSON with a trailing newline so the file is stable and
    /// diff friendly. Array order is preserved as written.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
