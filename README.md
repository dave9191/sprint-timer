# Sprint Timer

A minimal macOS focus timer designed for ADHD brains. No tasks, no productivity system, no streaks — just a clean countdown to help you start and stay in motion.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-black) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## Features

- **Four preset durations** — 5, 20, 30, and 60 minute sprints, shown as circular buttons with a clock-face fill so the duration is immediately obvious at a glance
- **Custom duration** — optional input field for any length sprint (off by default, toggle in Settings)
- **Overtime tracking** — when the timer expires the ring empties, the background pulses red, and an overtime counter shows how far over you've gone
- **Notification chime** — a double chime plays on expiry; choose from all 14 macOS system sounds or disable it entirely
- **Global hotkeys** — system-wide keyboard shortcuts to start each of the four timers, pause/resume, and cancel; none set by default, fully configurable in Settings
- **Schedule bars** — slim progress bars along the bottom edge showing how far through one or more named time ranges you are (e.g. Day, Work shift); off by default, enable and configure in Settings
- **Floating window** — always on top, visible across all Spaces, never steals focus
- **Remembers position** — the window reopens on the same display and at the same position it was last closed
- **Tabbed settings** — settings are split across three tabs (General, Hot Keys, Schedules) for easier navigation
- **Single-file build** — no Xcode, no package manager, just `swiftc`

---

## Requirements

- macOS 12 Monterey or later
- Xcode Command Line Tools (`xcode-select --install`)

---

## Build

```bash
./build.sh
```

This will:
1. Generate `AppIcon.icns` from source using Swift
2. Compile `CountdownTimer.swift` with `swiftc`
3. Package everything into `SprintTimer.app`

---

## Install

Copy the built app to your Applications folder:

```bash
cp -r SprintTimer.app /Applications/
```

Then launch it from Spotlight or Finder. Because the app has no code signature, macOS Gatekeeper will block the first launch — right-click the app in Finder and choose **Open** to bypass it.

---

## Run without installing

```bash
open SprintTimer.app
```

---

## Usage

| Action | Result |
|---|---|
| Click a round button | Start that duration |
| Click pause icon | Pause / resume |
| Click reset icon | Return to timer selection |
| Click bell icon | Toggle chime for this session |
| Click gear icon | Open settings |
| Type a number + Enter | Start custom duration (if enabled) |
| Global hotkey | Start timer, pause/resume, or cancel (if configured) |
| Hover over schedule bars | Show instant tooltip with name, time range, and % progress |
| ESC | Close settings without saving |
| Close window | Quit the app |

---

## Settings

Open settings with the **⚙** icon in the bottom-left corner. Settings are split into three tabs.

### General

| Setting | Description |
|---|---|
| Button durations | Change the four preset values (any positive integer) |
| Sound | Choose which system sound plays on expiry |
| On by default | Whether the chime starts enabled each session |
| Show custom input | Show/hide the custom duration input field |

### Hot Keys

Assign system-wide keyboard shortcuts to any of the six actions:

| Action | Description |
|---|---|
| Start Timer 1–4 | Immediately start the corresponding preset duration |
| Pause / Resume | Toggle pause on the running timer |
| Cancel | Stop the timer and return to the selection screen |

Click a hotkey field and press your desired key combination to record it. Click **×** to clear a shortcut. No shortcuts are set by default.

### Schedules

| Setting | Description |
|---|---|
| Show schedule bars | Toggle the progress bar strip at the bottom of the window |
| Time ranges | Each row defines a named range with a start and end time; use the stepper to set times |
| + Add | Add a new time range row |
| × | Remove a time range row |

Ranges that cross midnight (end time earlier than start time) are handled automatically. Up to five ranges display cleanly; more are supported but bars become very thin.

---

## Schedule bars

When enabled, a strip of slim bars appears along the bottom edge of the window. Each bar fills from left to right as the current time moves through its range. Hovering over a bar shows an instant tooltip:

```
Work
09:00 – 17:30
62%
```

The tooltip shows "not started" before the range begins and "complete" after it ends.

---

## Settings storage

Settings are saved to `~/.config/sprint-timer/config.json` the first time you change them. The file is only created on save — if it doesn't exist the app uses its defaults.

---

## Project structure

```
CountdownTimer.swift   — entire application (single file)
make_icon.swift        — generates AppIcon.icns at build time
build.sh               — compile + package script
Info.plist             — app bundle metadata
```
