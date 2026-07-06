import SwiftUI
import AppKit

struct ContentView: View {
    @State private var store = ProjectStore()

    var body: some View {
        List {
            ForEach(store.projects) { project in
                ProjectRowView(project: project)
                    .contextMenu {
                        Button("Remove") { store.remove(project) }
                    }
            }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240)
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
}
