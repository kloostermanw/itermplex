import Testing
@testable import itermplex

@Suite struct ProcessVariablesTests {
    @Test func detectsBareReference() {
        let unresolved = ProcessVariables.unresolved(in: "gh pr view $ITERMPLEX_PR_NUMBER", available: [:])
        #expect(unresolved == ["ITERMPLEX_PR_NUMBER"])
    }

    @Test func detectsBracedReference() {
        let unresolved = ProcessVariables.unresolved(in: "echo ${ITERMPLEX_BRANCH}", available: [:])
        #expect(unresolved == ["ITERMPLEX_BRANCH"])
    }

    @Test func resolvedReferenceIsNotReported() {
        let unresolved = ProcessVariables.unresolved(
            in: "gittower $ITERMPLEX_WORKSPACE_PATH", available: ["ITERMPLEX_WORKSPACE_PATH": "/x"]
        )
        #expect(unresolved.isEmpty)
    }

    @Test func nonItermplexVariablesAreIgnored() {
        let unresolved = ProcessVariables.unresolved(in: "echo $HOME ${PATH}", available: [:])
        #expect(unresolved.isEmpty)
    }

    @Test func unknownItermplexNameCountsAsUnresolved() {
        let unresolved = ProcessVariables.unresolved(in: "echo $ITERMPLEX_TYPO", available: ["ITERMPLEX_BRANCH": "main"])
        #expect(unresolved == ["ITERMPLEX_TYPO"])
    }

    @Test func reportsEachUnresolvedOnceSorted() {
        let unresolved = ProcessVariables.unresolved(
            in: "$ITERMPLEX_REPO $ITERMPLEX_OWNER $ITERMPLEX_REPO", available: [:]
        )
        #expect(unresolved == ["ITERMPLEX_OWNER", "ITERMPLEX_REPO"])
    }

    @Test func mixesResolvedAndUnresolved() {
        let unresolved = ProcessVariables.unresolved(
            in: "run ${ITERMPLEX_BRANCH} $ITERMPLEX_PR_NUMBER", available: ["ITERMPLEX_BRANCH": "main"]
        )
        #expect(unresolved == ["ITERMPLEX_PR_NUMBER"])
    }

    @Test func commandWithoutReferencesIsEmpty() {
        #expect(ProcessVariables.unresolved(in: "npm run dev", available: [:]).isEmpty)
    }

    @Test func loneDollarAndUnclosedBraceAreNotReferences() {
        #expect(ProcessVariables.unresolved(in: "cost is $ and ${ITERMPLEX_BRANCH", available: [:]).isEmpty)
    }
}
