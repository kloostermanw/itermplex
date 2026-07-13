import SwiftUI

struct SettingsView: View {
    @Bindable var store: ProjectStore

    var body: some View {
        Form {
            Toggle("Show workspace name as iTerm2 badge", isOn: $store.showWorkspaceBadge)
            Text("Displays each workspace's name as a translucent badge on the iTerm2 sessions itermplex opens. Applies to sessions opened after this is turned on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
