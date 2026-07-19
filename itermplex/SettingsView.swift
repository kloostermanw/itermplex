import SwiftUI

struct SettingsView: View {
    @Bindable var store: ProjectStore

    var body: some View {
        Form {
            Section {
                Toggle("Show workspace name as iTerm2 badge", isOn: $store.showWorkspaceBadge)
                Text("Displays each workspace's name as a translucent badge on the iTerm2 sessions itermplex opens. Applies to sessions opened after this is turned on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Periodic checks") {
                intervalStepper("Fast", value: $store.checkIntervals.fast, range: CheckIntervals.fastRange)
                intervalStepper("Normal", value: $store.checkIntervals.normal, range: CheckIntervals.normalRange)
                intervalStepper("Slow", value: $store.checkIntervals.slow, range: CheckIntervals.slowRange)
                Text("Seconds between checks for each tier. Which check runs at which tier depends on context (collapsed vs expanded workspace, pending CI, attention). See documentation/periodic-checks.md.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ports") {
                portField("MCP server", value: $store.mcpPort)
                portField("Remote terminal", value: $store.remotePort)
                Text("TCP ports for the loopback MCP server and the LAN remote terminal server. Changes take effect after the affected server restarts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Remote access (experimental)") {
                Toggle("Enable LAN remote terminal", isOn: $store.remoteEnabled)
                if store.remoteEnabled {
                    if let ip = LocalNetwork.primaryIPv4() {
                        let url = "http://\(ip):\(store.remotePort)/?token=\(store.remoteToken.value)"
                        Text(url).font(.caption).textSelection(.enabled)
                        if let qr = QRCode.image(from: url) {
                            Image(nsImage: qr).interpolation(.none).resizable()
                                .frame(width: 140, height: 140)
                        }
                    } else {
                        Text("No active network interface found.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Serves a browser terminal to other devices on your local network. Anyone with this URL can read and type into your sessions. Traffic is unencrypted, so use it only on trusted networks.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }

    private func portField(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number.grouping(.never))
                .labelsHidden()
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
        }
    }

    private func intervalStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range, step: 5) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue) s").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
