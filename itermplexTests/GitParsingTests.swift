import Testing
import Foundation
@testable import itermplex

@Suite struct GitParsingTests {
    @Test func issueNumberFromTrailingDigits() {
        #expect(GitParsing.issueNumber(fromBranch: "feature/issue-333") == 333)
        #expect(GitParsing.issueNumber(fromBranch: "hotfix/456") == 456)
    }

    @Test func issueNumberNilWhenNoTrailingDigits() {
        #expect(GitParsing.issueNumber(fromBranch: "develop") == nil)
        #expect(GitParsing.issueNumber(fromBranch: "main") == nil)
        #expect(GitParsing.issueNumber(fromBranch: "feature/v2-release") == nil)
        #expect(GitParsing.issueNumber(fromBranch: "feature/issue-") == nil)
    }

    @Test func aheadBehindParsesTwoIntegers() {
        #expect(GitParsing.aheadBehind(fromRevListOutput: "3\t5") ?? (-1, -1) == (3, 5))
        #expect(GitParsing.aheadBehind(fromRevListOutput: "0 0\n") ?? (-1, -1) == (0, 0))
    }

    @Test func aheadBehindNilOnMalformed() {
        #expect(GitParsing.aheadBehind(fromRevListOutput: "") == nil)
        #expect(GitParsing.aheadBehind(fromRevListOutput: "x y") == nil)
        #expect(GitParsing.aheadBehind(fromRevListOutput: "3") == nil)
    }

    @Test func ownerRepoFromHTTPSandSSH() {
        let https = GitParsing.ownerRepo(fromRemoteURL: "https://github.com/kloostermanw/itermplex.git")
        #expect(https?.owner == "kloostermanw")
        #expect(https?.repo == "itermplex")
        let ssh = GitParsing.ownerRepo(fromRemoteURL: "git@github.com:kloostermanw/itermplex.git")
        #expect(ssh?.owner == "kloostermanw")
        #expect(ssh?.repo == "itermplex")
    }

    @Test func ownerRepoNilForNonGitHub() {
        #expect(GitParsing.ownerRepo(fromRemoteURL: "https://gitlab.com/a/b.git") == nil)
        #expect(GitParsing.ownerRepo(fromRemoteURL: "not a url") == nil)
    }

    @Test func checksSummaryTotalsAndFailures() {
        let s = ChecksSummary(passing: 291, failing: 11, cancelled: 3, skipped: 3, pending: 0)
        #expect(s.total == 308)
        #expect(s.hasFailures == true)
        let clean = ChecksSummary(passing: 291, failing: 0, cancelled: 0, skipped: 3, pending: 0)
        #expect(clean.hasFailures == false)
        #expect(clean.total == 294)
    }

    @Test func defaultBranchStripsOriginPrefix() {
        #expect(GitParsing.defaultBranch(fromSymbolicRef: "origin/develop\n") == "develop")
        #expect(GitParsing.defaultBranch(fromSymbolicRef: "refs/remotes/origin/main") == "main")
        #expect(GitParsing.defaultBranch(fromSymbolicRef: "") == nil)
    }

    @Test func checksSummaryTalliesBuckets() {
        let json = """
        [{"bucket":"pass"},{"bucket":"pass"},{"bucket":"fail"},{"bucket":"cancel"},{"bucket":"skipping"},{"bucket":"pending"}]
        """
        let s = GitParsing.checksSummary(fromBucketJSON: json)
        #expect(s?.passing == 2)
        #expect(s?.failing == 1)
        #expect(s?.cancelled == 1)
        #expect(s?.skipped == 1)
        #expect(s?.pending == 1)
    }

    @Test func checksSummaryNilOnEmptyOrInvalid() {
        #expect(GitParsing.checksSummary(fromBucketJSON: "") == nil)
        #expect(GitParsing.checksSummary(fromBucketJSON: "not json") == nil)
        #expect(GitParsing.checksSummary(fromBucketJSON: "[]") == nil)
    }
}
