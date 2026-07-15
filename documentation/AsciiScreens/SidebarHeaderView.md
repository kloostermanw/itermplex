# SidebarHeaderView

ASCII reference layout for `SidebarHeaderView`, kept in sync with the SwiftUI view
so the intended structure stays readable without running the app.

## Header

`SidebarHeaderView` sits at the top of the sidebar. It shows the "Workspaces"
title, a capsule badge with the workspace count, and two trailing icon buttons:
refresh git status and add a project folder.

```
┌───────────────────────────────────────────────────────────────────┐
│ Workspaces  (3)                                       ( ⟳ )  ( + )  │
└───────────────────────────────────────────────────────────────────┘
```

Legend:

- `Workspaces`: title text (`title3`, semibold).
- `(3)`: workspace count in a capsule badge (`count` bound to the project list).
- `( ⟳ )`: refresh button, "Refresh git status" (`arrow.clockwise`, `onRefresh`).
- `( + )`: add button, "Add project folder" (`plus`, `onAdd`).
