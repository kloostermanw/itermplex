# ContentView

ASCII reference layout for `ContentView`, the top level sidebar window, kept in
sync with the SwiftUI view so the intended structure stays readable without
running the app.

## Window

`ContentView` is a vertical scroll view. `SidebarHeaderView` sits at the top,
followed by one `WorkspaceCardView` per project with a `Divider` between cards. A
trailing empty drop zone accepts a card dragged to the end of the list. Cards are
draggable to reorder.

```
┌───────────────────────────────────────────────────────────────────┐
│                                                       ( ⟳ )  ( + )  │  SidebarHeaderView
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
└───────────────────────────────────────────────────────────────────┘
```

Legend:

- `SidebarHeaderView`: title, workspace count, refresh and add buttons.
- `WorkspaceCardView`: one per project, expanded or collapsed. See
  `WorkspaceCardView.md`.
- `Divider`: drawn between cards, not after the last one.
- Drop zone: a `Color.clear` region at the bottom that accepts a dragged card to
  move it to the end.
- `minWidth: 240`: the sidebar has a minimum width.

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
