import SwiftUI

/// A resizable, read-only, auto-scrolling view of one process's output.
struct ProcessLogWindow: View {
    let store: ProjectStore
    let id: ProcessLogWindowID

    private var process: ManagedProcess? {
        store.processes.process(projectId: id.projectId, name: id.name)
    }

    var body: some View {
        Group {
            if let process {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(process.log.lines.joined(separator: "\n"))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .onChange(of: process.log.lines.count) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            } else {
                ContentUnavailableView("Process not found", systemImage: "bolt.slash")
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .navigationTitle(id.name)
    }
}
