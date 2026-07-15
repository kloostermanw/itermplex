# WorkspaceCardView

ASCII reference layout for `WorkspaceCardView`, kept in sync with the SwiftUI view
so the intended structure stays readable without running the app.

## Expanded card

A project renders as a `WorkspaceCardView`. The header carries the collapse
chevron, the project name, and the git ahead/behind indicators. Below the header
sit the Issue/PR pills, the CI checks line, and the terminal tree.

The ahead/behind indicators are two stacked, right aligned rows. Each row is
labeled with the remote ref it compares against: the base row against the remote
default branch (`origin/develop`), the upstream row against the branch upstream
(`origin/feature/issue-15`).

```
┌───────────────────────────────────────────────────────────────────┐
│ ▾ laravel-test                       origin/develop           ↑1 ↓0 │
│                                      origin/feature/issue-15   ↑1 ↓0 │
│   (Issue #15)  (PR #16)                                             │
│   1 failing, 1 successfull checks                                   │
│   │  > Terminal 1                                                   │
│   │  ✦ Claude Code (Python")                                        │
│   │  > Terminal 2                                                   │
│   │  ✦ Claude Code (Python")                                        │
└───────────────────────────────────────────────────────────────────┘
```

Legend:

- `▾` / `▸`: expanded / collapsed chevron (`WorkspaceCardView.header`).
- `origin/... ↑a ↓b`: `AheadBehindView`, one row per comparison, label plus the
  up (ahead) and down (behind) counts.
- `(Issue #N)` / `(PR #N)`: filled pills from `IssuePRLineView`.
- `1 failing, 1 successfull checks`: `ChecksLineView`, wording from
  `ChecksSummary.summaryText`.
- `│`: the leading rule that groups the terminal rows (`WorkspaceCardView.children`).
- `>`: terminal row glyph. `✦`: Claude row glyph (`TerminalRowView`).

## Collapsed card

When collapsed, the chevron flips and everything below and beside the header is
hidden: the terminal tree, the Issue/PR pills, the checks line, and the
ahead/behind indicators. Only the chevron and project name remain.

```
┌───────────────────────────────────────────────────────────────────┐
│ ▸ laravel-test                                                      │
└───────────────────────────────────────────────────────────────────┘
```
