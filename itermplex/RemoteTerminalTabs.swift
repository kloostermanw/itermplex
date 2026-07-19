import SwiftUI
import Observation

/// Identifies one open remote terminal tab: which connection, which remote
/// session, and the label shown on the tab.
struct RemoteTerminalTabID: Codable, Hashable {
    let connectionId: UUID
    let sessionId: String
    let title: String
}

/// Shared model of the terminal tabs open in the `remote-terminal` window.
/// `open(_:)` adds a new tab or, if a tab for the same connection + session is
/// already open, just focuses it. `close(_:)` drops a tab, which lets
/// `RemoteTerminalTabsView` remove (and thereby tear down) its
/// `RemoteTerminalView`.
@MainActor
@Observable
final class RemoteTerminalTabs {
    private(set) var tabs: [RemoteTerminalTabID] = []
    var selected: RemoteTerminalTabID?

    func open(_ tab: RemoteTerminalTabID) {
        if let existing = tabs.first(where: { $0.connectionId == tab.connectionId && $0.sessionId == tab.sessionId }) {
            selected = existing
            return
        }
        tabs.append(tab)
        selected = tab
    }

    func close(_ tab: RemoteTerminalTabID) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: index)
        guard selected == tab else { return }
        selected = tabs[safe: min(index, tabs.count - 1)]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Renders a tab bar plus the selected tab's `RemoteTerminalView`. Every open
/// tab's view is kept mounted (hidden via opacity when not selected, not
/// removed) so switching tabs preserves scrollback and keeps the underlying
/// `RemoteTerminalConnection` alive; only closing a tab tears its connection
/// down.
struct RemoteTerminalTabsView: View {
    let connections: RemoteConnectionsStore
    let tabs: RemoteTerminalTabs

    var body: some View {
        VStack(spacing: 0) {
            if !tabs.tabs.isEmpty {
                tabBar
                Divider()
            }
            content
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs.tabs, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(6)
        }
    }

    private func tabButton(_ tab: RemoteTerminalTabID) -> some View {
        HStack(spacing: 6) {
            Text(tab.title).lineLimit(1)
            Button {
                tabs.close(tab)
            } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tabs.selected == tab ? Color.accentColor.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { tabs.selected = tab }
    }

    @ViewBuilder
    private var content: some View {
        if tabs.tabs.isEmpty {
            ContentUnavailableView("No terminals open", systemImage: "terminal")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                ForEach(tabs.tabs, id: \.self) { tab in
                    terminalContent(for: tab)
                        .opacity(tabs.selected == tab ? 1 : 0)
                        .allowsHitTesting(tabs.selected == tab)
                }
            }
        }
    }

    @ViewBuilder
    private func terminalContent(for tab: RemoteTerminalTabID) -> some View {
        if let connection = connections.connections.first(where: { $0.id == tab.connectionId }) {
            RemoteTerminalView(remoteConnection: connection, sessionId: tab.sessionId)
        } else {
            ContentUnavailableView("Connection removed", systemImage: "bolt.slash")
        }
    }
}
