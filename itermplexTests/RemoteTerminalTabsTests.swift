import Testing
import Foundation
@testable import itermplex

@MainActor
@Suite struct RemoteTerminalTabsTests {
    @Test func openAddsAndSelectsANewTab() {
        let tabs = RemoteTerminalTabs()
        let tab = RemoteTerminalTabID(connectionId: UUID(), sessionId: "s1", title: "Terminal 1")
        tabs.open(tab)
        #expect(tabs.tabs == [tab])
        #expect(tabs.selected == tab)
    }

    @Test func openTwiceForSameConnectionAndSessionFocusesTheExistingTab() {
        let tabs = RemoteTerminalTabs()
        let connectionId = UUID()
        let first = RemoteTerminalTabID(connectionId: connectionId, sessionId: "s1", title: "Terminal 1")
        let second = RemoteTerminalTabID(connectionId: UUID(), sessionId: "s2", title: "Terminal 2")
        tabs.open(first)
        tabs.open(second)
        tabs.selected = second

        // Same connectionId + sessionId, different title: still counts as the same tab.
        let renamed = RemoteTerminalTabID(connectionId: connectionId, sessionId: "s1", title: "Renamed")
        tabs.open(renamed)

        #expect(tabs.tabs == [first, second])
        #expect(tabs.selected == first)
    }

    @Test func closeRemovesTheTabAndReselectsANeighbor() {
        let tabs = RemoteTerminalTabs()
        let a = RemoteTerminalTabID(connectionId: UUID(), sessionId: "a", title: "A")
        let b = RemoteTerminalTabID(connectionId: UUID(), sessionId: "b", title: "B")
        let c = RemoteTerminalTabID(connectionId: UUID(), sessionId: "c", title: "C")
        tabs.open(a); tabs.open(b); tabs.open(c)
        tabs.selected = b

        tabs.close(b)

        #expect(tabs.tabs == [a, c])
        #expect(tabs.selected == c)
    }

    @Test func closingTheLastTabClearsSelection() {
        let tabs = RemoteTerminalTabs()
        let a = RemoteTerminalTabID(connectionId: UUID(), sessionId: "a", title: "A")
        tabs.open(a)
        tabs.close(a)
        #expect(tabs.tabs.isEmpty)
        #expect(tabs.selected == nil)
    }

    @Test func closingANonSelectedTabLeavesSelectionUnchanged() {
        let tabs = RemoteTerminalTabs()
        let a = RemoteTerminalTabID(connectionId: UUID(), sessionId: "a", title: "A")
        let b = RemoteTerminalTabID(connectionId: UUID(), sessionId: "b", title: "B")
        tabs.open(a); tabs.open(b)
        tabs.selected = a

        tabs.close(b)

        #expect(tabs.tabs == [a])
        #expect(tabs.selected == a)
    }
}
