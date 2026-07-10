import SwiftUI

struct SidebarHeaderView: View {
    let count: Int
    let onRefresh: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Workspaces")
                .font(.title3.weight(.semibold))
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
            iconButton(system: "arrow.clockwise", help: "Refresh git status", action: onRefresh)
            iconButton(system: "plus", help: "Add project folder", action: onAdd)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func iconButton(system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.bordered)
        .help(help)
        .accessibilityLabel(help)
    }
}
