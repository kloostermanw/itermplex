import SwiftUI

struct TerminalRowView: View {
    let label: String
    let kind: TerminalKind

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind == .claude ? "sparkles" : "terminal")
                .foregroundStyle(.secondary)
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.leading, 16)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}
