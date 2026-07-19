# ContentView

ASCII reference layout for `ContentView`, the top level sidebar window, kept in
sync with the SwiftUI view so the intended structure stays readable without
running the app.

## Window

`ContentView` is a vertical scroll view made of one **Local** section followed
by one **Remote** section per connection in `remoteConnections.connections`
(each backed by a live `RemoteWorkspaceStore` from `remoteWorkspaces.stores`).
Each section starts with a `SidebarSectionHeaderView` and, unless collapsed
(`sections: SectionCollapseState`, keyed `"local"` / `"remote-<connection id>"`),
lists one `WorkspaceCardView` per project with a `Divider` between cards. Only
the Local section has the trailing drop zone and drag-to-reorder support; a
Remote section instead shows a state line ("Connecting…", "Unreachable.
Retrying…", "Unauthorized: check the connection's token.") in place of cards
whenever that connection isn't `.connected`. When a remote action (open,
restart, or close) is rejected by the server, that section also shows a small
red caption from `store.lastActionError`, so the failure is visible.

```
┌───────────────────────────────────────────────────────────────────┐
│ ▾ Local                                              ( ⟳ )  ( + )  │  SidebarSectionHeaderView
├───────────────────────────────────────────────────────────────────┤
│ ▾ laravel-test                       origin/develop           ↑1 ↓0 │  WorkspaceCardView
│                                      origin/feature/issue-15   ↑1 ↓0 │
│   (Issue #15)  (PR #16)                                             │
│   1 failing, 1 successfull checks                                   │
│   │  > Terminal 1                                                   │
│   │  ✦ Claude Code                                                  │
│ ································· Divider ·························· │
│ ▸ api-service                                                       │  WorkspaceCardView (collapsed)
│                                                                     │
│                       (drop zone: drag a card here to move to end)  │
├───────────────────────────────────────────────────────────────────┤
│ ▾ Office Mac                                         ( ⟳ )  ( - )  │  SidebarSectionHeaderView (remote)
├───────────────────────────────────────────────────────────────────┤
│ ▾ web-app                             origin/main             ↑0 ↓2 │  WorkspaceCardView (remote)
│   │  > Terminal 1                                                   │
├───────────────────────────────────────────────────────────────────┤
│ ▾ Home Mac                                                          │
│   Unreachable. Retrying…                                            │
└───────────────────────────────────────────────────────────────────┘
```

Legend:

- `SidebarSectionHeaderView`: one per section, title, chevron, and trailing
  icon buttons. Local: refresh git status, add a project folder. Remote:
  reconnect (`store.stop(); store.start()`), remove connection
  (`remoteConnections.remove(id:)` then `remoteWorkspaces.sync()`). See
  `SidebarSectionHeaderView`.
- `WorkspaceCardView`: one per project, expanded or collapsed. See
  `WorkspaceCardView.md`. Remote cards feed data from
  `RemoteWorkspaceStore.workspaces` (`DecodedRemoteWorkspaces`); actions that
  have no remote equivalent (rename, remove terminal, remove project, enable
  sync, apply config, process controls) are wired to no-ops. Tapping a remote
  terminal row (`onActivate`) calls `openRemoteTerminal(remoteStore, ref)`,
  which opens (or focuses an existing) tab in the shared `remote-terminal`
  window for `(remoteStore.connection.id, ref.sessionId, ref.label)` and
  brings that window forward. See `RemoteTerminalTabsView.md`.
- `Divider`: drawn between cards, not after the last one, in both Local and
  Remote sections.
- Drop zone: a `Color.clear` region at the bottom of the Local section that
  accepts a dragged card to move it to the end. Remote sections don't support
  reordering.
- `minWidth: 240`: the sidebar has a minimum width.
- Collapse state (both the section chevron and each remote card's own chevron)
  is `@State` in `ContentView`; section collapse persists via
  `SectionCollapseState` (`UserDefaults`), per-card collapse for remote
  projects is in-memory only for this window's lifetime (local project cards
  persist their collapse through `ProjectStore.toggleCollapsed`).

## Overlays and alerts

`ContentView` is disabled and shows a small `ProgressView` while `isBusy` (a
terminal or Claude session is being opened, activated, or closed). It also hosts
two alerts:

```
┌──────────────────────────────┐        ┌──────────────────────────────┐
│ Rename terminal              │        │ <error message>              │
│                              │        │                              │
│  [ Name________________ ]    │        │                    [  OK  ]  │
│                              │        └──────────────────────────────┘
│        [ Cancel ] [ Rename ] │          (store.lastError)
└──────────────────────────────┘
  (renameTarget != nil)
```

Update related alerts are added separately by `UpdateAlertModifier`. See
`UpdateAlertModifier.md`.
