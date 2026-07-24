import Testing
@testable import itermplex

@Suite struct CheckTierTests {
    @Test func bumpedClampsAtFast() {
        #expect(CheckTier.slow.bumped() == .normal)
        #expect(CheckTier.normal.bumped() == .fast)
        #expect(CheckTier.fast.bumped() == .fast)
    }

    @Test func baseTierByCollapsed() {
        // .workingTree is intentionally excluded: it is local-only and always
        // runs Fast while expanded regardless of overlays (see
        // workingTreeIsFastWhenExpanded/workingTreeIsSlowWhenCollapsed below).
        for kind in CheckKind.allCases where kind != .workingTree {
            #expect(checkTier(for: kind, collapsed: true, ciPending: false, needsAttention: false) == .slow)
            #expect(checkTier(for: kind, collapsed: false, ciPending: false, needsAttention: false) == .normal)
        }
    }

    @Test func ciPendingBumpsOnlyCiChecks() {
        #expect(checkTier(for: .ciChecks, collapsed: false, ciPending: true, needsAttention: false) == .fast)
        #expect(checkTier(for: .ciChecks, collapsed: true, ciPending: true, needsAttention: false) == .normal)
        // other checks unaffected by ciPending
        #expect(checkTier(for: .gitSync, collapsed: false, ciPending: true, needsAttention: false) == .normal)
    }

    @Test func needsAttentionBumpsAnyCheck() {
        #expect(checkTier(for: .gitSync, collapsed: false, ciPending: false, needsAttention: true) == .fast)
        #expect(checkTier(for: .gitSync, collapsed: true, ciPending: false, needsAttention: true) == .normal)
    }

    @Test func overlaysStackCumulativelyClampedAtFast() {
        // collapsed CI: slow -> (ciPending) normal -> (attention) fast
        #expect(checkTier(for: .ciChecks, collapsed: true, ciPending: true, needsAttention: true) == .fast)
        // expanded CI both overlays: normal -> fast -> fast
        #expect(checkTier(for: .ciChecks, collapsed: false, ciPending: true, needsAttention: true) == .fast)
    }

    @Test func workingTreeIsFastWhenExpanded() {
        #expect(checkTier(for: .workingTree, collapsed: false, ciPending: false, needsAttention: false) == .fast)
    }

    @Test func workingTreeIsSlowWhenCollapsed() {
        #expect(checkTier(for: .workingTree, collapsed: true, ciPending: false, needsAttention: false) == .slow)
    }
}
