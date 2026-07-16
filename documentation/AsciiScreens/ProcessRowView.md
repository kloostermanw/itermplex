# ProcessRowView

ASCII reference layout for `ProcessRowView`, a single row inside a workspace
card's Processes group, kept in sync with the SwiftUI view so the intended
structure stays readable without running the app.

## Row

A row is a status dot plus the process name. When the process is `.orphaned`
(still running but removed from `itermplex.json`) an `(orphan)` tag is
appended. Tapping the row opens its log window; right-clicking opens a context
menu with Start, Stop, Restart, Kill, and Open log.

```
● queue                                   running
○ phpunit                                 finished (exit 0)
○ npm                                     failed (exit 1)
● migrate            (orphan)             orphaned, still running
```

Legend:

- `●` / `○`: status dot from `processDot(for: process.state)` — filled
  (`circle.fill`) when the process is live, open (`circle`) when it is not.
  Color follows the dot's outcome: green for success/healthy (`.running`,
  `.orphaned`, `.stopping`, `.finished`), red for `.failed`, gray/secondary for
  neutral (`.idle`, `.starting`).
- Process name: `process.name`, single line, middle-truncated.
- `(orphan)`: shown only when `process.state == .orphaned`.
- Tap: calls `onOpenLog`, which opens the process's log window
  (`ContentView.openProcessLog`).
- Hover: a tooltip (`.help`) with a human-readable state description (e.g.
  "Running", "Failed (exit 1)", "Running, but removed from itermplex.json").
- Context menu: Start / Stop / Restart / Kill / Open log, wired to
  `ManagedProcess.start()/stop()/restart()/kill()` and `onOpenLog`.
