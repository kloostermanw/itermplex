# WorkspaceCardView

ASCII reference layout for `WorkspaceCardView`, kept in sync with the SwiftUI view
so the intended structure stays readable without running the app.

## Expanded card

A project renders as a `WorkspaceCardView`. The header carries the collapse
chevron, the project name, and the git ahead/behind indicators. Below the header
sit the Issue/PR pills, the CI checks line, the Processes group, and the
terminal tree.

The ahead/behind indicators are two stacked, right aligned rows. Each row is
labeled with the remote ref it compares against: the base row against the remote
default branch (`origin/develop`), the upstream row against the branch upstream
(`origin/feature/issue-15`).

```
┌───────────────────────────────────────────────────────────────────┐
│ ▾ laravel-test                  ⟳   origin/develop            ↑1 ↓0 │
│                                      origin/feature/issue-15   ↑1 ↓0 │
│   (Issue #15)  (PR #16)                                             │
│   1 failing, 1 successfull checks                                   │
│   │  ● queue          (filled green = running)                      │
│   │  ○ phpunit        (open green = passed)                         │
│   │  ○ npm            (open red = crashed)                          │
│   │  > Terminal 1                                                   │
│   │  ✦ Claude Code (Python")                                        │
│   │  ✦ old-agent                                     (local)        │
└───────────────────────────────────────────────────────────────────┘
```

Legend:

- `▾` / `▸`: expanded / collapsed chevron (`WorkspaceCardView.header`). The
  chevron sits in a fixed width slot and the header aligns on the first text
  baseline, so the project name keeps the same position whether the card is
  collapsed or expanded and whether the ahead/behind block has one row or two.
- `origin/... ↑a ↓b`: `AheadBehindView`, one row per comparison, label plus the
  up (ahead) and down (behind) counts.
- `(Issue #N)` / `(PR #N)`: filled pills from `IssuePRLineView`. When no issue is
  linked to the branch, the issue pill is replaced by the branch name rendered as
  plain, secondary text (no pill), so the line always shows some branch context.
- `1 failing, 1 successfull checks`: `ChecksLineView`, wording from
  `ChecksSummary.summaryText`. The line color follows `ChecksSummary.status`:
  red on failures, yellow while checks are still pending (nothing failed yet),
  green when everything completed without failures.
- `│`: the leading rule that groups the process and terminal rows
  (`WorkspaceCardView.children`).
- `●` / `○`: process status dot (`ProcessRowView`) — filled = running, open =
  not running; green = success/healthy, red = failed, gray = neutral.
- `>`: terminal row glyph. `✦`: Claude row glyph (`TerminalRowView`).
- Hovering a row reveals trailing action buttons (play / stop / refresh, plus a
  log button on process rows). A plain click on a process row is a no-op, while a
  plain click on a terminal or Claude row still activates it (`onActivate`).
  Terminal buttons are wired here to `onActivate` (play), `onCloseTerminal`
  (stop), and `onRestartTerminal` (refresh). See `ProcessRowView.md` and
  `TerminalRowView.md`.
- `⟳`: appears only when `itermplex.json` changed on disk. Clicking it applies
  the file to the rows (`WorkspaceCardView.header`, `onApplyConfig`).
- `(local)`: a row tracked locally but absent from `itermplex.json`, kept alive
  after an external removal (`TerminalRowView`, `isLocalOnly`).

The change indicator and the enable action only appear for workspaces that have,
or can have, an `itermplex.json`. "Enable config sync" lives in the header's
context menu, shown only while sync is off, and writes the file from the
workspace's current rows.

## Collapsed card

When collapsed, the chevron flips and everything below and beside the header is
hidden: the terminal tree, the Processes group, the Issue/PR pills, the checks
line, and the ahead/behind indicators. Only the chevron and project name
remain.

```
┌───────────────────────────────────────────────────────────────────┐
│ ▸ laravel-test                                                      │
└───────────────────────────────────────────────────────────────────┘
```
