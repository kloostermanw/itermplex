import Foundation

protocol GitInfoProviding: Sendable {
    func gitSync(for folder: URL) async -> GitSync?
    func pullRequestNumber(for folder: URL, branch: String) async -> Int?
    func ciChecks(for folder: URL, prNumber: Int) async -> ChecksSummary?
}

struct GitInfoService: GitInfoProviding {
    private let runner: CommandRunning
    private let gitPath: String
    private let ghPath: String?

    init(
        runner: CommandRunning = ProcessCommandRunner(),
        gitPath: String = "/usr/bin/git",
        ghCandidates: [String] = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
    ) {
        self.runner = runner
        self.gitPath = gitPath
        self.ghPath = ghCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func gitSync(for folder: URL) async -> GitSync? {
        let isRepo = git(folder, ["rev-parse", "--is-inside-work-tree"])
        guard isRepo.status == 0,
              isRepo.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return nil
        }
        _ = git(folder, ["fetch", "--quiet"]) // best-effort

        let branch = git(folder, ["rev-parse", "--abbrev-ref", "HEAD"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        var behind = 0, ahead = 0, hasUpstream = false
        var upstreamRef: String?
        let revList = git(folder, ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"])
        if revList.status == 0, let parsed = GitParsing.aheadBehind(fromRevListOutput: revList.stdout) {
            behind = parsed.behind; ahead = parsed.ahead; hasUpstream = true
            let upstream = git(folder, ["rev-parse", "--abbrev-ref", "@{upstream}"])
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            upstreamRef = upstream.isEmpty ? nil : upstream
        }

        var baseBehind = 0, baseAhead = 0, hasBase = false
        var baseRef: String?
        let symbolicRef = git(folder, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
        if symbolicRef.status == 0, let base = GitParsing.defaultBranch(fromSymbolicRef: symbolicRef.stdout) {
            let baseRevList = git(folder, ["rev-list", "--left-right", "--count", "origin/\(base)...HEAD"])
            if baseRevList.status == 0, let parsed = GitParsing.aheadBehind(fromRevListOutput: baseRevList.stdout) {
                baseBehind = parsed.behind; baseAhead = parsed.ahead; hasBase = true
                baseRef = "origin/\(base)"
            }
        }

        let remote = git(folder, ["remote", "get-url", "origin"])
        let ownerRepo = remote.status == 0 ? GitParsing.ownerRepo(fromRemoteURL: remote.stdout) : nil

        return GitSync(
            branch: branch, behind: behind, ahead: ahead, hasUpstream: hasUpstream,
            upstreamRef: upstreamRef, baseAhead: baseAhead, baseBehind: baseBehind,
            hasBase: hasBase, baseRef: baseRef,
            owner: ownerRepo?.0, repo: ownerRepo?.1,
            issueNumber: GitParsing.issueNumber(fromBranch: branch)
        )
    }

    func pullRequestNumber(for folder: URL, branch: String) async -> Int? {
        guard let ghPath, !branch.isEmpty else { return nil }
        let result = runner.run(
            ghPath,
            ["pr", "list", "--head", branch, "--json", "number", "--jq", ".[0].number"],
            workingDirectory: folder
        )
        guard result.status == 0 else { return nil }
        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func ciChecks(for folder: URL, prNumber: Int) async -> ChecksSummary? {
        guard let ghPath else { return nil }
        let result = runner.run(
            ghPath, ["pr", "checks", "\(prNumber)", "--json", "bucket"], workingDirectory: folder
        )
        return GitParsing.checksSummary(fromBucketJSON: result.stdout)
    }

    private func git(_ folder: URL, _ arguments: [String]) -> CommandResult {
        runner.run(gitPath, ["-C", folder.path] + arguments, workingDirectory: nil)
    }
}
