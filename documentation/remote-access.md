# LAN remote terminal

iTermPlex can serve a browser based terminal to other devices on your local
network. From a second laptop, an iPad, or an iPhone on the same wifi you open a
token protected page, see this instance's iTerm2 sessions, attach to one, and
get a live, colored, interactive terminal. The screen streams in real time and
the keys you type reach the session.

This feature is opt in and off by default. It is the first buildable slice of a
larger vision. Native macOS and iOS remote clients are out of scope here and
become later sub projects that reuse the same WebSocket protocol.

## How to use it

1. Open Settings and turn on "Enable LAN remote terminal" in the "Remote access
   (experimental)" section.
2. A reachable URL and a QR code appear. The URL looks like
   `http://192.168.1.20:7434/?token=<token>`.
3. On another device on the same wifi, open the URL or scan the QR code.
4. The page lists this instance's workspaces and their iTerm2 sessions. Tap one
   to attach.
5. Type in the terminal. Keys, including Ctrl+C, arrows, and tab completion,
   reach the session. Colors and screen updates render live.
6. Turn the toggle off to stop the server. Open pages can no longer connect.

If the server cannot start (for example the remote port is already in use), the
Settings section shows the error instead of a URL, so you can pick a free port.

## Architecture

The path from the browser back to iTerm2, in order:

- **Browser (xterm.js).** `remote_index.html` bundles xterm.js. It fetches
  `GET /api/sessions` for the session list, then opens
  `WS /attach?session=<id>&token=<t>`. It writes incoming VT bytes to the
  terminal and forwards each keystroke as `{"data":"<bytes>"}`.
- **`RemoteServer.swift`.** A Hummingbird HTTP plus WebSocket server bound to
  `0.0.0.0` on the remote port (7434 by default), separate from the loopback MCP
  server. It serves the web client, the token gated session list built by
  `RemoteSessionList`, and the token gated per session socket. It bridges the
  session's VT stream down to the socket and the socket's input bytes up to the
  streamer.
- **`ITermScreenStreamer.swift`.** Owns the `iterm_streamer.py` daemon (launch,
  relaunch with backoff, silent failure, mirroring `ITermMonitor`). It decodes
  each frame and feeds it through a `VTSynthesizer` that turns the grid into a
  terminal byte stream. The first frame for a new size reports a resize; later
  frames rewrite only the rows that changed. Streaming is per connection, so
  several viewers (a page reload, or two devices) can watch the same session at
  once, each with its own VT state; a viewer that joins an already streaming
  session is painted the last frame immediately. When a session ends, every
  viewer of it receives an end signal and the browser shows "Session ended".
- **`iterm_streamer.py`.** A persistent daemon. For each attached session it
  subscribes to iTerm2 screen updates via `session.get_screen_streamer()` and
  emits styled grid frames as NDJSON. Input arrives on the same daemon and is
  delivered with `session.async_send_text`, so there is no Python process spawn
  per keystroke. It reuses the iTerm2 cookie and the venv the rest of the app
  already provisions.

Because iTerm2 owns the sessions, iTermPlex cannot tap a raw PTY byte stream for
them. It mirrors the rendered screen grid and synthesizes a terminal byte stream
from it. As a result, scrollback and history are not streamed (only the visible
screen), remote resize is not supported (the browser grid matches the session
size), and managed process PTYs are not remotable in this slice. Only iTerm2
sessions are.

## Ports

Two servers run on separate ports, both configurable in the "Ports" section of
Settings:

- MCP server: `127.0.0.1:7433` (loopback only).
- LAN remote terminal: `0.0.0.0:7434` (reachable on the local network).

Ports are clamped to the range 1024 to 65535 and persisted. Changing a port
restarts the affected server.

## Security

The security posture is deliberately minimal for a trusted home or office wifi:

- Opt in, off by default.
- A shared token is required on every HTTP request and on the WebSocket
  handshake. A missing or wrong token is rejected. The token is generated on
  first use and persisted.
- Traffic is plain HTTP and WebSocket on the LAN. It is not encrypted.

Accepted risk: on a shared or hostile network, screen contents and keystrokes
travel unencrypted and the token can be observed by an on path attacker. Use the
feature only on networks you trust. The Settings UI states this. TLS and internet
(WAN) access are future work, as are native clients, Bonjour discovery,
scrollback, and remote resize.
