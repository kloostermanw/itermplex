import SwiftUI
import AppKit

struct ContentView: View {
    let store: ProjectStore
    @Environment(\.openWindow) private var openWindow
    @State private var monitor: SessionMonitoring = ITermMonitor()
    @State private var mcpHost: MCPServerHost?
    @State private var isBusy = false
    @State private var renameTarget: (project: Project, ref: TerminalRef)?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                SidebarHeaderView(
                    onRefresh: { Task { await store.refreshAllGitInfo() } },
                    onAdd: addProject
                )
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
                let host = MCPServerHost(router: MCPToolRouter(store: store))
                mcpHost = host
                await host.start()
            }
        }
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

    private func startRename(_ ref: TerminalRef, in project: Project) {
        renameText = ref.label
        renameTarget = (project, ref)
    }

    private func openProcessLog(_ process: ManagedProcess, in project: Project) {
        openWindow(id: "process-log", value: ProcessLogWindowID(projectId: project.id, name: process.name))
    }
}
