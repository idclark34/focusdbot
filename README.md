# FocusdBot

A friendly macOS menu bar companion that helps you stay on task. FocusdBot combines a Pomodoro timer with distraction awareness (apps + websites), a clean menu UI, helpful nudges, and optional AI session summaries. It’s privacy‑first: all activity stays on your Mac unless you explicitly enable AI.

![FocusdBot screenshot](site/assets/focusdbot.svg)

## Install
- Download the notarized DMG from the latest release:
  - https://github.com/idclark34/watchdog/releases
- Drag `FocusdBot.app` to Applications and open it.
- On first run, grant Accessibility (for activity monitoring) and Safari Apple Events (for website rules) when prompted.

## Quick run (development)
Prerequisites: macOS 13+ and Xcode command line tools
```bash
cd FocusedBot/watchdog
swift run FocusdBot
```
The robot appears in your menu bar. Use Quick Test → 30s to try a fast session.

## Build from source (release)
```bash
cd FocusedBot/watchdog
swift build --configuration release --target FocusdBot
```
Then bundle the app (see `FocusedBot/README.md` for signing, notarization, and DMG packaging).

## Privacy
- Activity (frontmost app + window title) is recorded locally to a SQLite database under `~/Library/Application Support/Focusd/focusd.sqlite`.
- Website checks read the current Safari tab’s URL only while a session is active, to enforce your allow‑list.
- AI summaries are optional and disabled by default. If enabled, data is sent to your configured proxy via `FOCUSD_PROXY_URL` and never directly to third‑party APIs from the app.

## More docs
For full build/sign/notarize instructions and troubleshooting, see `FocusedBot/README.md`.

## 1.0.0
- First public notarized release
- New menu bar UI and animated mascot
- Activity + media tracking, Safari website rules
- Optional AI session summaries via proxy
- Signed & notarized DMG download
