import Foundation

/// Reads and writes the workspace `itermplex.json`. Wraps security-scoped
/// access so it works with the app's bookmarked folders and with plain URLs in
/// tests (where `startAccessingSecurityScopedResource` returns false).
enum ConfigFile {
    static let fileName = "itermplex.json"

    static func url(in folder: URL) -> URL {
        folder.appendingPathComponent(fileName)
    }

    static func exists(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(in: folder).path)
    }

    static func read(in folder: URL) throws -> ItermplexConfig? {
        let fileURL = url(in: folder)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try ItermplexConfig.parse(try Data(contentsOf: fileURL))
    }

    @discardableResult
    static func write(_ config: ItermplexConfig, in folder: URL) throws -> Data {
        let fileURL = url(in: folder)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let data = try config.encoded()
        try data.write(to: fileURL, options: .atomic)
        return data
    }

    static func rawData(in folder: URL) -> Data? {
        let fileURL = url(in: folder)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: fileURL)
    }
}
