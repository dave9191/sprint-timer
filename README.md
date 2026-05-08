# Sprint Timer

A minimal macOS focus timer designed for ADHD brains. No tasks, no productivity system, no streaks — just a clean countdown to help you start and stay in motion.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-black) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## Features

- **Four preset durations** — 5, 20, 30, and 60 minute sprints, shown as circular buttons with a clock-face fill so the duration is immediately obvious at a glance
- **Custom duration** — optional input field for any length sprint (off by default, toggle in Settings)
- **Overtime tracking** — when the timer expires the ring empties, the background pulses red, and an overtime counter shows how far over you've gone
- **Notification chime** — a double chime plays on expiry; choose from all 14 macOS system sounds or disable it entirely
- **Floating window** — always on top, visible across all Spaces, never steals focus
- **Remembers position** — the window reopens on the same display and at the same position it was last closed
- **Settings overlay** — configure preset durations, notification sound, default chime state, and custom input visibility without leaving the app
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
| ESC | Close settings without saving |
| Close window | Quit the app |

---

## Settings

Open settings with the **⚙** icon in the bottom-left corner.

| Setting | Description |
|---|---|
| Button durations | Change the four preset values (any positive integer) |
| Sound | Choose which system sound plays on expiry |
| On by default | Whether the chime starts enabled each session |
| Show custom input | Show/hide the custom duration input field |

Settings are saved to `~/.config/sprint-timer/config.json` the first time you change them. The file is only created on save — if it doesn't exist the app uses its defaults.

---

## Project structure

```
CountdownTimer.swift   — entire application (single file)
make_icon.swift        — generates AppIcon.icns at build time
build.sh               — compile + package script
Info.plist             — app bundle metadata
```
