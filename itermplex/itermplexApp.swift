import SwiftUI

@main
struct itermplexApp: App {
    @State private var store = ProjectStore()
    @State private var updates = UpdateService()

    var body: some Scene {
        Window("itermplex", id: "main") {
            ContentView(store: store)
                .preferredColorScheme(.dark)
                .updateAlerts(updates)
                .task {
                    await updates.checkForUpdates(userInitiated: false)
                    await updates.runPeriodicChecks()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 300, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updates.checkForUpdates(userInitiated: true) }
                }
            }
        }

        WindowGroup(id: "process-log", for: ProcessLogWindowID.self) { $id in
            if let id {
                ProcessLogWindow(store: store, id: id)
                    .preferredColorScheme(.dark)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
