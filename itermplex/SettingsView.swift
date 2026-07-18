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
        }
        .formStyle(.grouped)
        .frame(width: 380)
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
