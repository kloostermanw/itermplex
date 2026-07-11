# MCP server

itermplex hosts an MCP server so agents (for example Claude Code) can drive
workspaces and terminal/claude sessions. The server runs inside the app and is
backed by the live `ProjectStore`, so every result reflects what the UI shows.

## Transport

The server uses the MCP "Streamable HTTP" transport in its stateless variant
(plain JSON request/response, no sessions or SSE, which is all itermplex needs
because it sends no server-initiated messages). It binds to loopback only:

```
http://127.0.0.1:7433/mcp
```

The default validation pipeline only checks `Content-Type`. Origin validation
is intentionally relaxed (many MCP HTTP clients omit the `Origin` header); the
loopback-only bind is the mitigation.

## Connecting Claude Code

```sh
claude mcp add --transport http itermplex http://127.0.0.1:7433/mcp
```

The app must be running for the endpoint to be reachable.

## Tools

Workspaces: `list_projects`, `get_project`, `create_project`, `delete_project`,
`select_project`.

Sessions: `list_processes`, `get_process_status`, `spawn_process`,
`spawn_agent` (claude shorthand), `send_input`, `close_process`,
`select_process`, `rename_process`, `get_process_output`, `restart_process`.

Tools that omit `project_id` fall back to the workspace set with
`select_project`. Send a trailing newline in `send_input` text to submit a
command.

## Notes

Workspace ids are persisted, so they stay stable across app restarts. Session
ids come from iTerm2 and are stable while the session lives (a session opened in
a previous app launch may no longer exist in iTerm2, in which case tools that
target it report that the session was not found).
