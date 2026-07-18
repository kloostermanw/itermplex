# TerminalRowView

ASCII reference layout for `TerminalRowView`, a single row inside a workspace
card's terminal tree, kept in sync with the SwiftUI view so the intended
structure stays readable without running the app.

## Row

A row is a leading glyph plus a label. The glyph is `terminal` (`>`) for a
terminal session and `sparkle` (`✦`) for a Claude session. When the row needs
attention a `🔔` is pushed to the trailing edge. A plain left click still
activates the terminal (`onActivate`, applied by the parent `WorkspaceCardView`);
hovering additionally lightens the row background and reveals action buttons on
the trailing edge (after any `🔔`). The right-click context menu (also applied by
the parent) is unchanged.

```
> Terminal 1                    [◼] [⟳]    terminal, running (hovered)
✦ Claude Code                              claude, running
✦ Claude Code (Python")      🔔 [◼] [⟳]    claude, needs attention (hovered)
✦ Claude Code                   [▶]        claude, exited (dimmed, hovered)
```

Legend:

- `>`: terminal glyph (`kind == .terminal`).
- `✦`: Claude glyph (`kind == .claude`).
- `🔔`: trailing attention indicator (`needsAttention`), separated by a spacer.
- Exited Claude rows (`isExited`) render with dimmed glyph and secondary label
  text; there is no separate marker glyph, only the reduced emphasis.
- Click: activates the terminal (`onActivate`), unchanged from before.
- Hover: the background lightens (rounded `.secondary.opacity(0.12)` fill) and
  the trailing action buttons appear. Running is `!isExited` (plain terminals
  never report an exited state, so they are always running; Claude rows use
  `isExited`).
- Action buttons (visible on hover only):
  - `[▶]` play (`play.fill`) → `onPlay` (activate / relaunch), shown when not
    running.
  - `[◼]` stop (`stop.fill`) → `onStop` (close terminal), shown when running.
  - `[⟳]` refresh (`arrow.clockwise`) → `onRestart` (restart session), shown
    when running.
