import SwiftUI

struct TerminalRowView: View {
    let label: String
    let kind: TerminalKind
    var isExited: Bool = false
    var needsAttention: Bool = false
    var isLocalOnly: Bool = false

    private var iconName: String {
        kind == .claude ? "sparkle" : "terminal"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(isExited ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .opacity(isExited ? 0.6 : 1)
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isExited ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if isLocalOnly {
                Text("local")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
            if needsAttention {
                Spacer(minLength: 4)
                Text("🔔")
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}
