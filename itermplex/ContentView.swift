import SwiftUI
import AppKit

struct ContentView: View {
    let store: ProjectStore
    let remoteConnections: RemoteConnectionsStore
    let remoteWorkspaces: RemoteWorkspacesController
    let remoteTerminalTabs: RemoteTerminalTabs
    @Environment(\.openWindow) private var openWindow
    @State private var monitor: SessionMonitoring = ITermMonitor()
    @State private var mcpHost: MCPServerHost?
    @State private var streamer = ITermScreenStreamer()
    @State private var remoteServer: RemoteServer?
    @State private var isBusy = false
    @State private var renameTarget: (project: Project, ref: TerminalRef)?
    @State private var renameText = ""
    @State private var sections = SectionCollapseState()
    @State private var remoteCardCollapsed: Set<UUID> = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                localSection
                ForEach(remoteConnections.connections) { connection in
                    if let remoteStore = remoteWorkspaces.stores[connection.id] {
                        remoteSection(remoteStore)
                    }
                }
            }
        }
        .frame(minWidth: 240)
        .disabled(isBusy)
        .overlay {
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .navigationTitle("")
        .task {
            store.startPeriodicRefresh()
            monitor.start { event in store.handle(event) }
            if mcpHost == nil {
                let host = MCPServerHost(router: MCPToolRouter(store: store), port: store.mcpPort)
                mcpHost = host
                await host.start()
            }
            await syncRemoteServer()
            remoteWorkspaces.sync()
        }
        .onChange(of: store.remoteEnabled) { Task { await syncRemoteServer() } }
        .onChange(of: store.remotePort) { Task { await syncRemoteServer(forceRestart: true) } }
        .onChange(of: store.mcpPort) { Task { await restartMCPHost() } }
        .alert("Rename terminal", isPresented: renameIsPresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let target = renameTarget {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        store.rename(target.ref, in: target.project, to: trimmed)
                    }
                }
                renameTarget = nil
            }
        }
        .alert(
            store.lastError ?? "",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { presented in if !presented { store.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.lastError = nil }
        }
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { presented in if !presented { renameTarget = nil } }
        )
    }

    @ViewBuilder
    private var localSection: some View {
        SidebarSectionHeaderView(
            title: "Local",
            collapsed: sections.isCollapsed("local"),
            onToggle: { sections.setCollapsed("local", !sections.isCollapsed("local")) },
            buttons: [
                .init(system: "arrow.clockwise", help: "Refresh git status",
                      action: { Task { await store.refreshAllGitInfo() } }),
                .init(system: "plus", help: "Add project folder", action: addProject)
            ]
        )
        if !sections.isCollapsed("local") {
            ForEach(store.projects) { project in
                WorkspaceCardView(
                    project: project,
                    collapsed: project.collapsed,
                    gitInfo: store.gitInfo[project.id],
                    runState: { store.runState(for: $0) },
                    needsAttention: { store.attention.contains($0.id) },
                    syncEnabled: store.isSyncEnabled(project),
                    configChanged: store.configChangedOnDisk.contains(project.id),
                    isLocalOnly: { store.localOnlyTerminals.contains($0.id) },
                    onActivate: { activate($0, in: project) },
                    onRestartTerminal: { restartTerminal($0, in: project) },
                    onRenameTerminal: { startRename($0, in: project) },
                    onRemoveTerminal: { store.removeTerminal($0, in: project) },
                    onCloseTerminal: { closeTerminal($0, in: project) },
                    onOpenTerminal: { openTerminal(for: project) },
                    onOpenClaude: { openClaude(for: project) },
                    onRemoveProject: { store.remove(project) },
                    onToggleCollapsed: { store.toggleCollapsed(project) },
                    onEnableSync: { store.enableConfigSync(for: project) },
                    onApplyConfig: { store.applyConfigChanges(for: project) },
                    processes: store.processes.processes(for: project.id),
                    onProcessStart: { $0.start() },
                    onProcessStop: { $0.stop() },
                    onProcessRestart: { $0.restart() },
                    onProcessKill: { $0.kill() },
                    onOpenProcessLog: { openProcessLog($0, in: project) }
                )
                .draggable(project.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first, let dragged = UUID(uuidString: first) else { return false }
                    store.move(id: dragged, before: project.id)
                    return true
                }
                if project.id != store.projects.last?.id {
                    Divider()
                }
            }
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first, let dragged = UUID(uuidString: first) else { return false }
                    store.moveToEnd(id: dragged)
                    return true
                }
        }
    }

    @ViewBuilder
    private func remoteSection(_ remoteStore: RemoteWorkspaceStore) -> some View {
        let key = "remote-\(remoteStore.connection.id.uuidString)"
        SidebarSectionHeaderView(
            title: remoteStore.connection.name,
            collapsed: sections.isCollapsed(key),
            onToggle: { sections.setCollapsed(key, !sections.isCollapsed(key)) },
            buttons: [
                .init(system: "arrow.clockwise", help: "Reconnect",
                      action: { remoteStore.stop(); remoteStore.start() }),
                .init(system: "minus.circle", help: "Remove connection", action: {
                    remoteConnections.remove(id: remoteStore.connection.id)
                    remoteWorkspaces.sync()
                })
            ]
        )
        if !sections.isCollapsed(key) {
            if remoteStore.state == .connected {
                let projects = remoteStore.workspaces.projects
                ForEach(projects) { project in
                    WorkspaceCardView(
                        project: project,
                        collapsed: remoteCardCollapsed.contains(project.id),
                        gitInfo: remoteStore.workspaces.gitInfo[project.id],
                        runState: { remoteStore.workspaces.runStates[$0.id] ?? .exited },
                        needsAttention: { remoteStore.workspaces.attention.contains($0.id) },
                        syncEnabled: true,
                        configChanged: false,
                        isLocalOnly: { _ in false },
                        onActivate: { openRemoteTerminal(remoteStore, $0) },
                        onRestartTerminal: { remoteStore.restart(sessionId: $0.sessionId) },
                        onRenameTerminal: { _ in },
                        onRemoveTerminal: { _ in },
                        onCloseTerminal: { remoteStore.close(sessionId: $0.sessionId) },
                        onOpenTerminal: { remoteStore.openTerminal(workspaceId: project.id) },
                        onOpenClaude: { remoteStore.openClaude(workspaceId: project.id) },
                        onRemoveProject: {},
                        onToggleCollapsed: { toggleRemoteCardCollapsed(project.id) },
                        onEnableSync: {},
                        onApplyConfig: {},
                        processes: [],
                        onProcessStart: { _ in },
                        onProcessStop: { _ in },
                        onProcessRestart: { _ in },
                        onProcessKill: { _ in },
                        onOpenProcessLog: { _ in }
                    )
                    if project.id != projects.last?.id {
                        Divider()
                    }
                }
            } else {
                Text(stateText(remoteStore.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
    }

    private func toggleRemoteCardCollapsed(_ id: UUID) {
        if remoteCardCollapsed.contains(id) {
            remoteCardCollapsed.remove(id)
        } else {
            remoteCardCollapsed.insert(id)
        }
    }

    private func stateText(_ state: RemoteConnectionState) -> String {
        switch state {
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .unauthorized: return "Unauthorized: check the connection's token."
        case .unreachable: return "Unreachable. Retrying…"
        }
    }

    /// Starts or stops `RemoteServer` to match `store.remoteEnabled`. When the
    /// port changes, `forceRestart` tears down the running server first so it
    /// rebinds on the new port.
    private func syncRemoteServer(forceRestart: Bool = false) async {
        if store.remoteEnabled {
            if forceRestart, remoteServer != nil {
                remoteServer?.stop()
                remoteServer = nil
            }
            if remoteServer == nil {
                store.remoteStartupError = nil
                let server = RemoteServer(store: store, streamer: streamer,
                                          token: store.remoteToken, port: store.remotePort,
                                          onStartupError: { message in store.remoteStartupError = message })
                remoteServer = server
                await server.start()
            }
        } else {
            remoteServer?.stop()
            remoteServer = nil
            streamer.stop()
            store.remoteStartupError = nil
        }
    }

    /// Recreates the MCP host on the currently configured port.
    private func restartMCPHost() async {
        mcpHost?.stop()
        let host = MCPServerHost(router: MCPToolRouter(store: store), port: store.mcpPort)
        mcpHost = host
        await host.start()
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            store.addProject(url: url)
        }
    }

    private func openTerminal(for project: Project) {
        Task {
            isBusy = true
            await store.openTerminal(for: project)
            isBusy = false
        }
    }

    private func openClaude(for project: Project) {
        Task {
            isBusy = true
            await store.openClaude(for: project)
            isBusy = false
        }
    }

    private func activate(_ ref: TerminalRef, in project: Project) {
        Task {
            isBusy = true
            await store.activate(ref, in: project)
            isBusy = false
        }
    }

    private func closeTerminal(_ ref: TerminalRef, in project: Project) {
        Task {
            isBusy = true
            await store.closeTerminal(ref, in: project)
            isBusy = false
        }
    }

    private func restartTerminal(_ ref: TerminalRef, in project: Project) {
        Task {
            isBusy = true
            try? await store.restart(sessionId: ref.sessionId)
            isBusy = false
        }
    }

    private func startRename(_ ref: TerminalRef, in project: Project) {
        renameText = ref.label
        renameTarget = (project, ref)
    }

    private func openProcessLog(_ process: ManagedProcess, in project: Project) {
        openWindow(id: "process-log", value: ProcessLogWindowID(projectId: project.id, name: process.name))
    }

    /// Opens (or focuses) a tab in the shared `remote-terminal` window for a
    /// tapped remote session row, then brings that window forward.
    private func openRemoteTerminal(_ remoteStore: RemoteWorkspaceStore, _ ref: TerminalRef) {
        let tab = RemoteTerminalTabID(connectionId: remoteStore.connection.id, sessionId: ref.sessionId, title: ref.label)
        remoteTerminalTabs.open(tab)
        openWindow(id: "remote-terminal")
    }
}
