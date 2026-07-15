import Testing
import Foundation
@testable import itermplex

@Suite struct ItermplexConfigTests {
    @Test func parsesSampleFile() throws {
        let json = Data("""
        {
          "name": "laravel-test",
          "agents": [
            { "slot": "claude1", "type": "claude" },
            { "slot": "claude2", "type": "claude" }
          ],
          "iterm": ["Terminal 1", "Terminal 2"]
        }
        """.utf8)
        let config = try ItermplexConfig.parse(json)
        #expect(config.name == "laravel-test")
        #expect(config.agents.map(\.slot) == ["claude1", "claude2"])
        #expect(config.agents.allSatisfy { $0.type == "claude" })
        #expect(config.iterm == ["Terminal 1", "Terminal 2"])
    }

    @Test func roundTripsThroughEncodeAndParse() throws {
        let config = ItermplexConfig(
            name: "acme",
            agents: [.init(slot: "claude1", type: "claude")],
            iterm: ["Terminal 1", "Terminal 2"]
        )
        let restored = try ItermplexConfig.parse(config.encoded())
        #expect(restored == config)
    }

    @Test func omitsNilNameWhenEncoding() throws {
        let config = ItermplexConfig(name: nil, agents: [], iterm: [])
        let text = String(decoding: try config.encoded(), as: UTF8.self)
        #expect(!text.contains("name"))
    }

    @Test func encodesArrayOrderStably() throws {
        let config = ItermplexConfig(
            name: nil,
            agents: [.init(slot: "b", type: "claude"), .init(slot: "a", type: "claude")],
            iterm: []
        )
        let restored = try ItermplexConfig.parse(config.encoded())
        #expect(restored.agents.map(\.slot) == ["b", "a"])
    }
}
