# iTermPlex

iTermPlex is a macOS app that manages your development workspaces. Each workspace is a project
folder, shown as a card with its git status, issue and PR links, CI checks, terminals, Claude
agents, and supervised processes. Terminals and agents are iTerm2 sessions that iTermPlex drives
through the iTerm2 Python API. Per workspace configuration lives in an `itermplex.json` file that
the app reads (and, for terminals and agents, keeps in sync).

## Build

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen). `project.yml` is the source
of truth for the Xcode project; `itermplex.xcodeproj/` is generated and gitignored.

```sh
brew install xcodegen   # once
xcodegen generate

xcodebuild -scheme itermplex -destination 'platform=macOS' build
xcodebuild -scheme itermplex -destination 'platform=macOS' test
```

## Processes

Processes are named commands, declared in a workspace's `itermplex.json`, that iTermPlex runs and
supervises in the workspace directory. Unlike terminals and agents (which are iTerm2 sessions the
app only drives), a process is owned by iTermPlex: it starts the command, tracks its state and
exit code, streams its output into a per process log window, and can stop, restart, or kill it.

Process definitions are read only in the app. The file is the source of truth. Editing
`itermplex.json` surfaces the change indicator on the workspace card; clicking it applies the
change (new processes appear, removed ones are dropped, changed commands take effect on the next
start).

### Configuration

Processes live under a `processes` key, keyed by name:

```json
{
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
}
```

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `command` | string | required | The command to run, in the workspace directory. |
| `kind` | string | `long_running` | One of `long_running`, `daemon`, `short_running`. |
| `stop` | string | none | A command that shuts the process down. |
| `status` | string | none | Daemon only. A probe command (see Status command below). |
| `auto_start` | bool | `false` | Start the process when the workspace loads. |
| `auto_restart` | bool | `false` | Restart on unexpected exit (see Limitations). |
| `restart_when_changed` | array | `[]` | Paths to watch (see Limitations). |
| `env` | object | `{}` | Extra environment variables. |
| `allow_empty_vars` | bool | `false` | Run even when a referenced `ITERMPLEX_*` variable has no value (see Variables). |

### Kinds and controls

Every process offers start, stop, restart, and kill from the row's context menu.

- **short_running**: runs to completion (for example a test or lint run). Its state becomes the
  exit result: passed on exit 0, failed on a non zero exit. Killable while running.
- **long_running**: a foreground process (for example `npm run dev`), tracked while it runs.
  Stop runs the `stop` command if one is set, otherwise it sends a signal escalation (SIGINT,
  then SIGTERM, then SIGKILL). Kill sends SIGKILL immediately.
- **daemon**: a process that detaches and returns (for example `sail up -d`, `vagrant up`). Its
  start command may exit right away while the real service keeps running, so a `stop` command is
  effectively required to bring it down, and a `status` command is recommended so the app can
  tell whether it is up.

### Status dot

Each process row shows a status dot with two independent parts. Fill encodes liveness (filled
means running, open means not running). Color encodes outcome (green means success or healthy,
red means failed or crashed, gray means neutral).

| State | Dot |
| --- | --- |
| running (long_running alive, or daemon up) | filled green |
| short task passed (exit 0) | open green |
| failed or crashed (non zero exit) | open red |
| idle, never run, or stopped | open gray |

### Status command (daemon only)

For a daemon, iTermPlex learns whether the service is up by running the `status` command. The
contract is exit code based, and the command's output is ignored:

- Exit 0 means the daemon is up (running, filled green dot).
- Any non zero exit means it is down (idle, open gray dot).

Write a fast, non interactive shell one liner that succeeds when the service is up and fails when
it is down. The common idiom pipes a status check into `grep -q`, which exits 0 on a match:

```json
"status": "cd src && sail ps | grep -q Up"
"status": "vagrant status --machine-readable | grep -q ',state,running'"
"status": "docker compose ps --status running | grep -q ."
```

The probe runs when an `auto_start` daemon is applied, and on the periodic refresh cycle (the
same cadence the git status refresh uses). It does not re probe immediately after a manual start
or stop; the dot updates on the next refresh.

### Output

Click a process row to open its log window: a resizable, read only, auto scrolling view of the
process output. The log is an in memory buffer capped at roughly the last 5000 lines and is
cleared when the app quits.

### Environment and PATH

Each command runs under a login, non interactive shell (`$SHELL -l -c`). This matters for
resolving tools like `sail`, `composer`, `npm`, and `vendor/bin/...`:

- Because the shell is a login shell, it sources the login startup files (for zsh: `~/.zshenv`,
  `~/.zprofile`, `~/.zlogin`, plus macOS `/etc/zprofile`, which runs `path_helper`). So your
  login PATH, including a Homebrew `brew shellenv` line in `~/.zprofile`, is available. In most
  setups no extra PATH configuration is needed.
- Because the shell is not interactive, `~/.zshrc` is not sourced. PATH entries added only in
  `~/.zshrc` will not be visible to a process. If you hit "command not found", move that PATH
  export into a login sourced file (`~/.zprofile` or `~/.zshenv`).

The base environment is the app's own process environment (the minimal launchd environment when
started from Finder or the Dock, or the inheriting terminal when started from one), which the
login shell then augments. The definition's `env` map is merged on top before the shell runs.

There is no dedicated PATH field. If you truly need to set PATH, use `env`, but this is the least
reliable option because the login shell can rebuild PATH through `path_helper`. Prefer project
local commands (for example `vendor/bin/phpunit`, `cd src && sail ...`), which do not depend on
PATH at all.

### Variables

iTermPlex injects a set of workspace variables into every process as environment
variables under the `ITERMPLEX_` prefix. Reference them in `command`, `stop`, and
`status` with normal shell syntax (`$ITERMPLEX_BRANCH` or `${ITERMPLEX_BRANCH}`),
and the login shell expands them when it runs the command.

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

### Limitations (v1)

- `restart_when_changed` is parsed and stored, but file watching is not implemented yet, so the
  field currently has no effect.
- `auto_restart` applies to `long_running` processes only. Daemon auto restart is not implemented
  yet.
- There is no timeout on `stop` or `status` commands, so keep them fast and non interactive; a
  command that hangs will hang that step.
- Log output is not written to disk, and typing into a running process is not supported.
