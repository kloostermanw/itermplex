# ProcessLogWindow

ASCII reference layout for `ProcessLogWindow`, kept in sync with the SwiftUI
view so the intended structure stays readable without running the app.

## Log window

Opened via `openWindow(id: "process-log", value:)` with a `ProcessLogWindowID`
(project id + process name). One window per process; the window title is the
process name. The body is a scrollable, monospaced, read-only, selectable
dump of `ManagedProcess.log.lines`, auto-scrolled to the bottom whenever a new
line arrives.

```
┌ npm ──────────────────────────────────────────────────────────────┐
│ > project@0.0.0 dev                                                │
│ > vite                                                              │
│                                                                     │
│   VITE v5.0.0  ready in 320 ms                                      │
│                                                                     │
│   ➜  Local:   http://localhost:5173/                                │
│   ➜  Network: use --host to expose                                  │
│ [new lines keep appearing here, view auto-scrolls to the bottom]    │
└─────────────────────────────────────────────────────────────────────┘
```

Legend:

- Window title (`npm` above): `id.name`, set via `.navigationTitle` (
  `ProcessLogWindow`).
- Body text: `process.log.lines.joined(separator: "\n")`, rendered in a
  monospaced font and selectable, but not editable.
- Auto-scroll: a `ScrollViewReader` jumps to a hidden bottom anchor whenever
  `process.log.lines.count` changes, keeping the newest output in view.
- Resizing: the window has a minimum size (`480x320`) but is otherwise freely
  resizable.
- Missing process: if the process named in the window's `ProcessLogWindowID`
  can no longer be found (for example the project was removed), the window
  shows a `ContentUnavailableView` ("Process not found") instead of a log.
