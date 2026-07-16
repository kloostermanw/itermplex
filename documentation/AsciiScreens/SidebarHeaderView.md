# SidebarHeaderView

ASCII reference layout for `SidebarHeaderView`, kept in sync with the SwiftUI view
so the intended structure stays readable without running the app.

## Header

`SidebarHeaderView` sits at the top of the sidebar. It shows two trailing icon
buttons, pushed to the right by a leading spacer: refresh git status and add a
project folder.

```
┌───────────────────────────────────────────────────────────────────┐
│                                                       ( ⟳ )  ( + )  │
└───────────────────────────────────────────────────────────────────┘
```

Legend:

- `( ⟳ )`: refresh button, "Refresh git status" (`arrow.clockwise`, `onRefresh`).
- `( + )`: add button, "Add project folder" (`plus`, `onAdd`).
