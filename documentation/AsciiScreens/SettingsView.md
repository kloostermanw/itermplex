# SettingsView

ASCII reference layout for `SettingsView`, kept in sync with the SwiftUI view
so the intended structure stays readable without running the app.

The view is a single `Form` with two sections: the badge toggle (unlabeled
section) and "Periodic checks" (three steppers).

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
