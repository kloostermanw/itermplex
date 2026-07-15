import Testing
import Foundation
@testable import itermplex

@Suite struct ConfigFileTests {
    private func tempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func existsIsFalseWhenNoFile() {
        #expect(ConfigFile.exists(in: tempFolder()) == false)
    }

    @Test func readReturnsNilWhenAbsent() throws {
        #expect(try ConfigFile.read(in: tempFolder()) == nil)
    }

    @Test func writeThenReadRoundTrips() throws {
        let folder = tempFolder()
        let config = ItermplexConfig(
            name: "acme",
            agents: [.init(slot: "claude1", type: "claude")],
            iterm: ["Terminal 1"]
        )
        let written = try ConfigFile.write(config, in: folder)
        #expect(ConfigFile.exists(in: folder))
        #expect(try ConfigFile.read(in: folder) == config)
        #expect(ConfigFile.rawData(in: folder) == written)
    }

    @Test func writeUsesExactFileName() throws {
        let folder = tempFolder()
        try ConfigFile.write(ItermplexConfig(name: nil, agents: [], iterm: []), in: folder)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("itermplex.json").path))
    }
}
