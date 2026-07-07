import Foundation
import Observation

@MainActor
@Observable
final class ProjectStore {
    private(set) var projects: [Project] = []
    var lastError: String?
    private(set) var gitInfo: [UUID: GitInfo] = [:]

    private let defaults: UserDefaults
    private let service: TerminalService
    private let gitProvider: GitInfoProviding
    private let storageKey = "itermplex.projects.bookmarks"
    private var refreshTask: Task<Void, Never>?

    private struct StoredProject: Codable {
        var bookmark: Data
        var terminals: [TerminalRef]
        var terminalSeq: Int
        var claudeSeq: Int
        var windowId: String?

        init(bookmark: Data, terminals: [TerminalRef], terminalSeq: Int, claudeSeq: Int, windowId: String?) {
            self.bookmark = bookmark
            self.terminals = terminals
            self.terminalSeq = terminalSeq
            self.claudeSeq = claudeSeq
            self.windowId = windowId
        }

        private enum CodingKeys: String, CodingKey {
            case bookmark, terminals, terminalSeq, claudeSeq, windowId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bookmark = try container.decode(Data.self, forKey: .bookmark)
            terminals = try container.decode([TerminalRef].self, forKey: .terminals)
            terminalSeq = try container.decode(Int.self, forKey: .terminalSeq)
            claudeSeq = try container.decodeIfPresent(Int.self, forKey: .claudeSeq) ?? 0
            windowId = try container.decodeIfPresent(String.self, forKey: .windowId)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        service: TerminalService = ITermBridge(),
        gitProvider: GitInfoProviding = GitInfoService()
    ) {
        self.defaults = defaults
        self.service = service
        self.gitProvider = gitProvider
        load()
    }

    func addProject(url: URL) {
        let standardized = url.standardizedFileURL
        guard !projects.contains(where: {
            $0.url.standardizedFileURL.path == standardized.path
        }) else { return }
        guard (try? standardized.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil
        )) != nil else { return }
        projects.append(Project(url: standardized))
        save()
    }

    func remove(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        gitInfo[project.id] = nil
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        projects.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    func openTerminal(for project: Project) async {
        guard let preIndex = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let folder = projects[preIndex].url
        let existingWindowId = projects[preIndex].windowId
        do {
            let handle = try await service.open(folder: folder, existingWindowId: existingWindowId, command: nil)
            guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
            let sequence = projects[index].terminalSeq + 1
            projects[index].terminalSeq = sequence
            projects[index].windowId = handle.windowId
            projects[index].terminals.append(
                TerminalRef(label: "Terminal \(sequence)", sessionId: handle.sessionId)
            )
            save()
        } catch {
            lastError = (error as? TerminalError)?.errorDescription ?? error.localizedDescription
        }
    }

    func activate(_ ref: TerminalRef, in project: Project) async {
        guard let prePIndex = projects.firstIndex(where: { $0.id == project.id }),
              let preTIndex = projects[prePIndex].terminals.firstIndex(where: { $0.id == ref.id }) else { return }
        let sessionId = projects[prePIndex].terminals[preTIndex].sessionId
        let folder = projects[prePIndex].url
        let existingWindowId = projects[prePIndex].windowId
        do {
            let found = try await service.focus(sessionId: sessionId)
            if !found {
                let handle = try await service.open(folder: folder, existingWindowId: existingWindowId, command: nil)
                guard let pIndex = projects.firstIndex(where: { $0.id == project.id }),
                      let tIndex = projects[pIndex].terminals.firstIndex(where: { $0.id == ref.id }) else { return }
                projects[pIndex].windowId = handle.windowId
                projects[pIndex].terminals[tIndex].sessionId = handle.sessionId
                save()
            }
        } catch {
            lastError = (error as? TerminalError)?.errorDescription ?? error.localizedDescription
        }
    }

    func rename(_ ref: TerminalRef, in project: Project, to label: String) {
        guard let pIndex = projects.firstIndex(where: { $0.id == project.id }),
              let tIndex = projects[pIndex].terminals.firstIndex(where: { $0.id == ref.id }) else { return }
        projects[pIndex].terminals[tIndex].label = label
        save()
    }

    func removeTerminal(_ ref: TerminalRef, in project: Project) {
        guard let pIndex = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[pIndex].terminals.removeAll { $0.id == ref.id }
        save()
    }

    func closeTerminal(_ ref: TerminalRef, in project: Project) async {
        guard let prePIndex = projects.firstIndex(where: { $0.id == project.id }),
              let preTIndex = projects[prePIndex].terminals.firstIndex(where: { $0.id == ref.id }) else { return }
        let sessionId = projects[prePIndex].terminals[preTIndex].sessionId
        do {
            try await service.close(sessionId: sessionId)
            guard let pIndex = projects.firstIndex(where: { $0.id == project.id }) else { return }
            projects[pIndex].terminals.removeAll { $0.id == ref.id }
            save()
        } catch {
            lastError = (error as? TerminalError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshAllGitInfo() async {
        let snapshot = projects
        let provider = gitProvider
        let maxConcurrent = 4
        let results: [(UUID, GitInfo?)] = await withTaskGroup(of: (UUID, GitInfo?).self) { group in
            var index = 0
            while index < snapshot.count && index < maxConcurrent {
                let project = snapshot[index]
                let id = project.id
                let url = project.url
                group.addTask { (id, await provider.info(for: url)) }
                index += 1
            }
            var collected: [(UUID, GitInfo?)] = []
            for await result in group {
                collected.append(result)
                if index < snapshot.count {
                    let project = snapshot[index]
                    let id = project.id
                    let url = project.url
                    group.addTask { (id, await provider.info(for: url)) }
                    index += 1
                }
            }
            return collected
        }
        for (id, info) in results {
            gitInfo[id] = info
        }
    }

    func startPeriodicRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAllGitInfo()
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            }
        }
    }

    private func load() {
        guard let dataArray = defaults.array(forKey: storageKey) as? [Data] else { return }
        let decoder = JSONDecoder()
        var loaded: [Project] = []
        for data in dataArray {
            guard let record = try? decoder.decode(StoredProject.self, from: data) else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: record.bookmark, options: [],
                relativeTo: nil, bookmarkDataIsStale: &isStale
            ) else { continue }
            loaded.append(Project(
                url: url.standardizedFileURL,
                terminals: record.terminals,
                windowId: record.windowId,
                terminalSeq: record.terminalSeq,
                claudeSeq: record.claudeSeq
            ))
        }
        projects = loaded
    }

    private func save() {
        let encoder = JSONEncoder()
        let dataArray: [Data] = projects.compactMap { project in
            guard let bookmark = try? project.url.bookmarkData(
                options: [], includingResourceValuesForKeys: nil, relativeTo: nil
            ) else { return nil }
            let record = StoredProject(
                bookmark: bookmark,
                terminals: project.terminals,
                terminalSeq: project.terminalSeq,
                claudeSeq: project.claudeSeq,
                windowId: project.windowId
            )
            return try? encoder.encode(record)
        }
        defaults.set(dataArray, forKey: storageKey)
    }
}
