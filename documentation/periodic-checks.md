# Periodic Checks and Scheduling

The iTermPlex app continuously monitors each workspace through a tiered scheduler that runs four independent checks at different intervals depending on the workspace's state.

## The Four Checks

iTermPlex performs these four checks, each refreshing a different aspect of workspace information:

**Git Sync** (local)
Runs `git fetch` and computes the branch's ahead/behind status relative to its upstream. Also extracts branch metadata including any linked issue number.

**Pull Request Lookup** (network)
Queries GitHub for a pull request matching the current branch. Requires a valid owner/repo from Git Sync to proceed.

**CI Checks** (network)
Fetches the CI status of the workspace's pull request from GitHub. Shows pending, running, and completed checks (pass, fail, skip). Requires the pull request lookup to have found a PR.

**Process Status** (local)
Probes the iTerm session's foreground job and daemon process status. Runs frequently to detect when the Claude agent starts or exits.

## Tiers and Intervals

The scheduler uses four run modes:

**Fast** (15 seconds, default)
Used when a workspace needs urgent monitoring. Shortest interval.

**Normal** (60 seconds, default)
The baseline interval for expanded (visible) workspaces at rest.

**Slow** (300 seconds, default)
Used for collapsed (hidden) workspaces where changes are less urgent to detect.

**Instant** (immediate, event-driven)
Not a repeating interval. Triggered by specific user actions:
  * Un-collapsing a workspace runs all four of its checks immediately, then returns to the normal schedule.
  * The manual refresh button (top-right) runs all checks across all workspaces immediately.

Note: Collapsing a workspace does not trigger Instant checks.

## Configurable Intervals

The three repeating intervals (Fast, Normal, Slow) are configurable in the Settings window. Only these three durations are user-editable; Instant remains event-driven and not a separate duration. Settings edits take effect on the next scheduler tick.

The valid ranges are:
  * Fast: 5 to 600 seconds
  * Normal: 10 to 3600 seconds
  * Slow: 30 to 86400 seconds

Intervals are clamped to these ranges and persisted automatically.

## The Decision Matrix

The scheduler decides each check's tier by examining the workspace's current state. The tier determines how soon the check runs next.

**Base Tier**

When the workspace is collapsed, all checks default to Slow (300s). When expanded, all checks default to Normal (60s).

**Tier Bumps**

Two overlays can bump a check one tier faster (from Slow to Normal, or from Normal to Fast). These bumps are cumulative and capped at Fast (the fastest interval).

  * CI-pending: When the pull request has pending or running CI checks, the CI Checks check bumps one tier faster. Does not affect other checks.
  * Needs-attention: When the iTerm session has sent a bell signal (terminal alert), all four checks for that workspace bump one tier faster.

**Matrix Table**

| Workspace State | Git Sync | Pull Request | CI Checks | Process Status |
|---|---|---|---|---|
| Collapsed, no needs-attention, CI settled | Slow | Slow | Slow | Slow |
| Collapsed, needs-attention, CI settled | Normal | Normal | Normal | Normal |
| Collapsed, no needs-attention, CI-pending | Slow | Slow | Normal | Slow |
| Collapsed, needs-attention, CI-pending | Normal | Normal | Fast | Normal |
| Expanded, no needs-attention, CI settled | Normal | Normal | Normal | Normal |
| Expanded, needs-attention, CI settled | Fast | Fast | Fast | Fast |
| Expanded, no needs-attention, CI-pending | Normal | Normal | Fast | Normal |
| Expanded, needs-attention, CI-pending | Fast | Fast | Fast | Fast |

## Instant Triggers

Un-collapsing a workspace or pressing the manual refresh button causes all affected checks to run immediately:

  * **Un-collapse:** When you expand a collapsed workspace, all four of its checks are marked as due and execute at once. This is useful for quickly verifying the current state after the workspace was hidden.
  * **Manual Refresh:** The refresh button (↻) at the top right of the window resets all checks in all workspaces as due, then executes them. This is a full sync across the entire project.

## Dynamic Tier Recomputation

The scheduler evaluates each check's tier on every tick (every 15 seconds, the Fast interval). This means the decision matrix is recomputed live from the current state. If CI checks settle (all pass or complete), the CI Checks tier drops back to Normal or Slow on the next tick. Similarly, if needs-attention is cleared, the tier drops back to baseline. This ensures the scheduler naturally reflects reality: slow builds do not stay on Fast forever once they complete.

## Fixed Matrix

The tier decision matrix is built into the application code and cannot be customized by users. The rules live in `CheckTier.swift` in the `checkTier(for:collapsed:ciPending:needsAttention:)` function. Changing the matrix requires a code change and rebuild.

## Out of Scope

Three other real-time systems are not part of this periodic scheduler:

  * **iTerm session events:** Session title, bell, job, and termination events are delivered by iTerm2 in real time and update the app immediately. The process status check periodically confirms the job name, but user-visible events arrive event-driven.
  * **Config file changes:** The app watches the `itermplex.json` file in each workspace folder. Changes are detected event-driven and reconciled immediately, without waiting for a scheduled check.
  * **App self-update check:** The UpdateService checks for new app versions on a separate schedule, unrelated to workspace checks.
