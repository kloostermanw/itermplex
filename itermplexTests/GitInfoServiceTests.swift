import Testing
import Foundation
@testable import itermplex

struct FakeCommandRunner: CommandRunning {
    let handler: @Sendable (String, [String]) -> CommandResult
    func run(_ executable: String, _ arguments: [String], workingDirectory: URL?) -> CommandResult {
        handler(executable, arguments)
    }
}

@Suite struct GitInfoServiceTests {
    // "/bin/sh" exists, so ghCandidates resolves and the gh branch runs (the
    // fake runner intercepts the actual invocation).
    private func service(_ handler: @escaping @Sendable (String, [String]) -> CommandResult) -> GitInfoService {
        GitInfoService(runner: FakeCommandRunner(handler: handler), ghCandidates: ["/bin/sh"])
    }

    @Test func assemblesFullGitInfo() async {
        let svc = service { _, args in
            if args.contains("--is-inside-work-tree") { return CommandResult(stdout: "true\n", stderr: "", status: 0) }
            if args.contains("fetch") { return CommandResult(stdout: "", stderr: "", status: 0) }
            if args.contains("--abbrev-ref") { return CommandResult(stdout: "feature/issue-333\n", stderr: "", status: 0) }
            if args.contains("rev-list") { return CommandResult(stdout: "3\t5\n", stderr: "", status: 0) }
            if args.contains("remote") { return CommandResult(stdout: "https://github.com/kloostermanw/itermplex.git\n", stderr: "", status: 0) }
            if args.contains("pr") { return CommandResult(stdout: "334\n", stderr: "", status: 0) }
            return CommandResult(stdout: "", stderr: "", status: 1)
        }
        let info = await svc.info(for: URL(fileURLWithPath: "/tmp/x"))
        #expect(info?.branch == "feature/issue-333")
        #expect(info?.behind == 3)
        #expect(info?.ahead == 5)
        #expect(info?.hasUpstream == true)
        #expect(info?.issueNumber == 333)
        #expect(info?.prNumber == 334)
        #expect(info?.issueURL?.absoluteString == "https://github.com/kloostermanw/itermplex/issues/333")
        #expect(info?.prURL?.absoluteString == "https://github.com/kloostermanw/itermplex/pull/334")
    }

    @Test func returnsNilForNonRepo() async {
        let svc = service { _, _ in CommandResult(stdout: "", stderr: "fatal: not a git repository", status: 128) }
        let info = await svc.info(for: URL(fileURLWithPath: "/tmp/x"))
        #expect(info == nil)
    }

    @Test func noUpstreamHidesCounts() async {
        let svc = service { _, args in
            if args.contains("--is-inside-work-tree") { return CommandResult(stdout: "true", stderr: "", status: 0) }
            if args.contains("--abbrev-ref") { return CommandResult(stdout: "develop", stderr: "", status: 0) }
            if args.contains("rev-list") { return CommandResult(stdout: "", stderr: "no upstream", status: 128) }
            if args.contains("remote") { return CommandResult(stdout: "https://github.com/o/r.git", stderr: "", status: 0) }
            return CommandResult(stdout: "", stderr: "", status: 0) // fetch, pr → empty
        }
        let info = await svc.info(for: URL(fileURLWithPath: "/tmp/x"))
        #expect(info?.hasUpstream == false)
        #expect(info?.behind == 0)
        #expect(info?.ahead == 0)
        #expect(info?.issueNumber == nil)   // "develop" has no trailing digits
        #expect(info?.prNumber == nil)      // gh returned empty
    }
}
