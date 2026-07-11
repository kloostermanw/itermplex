import SwiftUI

@main
struct itermplexApp: App {
    @State private var store = ProjectStore()

    var body: some Scene {
        Window("itermplex", id: "main") {
            ContentView(store: store)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 300, height: 760)

        Settings {
            SettingsView(store: store)
        }
    }
}
