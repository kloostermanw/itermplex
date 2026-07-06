import SwiftUI

@main
struct itermplexApp: App {
    var body: some Scene {
        Window("itermplex", id: "main") {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 300, height: 760)
    }
}
