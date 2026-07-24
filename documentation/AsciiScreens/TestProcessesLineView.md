# TestProcessesLineView

ASCII reference layout for `TestProcessesLineView`, a single line inside a
workspace card that surfaces the project's test-process buttons, kept in sync
with the SwiftUI view so the intended structure stays readable without running
the app.

## Line

A horizontal, wrapping row of one button per test process plus a trailing
`ALL` button. Rendered by `WorkspaceCardView` only when the workspace defines
at least one test (`!tests.isEmpty`); it sits between the CI checks line and
the Processes/terminal tree, indented with the same leading padding as those
lines.

```
[phpunit]  [feature-tests]  [⟳ npm-test]  [ALL]
```

Legend:

- Each test button: `test.name`, a rounded, bordered capsule
  (`TestButton`/`TestFlowLayout`). Border color comes from
  `testButtonAppearance(for: test.state)`: green for the last run having
  passed, red for failed, gray/secondary (neutral) for never-run or stale
  (working tree changed since the last pass).
- `⟳` (shown as a spinner overlay, not a literal glyph): the button shows a
  `ProgressView` in place of/alongside its label while the test is running
  (`appearance.running`).
- `ALL`: a trailing button with neutral styling that runs every test
  (`onRunAll`); it also spins while any test is running (`anyRunning`).
- Layout: `TestFlowLayout` wraps buttons onto additional rows left to right
  when the line would otherwise overflow the card width, so a workspace with
  many tests doesn't clip.
- Click: runs that single test (`onRun`).
- Context menu per test button: Run (`onRun`); Cancel (`test.kill()`), shown
  only while that test is running; Open log (`onOpenLog`, opens a
  `ProcessLogWindow` with `isTest: true` via `WorkspaceCardView.onOpenTestLog`).
- Tooltip (`.help`): "Running…" while running, otherwise "Not run" / "Passed" /
  "Failed" based on the button's style.
