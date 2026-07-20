# The `itermplex.json` File

Each workspace can hold one `itermplex.json` in its root folder. It is the per
workspace configuration file: it names the workspace, lists the terminals and
Claude agents to lay out, and declares the supervised processes iTermPlex runs.

This document covers the file format and how the file is created and maintained.
For how processes actually behave once declared (kinds, status dots, the log
window, environment and PATH), see the "Processes" section of the top level
`README.md`.

## Location and naming

The file lives at the root of the workspace folder:

```
<workspace>/itermplex.json
```

The filename is fixed. A workspace with no `itermplex.json` still works; it just
has no persisted layout and no processes.

## How iTermPlex uses the file

The file is the source of truth. iTermPlex reads it and reflects it in the
workspace card.

- **Terminals and agents are kept in sync.** When a file exists (sync is on), the
  app writes the file to mirror the workspace's current rows, and it applies edits
  you make to the file back into the layout.
- **Processes are read only in the app.** You declare them in the file; the app
  never edits process definitions. It preserves the processes it last read when it
  rewrites the file for terminal or agent changes, so processes you add by hand are
  not lost.

When you edit the file on disk, a file watcher notices and the workspace card shows
a change indicator. Clicking it applies the change: new processes appear, removed
ones are dropped, and changed commands take effect on the next start.

The app writes the file pretty printed, with sorted keys and a trailing newline, so
it stays stable and diff friendly. Array order (agents, iterm) is preserved as
written.

## Creating the file (build)

There are two ways to get an `itermplex.json`:

1. **Let the app create it.** Enabling sync for a workspace writes a fresh
   `itermplex.json` from the workspace's current terminals and agents. From then on
   the app keeps it in sync.
2. **Write it by hand.** Create the file in the workspace root with the keys below.
   The app picks it up (sync is considered on whenever the file exists) and starts
   watching it.

A minimal file:

```json
{
  "agents": [],
  "iterm": [],
  "processes": {}
}
```

## Top level keys

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `name` | string | folder name | Display name for the workspace card. |
| `agents` | array | `[]` | Claude agent sessions to lay out, in order. |
| `iterm` | array | `[]` | iTerm2 terminal sessions to lay out, in order. |
| `processes` | object | `{}` | Supervised processes, keyed by name. |

### `name`

Optional. Overrides the workspace card title. When absent, the folder name is used.

### `agents`

An ordered list of Claude agent rows. Each entry is an object:

```json
"agents": [
  { "slot": "Design the sync feature", "type": "claude" }
]
```

| Field | Type | Meaning |
| --- | --- | --- |
| `slot` | string | The row's stable label and identity. |
| `type` | string | The agent kind. Currently `claude`. |

### `iterm`

An ordered list of terminal rows. Each entry is a plain string, the row's label:

```json
"iterm": [ "Terminal 1", "server logs" ]
```

### `processes`

An object keyed by process name. Each value is a process definition. Full field
reference:

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `command` | string | required | The command to run, in the workspace directory. |
| `kind` | string | `long_running` | One of `long_running`, `daemon`, `short_running`. |
| `stop` | string | none | A command that shuts the process down. |
| `status` | string | none | Daemon only. An exit code based probe command. |
| `auto_start` | bool | `false` | Start the process when the workspace loads. |
| `auto_restart` | bool | `false` | Restart on unexpected exit (long_running only). |
| `restart_when_changed` | array | `[]` | Paths to watch (not yet implemented). |
| `env` | object | `{}` | Extra environment variables. |
| `allow_empty_vars` | bool | `false` | Run even when a referenced `ITERMPLEX_*` variable has no value. |

Example:

```json
"processes": {
  "queue": {
    "command": "cd src && sail artisan queue:work",
    "kind": "long_running",
    "auto_start": true
  },
  "sail": {
    "command": "cd src && sail up -d",
    "kind": "daemon",
    "stop": "cd src && sail down",
    "status": "cd src && sail ps | grep -q Up"
  },
  "phpunit": {
    "command": "vendor/bin/phpunit tests",
    "kind": "short_running"
  }
}
```

See the README "Processes" section for how each kind runs, the status dot, the log
window, and the shell environment.

## Variables

iTermPlex injects workspace variables into every process as environment variables
under the `ITERMPLEX_` prefix. Reference them in `command`, `stop`, and `status`
with normal shell syntax (`$ITERMPLEX_BRANCH` or `${ITERMPLEX_BRANCH}`); the login
shell expands them when it runs the command.

```json
"processes": {
  "tower": { "command": "gittower $ITERMPLEX_WORKSPACE_PATH", "kind": "short_running" },
  "pr":    { "command": "gh pr view $ITERMPLEX_PR_NUMBER --web", "kind": "short_running" }
}
```

| Variable | Value |
| --- | --- |
| `ITERMPLEX_WORKSPACE_PATH` | Absolute path of the workspace folder. |
| `ITERMPLEX_WORKSPACE_NAME` | Workspace display name (the config `name`, else the folder name). |
| `ITERMPLEX_BRANCH` | Current git branch. |
| `ITERMPLEX_UPSTREAM` | Upstream tracking ref (for example `origin/feature-x`). |
| `ITERMPLEX_BASE_BRANCH` | Base branch ref (for example `origin/main`). |
| `ITERMPLEX_OWNER` | Repository owner. |
| `ITERMPLEX_REPO` | Repository name. |
| `ITERMPLEX_ISSUE_NUMBER` | Issue number parsed from the branch name. |
| `ITERMPLEX_PR_NUMBER` | Pull request number for the current branch. |

Workspace path and name are always available. The git derived variables come from
the same status refresh the workspace card uses, so they are only as fresh as the
last refresh and are absent when unknown (a non git folder, a branch with no
upstream, no open PR, and so on).

By default, a command that references a variable with no value is blocked rather
than run with the variable expanding to empty. The process is marked failed and a
message names the missing variables. Set `"allow_empty_vars": true` on the process
to opt into running anyway, in which case an unavailable variable expands to an
empty string like any unset shell variable.

Expansion happens in the shell that runs `command`, `stop`, and `status`, so it
does not apply to literal values in the `env` map (those are set verbatim, not shell
evaluated).

## Full example

```json
{
  "name": "Payroll API",
  "agents": [
    { "slot": "Design the sync feature", "type": "claude" }
  ],
  "iterm": [
    "server logs"
  ],
  "processes": {
    "dev": {
      "command": "npm run dev",
      "kind": "long_running",
      "auto_start": true,
      "auto_restart": true
    },
    "open-pr": {
      "command": "gh pr view $ITERMPLEX_PR_NUMBER --web",
      "kind": "short_running"
    },
    "tower": {
      "command": "gittower $ITERMPLEX_WORKSPACE_PATH",
      "kind": "short_running",
      "allow_empty_vars": true
    }
  }
}
```
