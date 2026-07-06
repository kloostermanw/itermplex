import Foundation
import Observation

@MainActor
@Observable
final class ProjectStore {
    private(set) var projects: [Project] = []

    private let defaults: UserDefaults
    private let storageKey = "itermplex.projects.bookmarks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func addProject(url: URL) {
        let standardized = url.standardizedFileURL
        guard !projects.contains(where: {
            $0.url.standardizedFileURL.path == standardized.path
        }) else { return }
        // Validate we can persist it before adding; skip if not.
        guard (try? standardized.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil
        )) != nil else { return }
        projects.append(Project(url: standardized))
        save()
    }

    private func load() {
        guard let dataArray = defaults.array(forKey: storageKey) as? [Data] else { return }
        var loaded: [Project] = []
        for data in dataArray {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data, options: [],
                relativeTo: nil, bookmarkDataIsStale: &isStale
            ) {
                loaded.append(Project(url: url.standardizedFileURL))
            }
        }
        projects = loaded
    }

    private func save() {
        let dataArray: [Data] = projects.compactMap {
            try? $0.url.bookmarkData(
                options: [], includingResourceValuesForKeys: nil, relativeTo: nil
            )
        }
        defaults.set(dataArray, forKey: storageKey)
    }
}
