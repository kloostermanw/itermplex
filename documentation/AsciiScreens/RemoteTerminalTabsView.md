# RemoteTerminalTabsView

ASCII reference layout for `RemoteTerminalTabsView`, kept in sync with the
SwiftUI view so the intended structure stays readable without running the app.

## Window

Hosted by the shared `WindowGroup(id: "remote-terminal")` in `itermplexApp`,
sibling to `process-log`. There is one such window for the whole app (not one
per tab); `ContentView.openRemoteTerminal(remoteStore, ref)` opens or focuses
it and adds/focuses a tab in the shared `RemoteTerminalTabs` model, keyed by
`RemoteTerminalTabID { connectionId, sessionId, title }`.

```
┌ itermplex ────────────────────────────────────────────────────────┐
│ [ web-app / Terminal 1 x] [ web-app / Claude x] [ api / Terminal x]│  tab bar
├─────────────────────────────────────────────────────────────────────┤
│ $ npm run dev                                                       │
│   VITE v5.0.0  ready in 320 ms                                      │
│                                                                     │
│   ➜  Local:   http://localhost:5173/                                │
│ █                                                                    │  RemoteTerminalView (SwiftTerm)
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

Legend:

- Tab bar: one pill per open `RemoteTerminalTabID`, showing `tab.title` and a
  close (`x`) button. Hidden entirely when no tabs are open, replaced instead
  by a `ContentUnavailableView` ("No terminals open"). Clicking a pill sets
  `tabs.selected`; clicking `x` calls `tabs.close(tab)`.
- Every open tab's `RemoteTerminalView` is kept mounted in a `ZStack` — only
  the selected one is visible (`opacity`), the rest are hidden but still
  running. This is deliberate: switching tabs must not tear down the
  underlying `RemoteTerminalConnection` or lose scrollback, only closing a
  tab does (via SwiftUI removing it from the `ForEach`, which triggers
  `RemoteTerminalView.dismantleNSView`).
- `RemoteTerminalView`: an `NSViewRepresentable` around SwiftTerm's AppKit
  `TerminalView`. Its `Coordinator` is the `TerminalViewDelegate`; the only
  requirement wired to something is `send(source:data:)`, forwarded to
  `RemoteTerminalConnection.send(_:)`. The rest (`sizeChanged`,
  `setTerminalTitle`, `hostCurrentDirectoryUpdate`, `scrolled`,
  `rangeChanged`) are no-ops — there's no local window chrome or host
  directory to reflect.
- `RemoteTerminalConnection`: opens `ws://host:port/attach?session=...` on
  `makeNSView`, closes it on `dismantleNSView`. Feeds incoming `{"type":
  "data","vt":...}` bytes into the terminal (`TerminalView.feed(byteArray:)`),
  applies `{"type":"resize","cols":,"rows":}` via
  `TerminalView.resize(cols:rows:)`, and on `{"type":"ended"}` (or a socket
  failure) stops the socket and feeds a `[session ended]` banner into the
  terminal so the tab visibly shows the session is gone.
- If a tab's connection was removed from Settings while its terminal is
  still open, the tab shows a `ContentUnavailableView` ("Connection removed")
  instead of a `RemoteTerminalView`.
