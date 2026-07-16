# TerminalRowView

ASCII reference layout for `TerminalRowView`, a single row inside a workspace
card's terminal tree, kept in sync with the SwiftUI view so the intended
structure stays readable without running the app.

## Row

A row is a leading glyph plus a label. The glyph is `terminal` (`>`) for a
terminal session and `sparkle` (`✦`) for a Claude session. When the row needs
attention a `🔔` is pushed to the trailing edge.

```
> Terminal 1                              terminal, active
✦ Claude Code                            claude, active
✦ Claude Code (Python")            🔔    claude, needs attention
✦ Claude Code                            claude, exited (dimmed)
```

Legend:

- `>`: terminal glyph (`kind == .terminal`).
- `✦`: Claude glyph (`kind == .claude`).
- `🔔`: trailing attention indicator (`needsAttention`), separated by a spacer.
- Exited Claude rows (`isExited`) render with dimmed glyph and secondary label
  text; there is no separate marker glyph, only the reduced emphasis.
