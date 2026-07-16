import SwiftUI

struct ProcessRowView: View {
    let process: ManagedProcess
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onKill: () -> Void
    let onOpenLog: () -> Void

    private var dot: ProcessDot { processDot(for: process.state) }

    var body: some View {
        HStack(spacing: 6) {
            dotView
            Text(process.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            if process.state == .orphaned {
                Text("(orphan)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenLog)
        .help(helpText)
        .contextMenu {
            Button("Start", action: onStart)
            Button("Stop", action: onStop)
            Button("Restart", action: onRestart)
            Button("Kill", action: onKill)
            Divider()
            Button("Open log", action: onOpenLog)
        }
    }

    private var dotView: some View {
        Image(systemName: dot.fill == .filled ? "circle.fill" : "circle")
            .font(.system(size: 9))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch dot.color {
        case .green: return .green
        case .red: return .red
        case .gray: return .secondary
        }
    }

    private var helpText: String {
        switch process.state {
        case .idle: return "Not running"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .finished: return "Finished (exit 0)"
        case .failed(let code): return "Failed (exit \(code))"
        case .stopping: return "Stopping…"
        case .orphaned: return "Running, but removed from itermplex.json"
        }
    }
}
