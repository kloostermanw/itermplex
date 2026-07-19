# SettingsView

ASCII reference layout for `SettingsView`, kept in sync with the SwiftUI view
so the intended structure stays readable without running the app.

The view is a single `Form` with four sections: the badge toggle (unlabeled
section), "Periodic checks" (three steppers), "Ports" (two port fields), and
"Remote access (experimental)" (the LAN toggle plus URL and QR when enabled).

```
┌──────────────────────────────────────────────────┐
│  ☑ Show workspace name as iTerm2 badge            │
│    Displays each workspace's name as a            │
│    translucent badge on the iTerm2 sessions        │
│    itermplex opens. Applies to sessions opened     │
│    after this is turned on.                        │
│                                                    │
│  Periodic checks                                  │
│    Fast                          15 s   [－][＋]   │
│    Normal                        60 s   [－][＋]   │
│    Slow                         300 s   [－][＋]   │
│    Seconds between checks for each tier. Which     │
│    check runs at which tier depends on context     │
│    (collapsed vs expanded workspace, pending CI,   │
│    attention). See documentation/periodic          │
│    checks.md.                                      │
│                                                    │
│  Ports                                            │
│    MCP server                        [  7433 ]    │
│    Remote terminal                   [  7434 ]    │
│    TCP ports for the loopback MCP server and the   │
│    LAN remote terminal server. Changes take        │
│    effect after the affected server restarts.      │
│                                                    │
│  Remote access (experimental)                     │
│    ☐ Enable LAN remote terminal                    │
│    (if the server failed to start:)               │
│    ⚠ Server did not start: <reason>               │
│    (when enabled:)                                 │
│    http://192.168.1.20:7434/?token=abcd...         │
│    ┌───────────┐                                   │
│    │ ▚▚ QR ▚▚ │  140 x 140                         │
│    └───────────┘                                   │
│    Serves a browser terminal to other devices on   │
│    your local network. Anyone with this URL can    │
│    read and type into your sessions. Traffic is    │
│    unencrypted, so use it only on trusted          │
│    networks.                                        │
└──────────────────────────────────────────────────┘
```

Legend:

- `☑`: `Toggle("Show workspace name as iTerm2 badge", isOn: $store.showWorkspaceBadge)`.
- `Fast` / `Normal` / `Slow`: one `Stepper` row each (`SettingsView.intervalStepper`),
  bound to `$store.checkIntervals.fast`, `.normal`, `.slow`.
- `15 s` / `60 s` / `300 s`: the current value in seconds, shown next to each
  stepper (`CheckIntervals.default`, since these are the defaults before any
  change).
- `[－][＋]`: the native stepper control. Each press moves the bound value by
  `step: 5`, clamped to the tier's range (`CheckIntervals.fastRange`,
  `.normalRange`, `.slowRange`).

Changing a value updates `ProjectStore.checkIntervals` directly (the property
clamps and persists on set), so the new interval takes effect on the
scheduler's next tick, no restart needed.

- `MCP server` / `Remote terminal`: two `TextField`s (`SettingsView.portField`)
  bound to `$store.mcpPort` and `$store.remotePort`. Each value is clamped to
  `ProjectStore.portRange` (1024 to 65535) and persisted on set. `ContentView`
  restarts the affected server when a port changes.
- `☐ Enable LAN remote terminal`: `Toggle(isOn: $store.remoteEnabled)`. Off by
  default. `ContentView` starts or stops `RemoteServer` in response.
- `⚠ Server did not start`: shown only when `store.remoteStartupError` is set
  (for example the port is already in use); it replaces the URL/QR until a
  successful restart clears it.
- The URL line and QR block appear only while the toggle is on and an active
  network interface exists. The URL is
  `http://<lan-ip>:<remotePort>/?token=<token>` (`LocalNetwork.primaryIPv4`,
  `ProjectStore.remoteToken`); the QR encodes the same URL (`QRCode.image`).

See documentation/remote-access.md for the full feature description and the
security caveat.
