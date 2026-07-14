import AppKit
import SwiftUI
import Testing
@testable import itermplex

@Suite struct SmokeTests {
    @Test func sanity() {
        #expect(1 + 1 == 2)
    }

    @MainActor
    @Test func workspaceCardViewRendersExpanded() {
        let result = renderWorkspaceCard(collapsed: false)
        #expect(result != nil)
    }

    @MainActor
    @Test func workspaceCardViewRendersCollapsed() {
        let result = renderWorkspaceCard(collapsed: true)
        #expect(result != nil)
    }

    /// Builds a `WorkspaceCardView` with a real `Project` (with one terminal so the
    /// collapsible `children` section has content) and no-op callbacks, then forces
    /// an actual render pass via `ImageRenderer` so construction/wiring crashes in
    /// the whole view tree (including terminal rows) would surface here.
    @MainActor
    private func renderWorkspaceCard(collapsed: Bool) -> NSImage? {
        let project = Project(
            url: URL(fileURLWithPath: "/tmp/itermplex-smoke-project"),
            terminals: [
                TerminalRef(label: "Terminal 1", sessionId: "sess-A", kind: .terminal)
            ],
            collapsed: collapsed
        )

        let view = WorkspaceCardView(
            project: project,
            collapsed: collapsed,
            gitInfo: nil,
            runState: { _ in .running },
            needsAttention: { _ in false },
            onActivate: { _ in },
            onRenameTerminal: { _ in },
            onRemoveTerminal: { _ in },
            onCloseTerminal: { _ in },
            onOpenTerminal: {},
            onOpenClaude: {},
            onRemoveProject: {},
            onToggleCollapsed: {}
        )
        .frame(width: 320)

        let renderer = ImageRenderer(content: view)
        return renderer.nsImage
    }
}
