import SwiftUI
import AppKit

struct ContentView: View {
    @State private var store = ProjectStore()
    @State private var isBusy = false
    @State private var renameTarget: (project: Project, ref: TerminalRef)?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(store.projects) { project in
                VStack(alignment: .leading, spacing: 2) {
                    ProjectRowView(project: project)
                        .contextMenu {
                            Button("Terminal") { openTerminal(for: project) }
                            Button("Remove") { store.remove(project) }
                        }
                    ForEach(project.terminals) { ref in
                        TerminalRowView(label: ref.label)
                            .onTapGesture { activate(ref, in: project) }
                            .contextMenu {
                                Button("Rename") { startRename(ref, in: project) }
                                Button("Remove") { store.removeTerminal(ref, in: project) }
                                Button("Close terminal") { closeTerminal(ref, in: project) }
                            }
                    }
                }
            }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240)
        .disabled(isBusy)
        .overlay {
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addProject) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add project folder")
                .accessibilityLabel("Add project folder")
            }
        }
        .navigationTitle("")
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
}
