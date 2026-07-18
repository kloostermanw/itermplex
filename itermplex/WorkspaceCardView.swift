import SwiftUI

struct WorkspaceCardView: View {
    let project: Project
    let collapsed: Bool
    let gitInfo: GitInfo?
    let runState: (TerminalRef) -> ClaudeRunState
    let needsAttention: (TerminalRef) -> Bool
    let syncEnabled: Bool
    let configChanged: Bool
    let isLocalOnly: (TerminalRef) -> Bool
    let onActivate: (TerminalRef) -> Void
    let onRestartTerminal: (TerminalRef) -> Void
    let onRenameTerminal: (TerminalRef) -> Void
    let onRemoveTerminal: (TerminalRef) -> Void
    let onCloseTerminal: (TerminalRef) -> Void
    let onOpenTerminal: () -> Void
    let onOpenClaude: () -> Void
    let onRemoveProject: () -> Void
    let onToggleCollapsed: () -> Void
    let onEnableSync: () -> Void
    let onApplyConfig: () -> Void
    let processes: [ManagedProcess]
    let onProcessStart: (ManagedProcess) -> Void
    let onProcessStop: (ManagedProcess) -> Void
    let onProcessRestart: (ManagedProcess) -> Void
    let onProcessKill: (ManagedProcess) -> Void
    let onOpenProcessLog: (ManagedProcess) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !collapsed {
                if let gitInfo {
                    IssuePRLineView(
                        branch: gitInfo.branch,
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .animation(.default, value: collapsed)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .center)
            Text(project.name)
                .font(.title3)
                .lineLimit(1)
                .truncationMode(.middle)
            if configChanged {
                Button(action: onApplyConfig) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(.orange)
                        .help("itermplex.json changed on disk. Click to apply.")
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if !collapsed {
                VStack(alignment: .trailing, spacing: 2) {
                    if let gitInfo, gitInfo.hasBase {
                        AheadBehindView(
                            label: gitInfo.baseRef ?? "base",
                            behind: gitInfo.baseBehind,
                            ahead: gitInfo.baseAhead
                        )
                    }
                    if let gitInfo, gitInfo.hasUpstream {
                        AheadBehindView(
                            label: gitInfo.upstreamRef ?? "origin/\(gitInfo.branch)",
                            behind: gitInfo.behind,
                            ahead: gitInfo.ahead
                        )
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggleCollapsed() }
        .contextMenu {
            Button("Terminal", action: onOpenTerminal)
            Button("Claude", action: onOpenClaude)
            if !syncEnabled {
                Button("Enable config sync", action: onEnableSync)
            }
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
                if !processes.isEmpty {
                    ForEach(processes) { process in
                        ProcessRowView(
                            process: process,
                            onStart: { onProcessStart(process) },
                            onStop: { onProcessStop(process) },
                            onRestart: { onProcessRestart(process) },
                            onKill: { onProcessKill(process) },
                            onOpenLog: { onOpenProcessLog(process) }
                        )
                    }
                }
                ForEach(project.terminals) { ref in
                    TerminalRowView(
                        label: ref.label,
                        kind: ref.kind,
                        isExited: ref.kind == .claude && runState(ref) == .exited,
                        needsAttention: needsAttention(ref),
                        isLocalOnly: isLocalOnly(ref),
                        onPlay: { onActivate(ref) },
                        onStop: { onCloseTerminal(ref) },
                        onRestart: { onRestartTerminal(ref) }
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
