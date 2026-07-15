import SwiftUI

struct SidebarHeaderView: View {
    let onRefresh: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
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
