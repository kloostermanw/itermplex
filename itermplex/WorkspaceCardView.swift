import SwiftUI

struct WorkspaceCardView: View {
    let project: Project
    let gitInfo: GitInfo?
    let runState: (TerminalRef) -> ClaudeRunState
    let needsAttention: (TerminalRef) -> Bool
    let onActivate: (TerminalRef) -> Void
    let onRenameTerminal: (TerminalRef) -> Void
    let onRemoveTerminal: (TerminalRef) -> Void
    let onCloseTerminal: (TerminalRef) -> Void
    let onOpenTerminal: () -> Void
    let onOpenClaude: () -> Void
    let onRemoveProject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let gitInfo, gitInfo.issueNumber != nil || gitInfo.prNumber != nil {
                IssuePRLineView(
                    issueNumber: gitInfo.issueNumber,
                    issueURL: gitInfo.issueURL,
                    prNumber: gitInfo.prNumber,
                    prURL: gitInfo.prURL
                )
                .padding(.leading, 24)
            }
            if let checks = gitInfo?.checks {
                ChecksLineView(summary: checks)
                    .padding(.leading, 24)
            }
            children
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(project.name)
                .font(.title3)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let gitInfo, gitInfo.hasBase {
                AheadBehindView(behind: gitInfo.baseBehind, ahead: gitInfo.baseAhead)
            }
            if let gitInfo, gitInfo.hasUpstream {
                AheadBehindView(behind: gitInfo.behind, ahead: gitInfo.ahead)
            }
        }
        .contextMenu {
            Button("Terminal", action: onOpenTerminal)
            Button("Claude", action: onOpenClaude)
            Button("Remove", action: onRemoveProject)
        }
    }

    private var children: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(width: 1)
                .padding(.leading, 7)
                .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(project.terminals) { ref in
                    TerminalRowView(
                        label: ref.label,
                        kind: ref.kind,
                        isExited: ref.kind == .claude && runState(ref) == .exited,
                        needsAttention: needsAttention(ref)
                    )
                    .onTapGesture { onActivate(ref) }
                    .contextMenu {
                        if ref.kind == .terminal {
                            Button("Rename") { onRenameTerminal(ref) }
                        }
                        Button("Remove") { onRemoveTerminal(ref) }
                        Button("Close terminal") { onCloseTerminal(ref) }
                    }
                }
            }
        }
    }
}
