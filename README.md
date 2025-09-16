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
For full build/sign/notarize instructions and troubleshooting, see [FocusedBot/README.md](FocusedBot/README.md).

## Architecture
- `FocusedBot/` (Swift, macOS)
  - SwiftPM workspace with the `FocusdBot` executable target (menu bar app). Uses AppKit, SwiftUI, Accessibility (AX) and Apple Events to Safari. Persists to SQLite via GRDB at `~/Library/Application Support/Focusd/focusd.sqlite`. Optional AI summaries call your proxy set by `FOCUSD_PROXY_URL`.
- `site/` (static marketing)
  - Plain HTML/CSS/JS landing page. The download button links to the GitHub Release DMG. JS posts to the API for simple metrics and email signup. `window.API_BASE` can point the site at a hosted API (e.g., Render).
- `server/` (Node/Express API)
  - Serves the static site at `/` and exposes:
    - `POST /download` – increments a local counter (basic analytics)
    - `POST /api/subscribe` – appends email signups to `server/data/signups.csv`
    - `GET /assets/og.png` – social preview image used by OG/Twitter meta tags
  - CORS enabled; default listens on `PORT` (8787 locally). Deployed via `render.yaml`.

## 1.0.0
- First public notarized release
- New menu bar UI and animated mascot
- Activity + media tracking, Safari website rules
- Optional AI session summaries via proxy
- Signed & notarized DMG download
