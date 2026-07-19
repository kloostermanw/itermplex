# LAN remote access

iTermPlex instances can reach each other, and be reached from a browser, over
the local network. There are two related but separate pieces:

- **Served side.** Every instance can opt in to serving a browser based
  terminal (xterm.js) and a JSON/WebSocket control API on the LAN. This is
  what the rest of this document calls the remote server.
- **Controlling side.** An itermplex instance can also register other
  instances as "remote connections" in Settings. Each remote connection shows
  up as its own section in the sidebar, alongside the local one, with live
  workspace state and the same workspace cards used locally. This is the
  native macOS to macOS control path; it is built into itermplex itself, not
  a separate app.

Both are opt in and off by default, and both are scoped to a trusted local
network. An iOS client and any client reachable outside the LAN remain future
work.

## Served side: browser based remote terminal

From a second laptop, an iPad, or an iPhone on the same wifi you can open a
token protected page, see an instance's iTerm2 sessions, attach to one, and
get a live, colored, interactive terminal. The screen streams in real time and
the keys you type reach the session.

### How to use it

1. Open Settings and turn on "Enable LAN remote terminal" in the "Remote
   access (experimental)" section.
2. A reachable URL and a QR code appear. The URL looks like
   `http://192.168.1.20:7434/?token=<token>`.
3. On another device on the same wifi, open the URL or scan the QR code.
4. The page lists this instance's workspaces and their iTerm2 sessions. Tap
   one to attach.
5. Type in the terminal. Keys, including Ctrl+C, arrows, and tab completion,
   reach the session. Colors and screen updates render live.
6. Turn the toggle off to stop the server. Open pages can no longer connect.

If the server cannot start (for example the remote port is already in use),
the Settings section shows the error instead of a URL, so you can pick a free
port.

### Architecture

The path from the browser back to iTerm2, in order:

- **Browser (xterm.js).** `remote_index.html` bundles xterm.js. It fetches
  `GET /api/sessions` for the session list, then opens
  `WS /attach?session=<id>&token=<t>`. It writes incoming VT bytes to the
  terminal and forwards each keystroke as `{"data":"<bytes>"}`.
- **`RemoteServer.swift`.** A Hummingbird HTTP plus WebSocket server bound to
  `0.0.0.0` on the remote port (7434 by default), separate from the loopback
  MCP server. It serves the web client, the token gated session and workspace
  listings, the token gated per session socket, and the control socket
  described below.
- **`ITermScreenStreamer.swift`.** Owns the `iterm_streamer.py` daemon
  (launch, relaunch with backoff, silent failure, mirroring `ITermMonitor`).
  It decodes each frame and feeds it through a `VTSynthesizer` that turns the
  grid into a terminal byte stream. The first frame for a new size reports a
  resize; later frames rewrite only the rows that changed. Streaming is per
  connection, so several viewers (a page reload, or two devices) can watch
  the same session at once, each with its own VT state; a viewer that joins
  an already streaming session is painted the last frame immediately. When a
  session ends, every viewer of it receives an end signal and the client
  shows the session has ended.
- **`iterm_streamer.py`.** A persistent daemon. For each attached session it
  subscribes to iTerm2 screen updates via `session.get_screen_streamer()` and
  emits styled grid frames as NDJSON. Input arrives on the same daemon and is
  delivered with `session.async_send_text`, so there is no Python process
  spawn per keystroke. It reuses the iTerm2 cookie and the venv the rest of
  the app already provisions.

Because iTerm2 owns the sessions, iTermPlex cannot tap a raw PTY byte stream
for them. It mirrors the rendered screen grid and synthesizes a terminal byte
stream from it. As a result, scrollback and history are not streamed (only
the visible screen), remote resize is not supported (the client's grid
matches the session size), and managed process PTYs are not remotable in
this slice. Only iTerm2 sessions are.

## Controlling side: connecting to another instance

Any itermplex instance can add one or more other instances as remote
connections and drive them from its own sidebar, without opening a browser.

### Setting up a connection

Settings has a "Remote connections" section, below "Remote access
(experimental)". It lists the connections already added
(`RemoteConnectionsStore`, persisted in `UserDefaults`), each row showing the
connection's name and `host:port` with edit and delete buttons, and below the
list a form to add a new one (name, host, port, token). The token here is the
same shared token shown on the other Mac's "Remote access (experimental)"
Settings section. Every add, edit, or delete immediately starts or stops the
matching `RemoteWorkspaceStore` (`RemoteWorkspacesController.sync()`); there
is no separate "connect" step.

There is no remote rename and no remote workspace removal. A connection can
only be added, edited (name, host, port, token), or removed; the workspaces
and sessions it exposes are managed on the other Mac, not from here.

### The grouped sidebar

The sidebar is grouped into collapsible sections: one "Local" section, and
one section per remote connection, each titled with the connection's name.
Every section starts with a `SidebarSectionHeaderView` (a title, a collapse
chevron, and trailing icon buttons); collapsing a section persists across
launches. The Local section's buttons refresh git status and add a project
folder. Each remote section's buttons reconnect the control socket
(`store.stop(); store.start()`) and remove that connection from Settings.

While a remote connection is not `.connected` (`.connecting`, `.unreachable`,
or `.unauthorized`), its section shows a short status line ("Connecting…",
"Unreachable. Retrying…", "Unauthorized: check the connection's token.")
instead of workspace cards. Once connected, its workspaces render with the
same `WorkspaceCardView` used for local projects, fed from the store's
decoded state. Remote sections do not support the drag to reorder or drop
zone that the Local section has.

### Remote actions

A remote workspace card supports exactly the subset of actions that have a
server side endpoint: open a new terminal, open a new claude session, attach
to (tap) an existing session, restart a session, and close a session. Any
action without a remote equivalent (rename, remove a terminal, remove a
project, enable sync, apply config, process controls) is wired to a no-op on
remote cards; those controls render but do nothing. There is no way to
create, rename, or remove a remote workspace from the controlling instance.

Actions are fire and forget: `RemoteWorkspaceStore` posts the request and
ignores the result. The next pushed snapshot (see below) reconciles the UI,
typically within a few hundred milliseconds.

### Live state: the control channel

Each `RemoteWorkspaceStore` opens one `WS /control` connection to its
instance and keeps it open for as long as the connection exists in Settings.
On connect, the server pushes a full snapshot,
`{"type":"snapshot","workspaces":[...]}`, built by the same
`WorkspaceSerializer` used for `GET /api/workspaces`. From then on, the
server watches for workspace changes (`ProjectStore.workspaceChanges()`) and
pushes a fresh, full snapshot, debounced by 250 milliseconds, whenever
something changes; there is no polling and no incremental diff format, every
push is the complete workspace list. The client applies each snapshot
wholesale (`RemoteWorkspaceStore.apply(snapshotText:)`) and marks the
connection `.connected` on the first one it decodes. If the socket drops, the
store marks itself `.unreachable` and retries after a short backoff.

### The control REST API

The server (`RemoteServer.swift`) exposes, all token gated:

- `GET /api/workspaces`: the full workspace list as JSON
  (`{"workspaces":[...]}`), the same shape pushed over `WS /control`.
- `POST /api/workspaces/{id}/terminal`: opens a new terminal in the workspace
  with that id.
- `POST /api/workspaces/{id}/claude`: opens a new claude session in the
  workspace with that id.
- `POST /api/sessions/{sid}/restart`: restarts the tracked session with that
  session id.
- `POST /api/sessions/{sid}/close`: closes the tracked session with that
  session id.
- `WS /control`: the push channel described above.
- `WS /attach`: the pre-existing live terminal stream (see "Served side"
  above), now also consumed by the native client, described next.

### The embedded terminal window

Tapping a remote session (attach) opens a shared, tabbed "remote-terminal"
window, backed by SwiftTerm instead of the browser's xterm.js. One tab is
opened or focused per `(connection, session)` pair; opening a second session
adds another tab in the same window rather than a new window. Each tab keeps
its `WS /attach` connection open and its terminal state mounted even while
another tab is selected, so switching tabs does not lose scrollback or drop
the connection; only closing a tab tears it down. If the underlying remote
connection is removed from Settings while its terminal tab is still open,
that tab shows a placeholder instead of reconnecting. See
`documentation/AsciiScreens/RemoteTerminalTabsView.md` for the layout.

## Ports

Two servers run on separate ports, both configurable in the "Ports" section
of Settings:

- MCP server: `127.0.0.1:7433` (loopback only).
- LAN remote terminal and control API: `0.0.0.0:7434` (reachable on the local
  network).

Ports are clamped to the range 1024 to 65535 and persisted. Changing a port
restarts the affected server.

## Security

The security posture is deliberately minimal, for a trusted home or office
wifi, on both the served and controlling side:

- Opt in, off by default.
- A shared token is required on every HTTP request and on every WebSocket
  handshake (`/attach` and `/control`), whether the caller is a browser or
  another itermplex instance. A missing or wrong token is rejected. The
  token is generated on first use and persisted; a remote connection stores
  its own copy of the target instance's token.
- Traffic is plain HTTP and WebSocket on the LAN. It is not encrypted, for
  either the browser client or instance to instance control traffic.

Accepted risk: on a shared or hostile network, screen contents, keystrokes,
and workspace state travel unencrypted, and the token can be observed by an
on path attacker. Use these features only on networks you trust; the
Settings UI states this. TLS and internet (WAN) access are future work, as
are an iOS client, Bonjour discovery, scrollback, and remote resize.
