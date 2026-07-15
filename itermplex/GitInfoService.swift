import Foundation

protocol GitInfoProviding: Sendable {
    func info(for folder: URL) async -> GitInfo?
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

    func info(for folder: URL) async -> GitInfo? {
        let isRepo = git(folder, ["rev-parse", "--is-inside-work-tree"])
        guard isRepo.status == 0,
              isRepo.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return nil
        }

        _ = git(folder, ["fetch", "--quiet"]) // best-effort

        let branch = git(folder, ["rev-parse", "--abbrev-ref", "HEAD"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        var behind = 0
        var ahead = 0
        var hasUpstream = false
        var upstreamRef: String?
        let revList = git(folder, ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"])
        if revList.status == 0, let parsed = GitParsing.aheadBehind(fromRevListOutput: revList.stdout) {
            behind = parsed.behind
            ahead = parsed.ahead
            hasUpstream = true
            let upstream = git(folder, ["rev-parse", "--abbrev-ref", "@{upstream}"])
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            upstreamRef = upstream.isEmpty ? nil : upstream
        }

        var baseBehind = 0
        var baseAhead = 0
        var hasBase = false
        var baseRef: String?
        let symbolicRef = git(folder, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
        if symbolicRef.status == 0,
           let base = GitParsing.defaultBranch(fromSymbolicRef: symbolicRef.stdout) {
            let baseRevList = git(folder, ["rev-list", "--left-right", "--count", "origin/\(base)...HEAD"])
            if baseRevList.status == 0,
               let parsed = GitParsing.aheadBehind(fromRevListOutput: baseRevList.stdout) {
                baseBehind = parsed.behind
                baseAhead = parsed.ahead
                hasBase = true
                baseRef = "origin/\(base)"
            }
        }

        let remote = git(folder, ["remote", "get-url", "origin"])
        let ownerRepo = remote.status == 0 ? GitParsing.ownerRepo(fromRemoteURL: remote.stdout) : nil

        let issueNumber = GitParsing.issueNumber(fromBranch: branch)
        let prNumber = pullRequestNumber(folder: folder, branch: branch)

        var checks: ChecksSummary?
        if let prNumber, let ghPath {
            let result = runner.run(
                ghPath,
                ["pr", "checks", "\(prNumber)", "--json", "bucket"],
                workingDirectory: folder
            )
            checks = GitParsing.checksSummary(fromBucketJSON: result.stdout)
        }

        var issueURL: URL?
        var prURL: URL?
        if let (owner, repo) = ownerRepo {
            if let issueNumber {
                issueURL = URL(string: "https://github.com/\(owner)/\(repo)/issues/\(issueNumber)")
            }
            if let prNumber {
                prURL = URL(string: "https://github.com/\(owner)/\(repo)/pull/\(prNumber)")
            }
        }

        return GitInfo(
            branch: branch, behind: behind, ahead: ahead, hasUpstream: hasUpstream,
            upstreamRef: upstreamRef,
            baseAhead: baseAhead, baseBehind: baseBehind, hasBase: hasBase, baseRef: baseRef,
            issueNumber: issueNumber, prNumber: prNumber, issueURL: issueURL, prURL: prURL,
            checks: checks
        )
    }

    private func git(_ folder: URL, _ arguments: [String]) -> CommandResult {
        runner.run(gitPath, ["-C", folder.path] + arguments, workingDirectory: nil)
    }

    private func pullRequestNumber(folder: URL, branch: String) -> Int? {
        guard let ghPath, !branch.isEmpty else { return nil }
        let result = runner.run(
            ghPath,
            ["pr", "list", "--head", branch, "--json", "number", "--jq", ".[0].number"],
            workingDirectory: folder
        )
        guard result.status == 0 else { return nil }
        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
