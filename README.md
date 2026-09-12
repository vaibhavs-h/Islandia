# Islandia

> **The Dynamic Island for your Mac.**

Islandia is a native macOS app that turns the dead space around the notch and menu bar into a persistent "island" — like iPhone's Dynamic Island, but for the Mac. One shell, one state machine, many activities: Now Playing, battery, timers, and more all move through the same collapsed → hover → expanded → interactive → collapse lifecycle, so nothing has to invent its own UI.

This repo has two parts:

* **`/`** — the marketing site (Next.js). Shipped.
* **`app/`** — the actual macOS app (Flutter + Swift). In active development; Technical Alpha is done, Phase 2 (core system activities) is mostly real.

---

## ⚡ Key Capabilities

**Working today:**

* **Now Playing**: Real system-wide media info (title, artist, artwork, elapsed/duration) via the private MediaRemote framework, plus working play/pause/next/previous controls. Spacebar (while expanded) and hardware media keys (F7/F8/F9, in any state) control playback. Tapping the artwork/title activates the source app and, with Accessibility permission granted, un-minimizes and raises its window. Auto-hides after sitting paused for a minute with no change.
* **Battery**: Live charge percentage and charging state via IOKit, event-driven (no polling).
* **Output device**: Shows "via AirPods Pro" (etc.) whenever audio isn't on the built-in speakers, via CoreAudio.
* **Timers**: A native countdown timer that surfaces its completion as a transient, self-dismissing notification.
* **Priority preemption**: A higher-priority activity (e.g. a call) takes over the surface and hands control back to exactly what was showing before, state intact.
* **Multi-display / notch-less support**: Live-repositions on display connect/disconnect, no restart needed.

**Planned, not yet built:** AirPods battery (CoreBluetooth), weather, the Clipboard/File Shelf, calendar, system monitor, and everything that depends on a third-party account (dev/cloud integrations, calls & meetings).

---

## 🏗️ Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │         Flutter (Dart) App Shell        │
                      │  Activity Engine, priority stack, UI    │
                      └───────────────────┬────────────────────┘
                                          │  platform channels
                                          ▼
                      ┌────────────────────────────────────────┐
                      │      Swift Native Bridge (macos/Runner) │
                      │  The window itself IS the pill —        │
                      │  a borderless, non-activating NSWindow  │
                      └───────────────────┬────────────────────┘
                          │                │                │
                          ▼                ▼                ▼
                  ┌───────────────┐ ┌──────────────┐ ┌───────────────┐
                  │  MediaRemote  │ │   CoreAudio   │ │     IOKit     │
                  │  Now Playing  │ │ Output device │ │  Power State  │
                  │ (via a perl   │ └──────────────┘ └───────────────┘
                  │  subprocess — │
                  │  see below)   │
                  └───────────────┘
```

* **App shell**: Flutter compiled to native macOS. The window is a hand-rolled, borderless `NSWindow` (`.nonactivatingPanel`) whose *frame is the pill itself* — there's no invisible canvas around it, so anything outside its bounds is click-through for free. (Considered `macos_window_utils`; it only manipulates a standard window and doesn't support the non-activating/click-through/all-Spaces behavior this needs, so the window is hand-written instead.)
* **Native bridge** (`app/macos/Runner/`): one Swift file per integration, each isolating a fragile or privileged dependency so it can never take the rest of the app down:
  * `NowPlayingChannel.swift` — MediaRemote is locked down to Apple-signed processes since macOS 15.4. Worked around via the vendored, open-source [`mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause, see `app/macos/Runner/Resources/MediaRemoteAdapter/LICENSE`): `/usr/bin/perl` — which macOS trusts — dynamically loads a small bundled framework and streams JSON over stdout. Islandia manages that subprocess; it never touches MediaRemote directly. Also handles hardware media keys (global + local `NSEvent` monitors, covering both the collapsed and expanded/key-window states) and activating the source app (with an Accessibility-gated un-minimize/raise as a best-effort fallback).
  * `BatteryStreamHandler.swift` — IOKit power-source notifications.
  * `AudioRouteChannel.swift` — CoreAudio default-output-device tracking.
  * `IslandWindowChannel.swift` — window frame/position, notch geometry, outside-click detection, live screen-change handling.
  * `MainFlutterWindow.swift` — the window itself.

---

## 🛠️ Tech Stack

* **App Shell** (`app/`): [Flutter](https://flutter.dev/) (Dart) for the UI/Activity Engine, Swift for everything AppKit-only (window behavior, MediaRemote, CoreAudio, IOKit).
* **Marketing Site** (`/`): [Next.js 16](https://nextjs.org/) (App Router), React 19, TypeScript, TailwindCSS 4, Framer Motion, Lucide React Icons, `clsx`, `tailwind-merge`.
* **Distribution (initial)**: Free Apple ID + Xcode personal-team signing; Apple Developer Program enrollment and notarization planned for the ship phase.

---

## 📁 Repository Structure

```text
├── src/                          # Marketing site (Next.js App Router)
│   ├── app/
│   ├── components/
│   └── lib/
├── public/
├── app/                          # The macOS app (Flutter + Swift)
│   ├── lib/
│   │   ├── engine/                # Activity model, the priority stack
│   │   ├── shell/                 # The Island widget, window channel, motion, geometry
│   │   ├── providers/             # Real data sources: Now Playing, Battery, Audio Route
│   │   ├── features/timer/        # Native countdown timer
│   │   ├── demo/                  # Fake activities (priority-preemption demo)
│   │   └── main.dart
│   ├── test/                      # Mirrors lib/ — unit tests for the engine/providers/geometry,
│   │   │                          # a widget test for the shell
│   └── macos/Runner/              # Native Swift bridge (see Architecture above)
├── temp/ROADMAP_PROGRESS.md       # Running tick-list against the build blueprint (gitignored — local reference only)
└── README.md
```

---

## 🚀 Running things

**Marketing site:**

```bash
npm run dev
```

Then open [http://localhost:3000](http://localhost:3000).

**The app:**

```bash
cd app
flutter run -d macos
```

It's a borderless overlay with no Dock icon, so it won't take normal keyboard focus by default — quit it with `q` in that terminal, or `killall islandia`.

```bash
cd app
flutter test      # unit + widget tests
flutter analyze   # static analysis
```

---

## 🗺️ Roadmap

Tracked in detail against the full build blueprint in `temp/ROADMAP_PROGRESS.md` (gitignored, local-only). In short:

1. **Core Shell & Activity Engine** *(done)* — the borderless pill, live notch detection, the priority stack, shared animation.
2. **Core System Activities** *(mostly done)* — Now Playing (real), Battery (real), Audio Route (real), Timers, transient notifications. AirPods battery and recording indicators are still open (v1 tier).
3. **Weather & the Shelf** *(not started)* — Open-Meteo weather, Clipboard History, the Shelf as a first-class drag-in/drag-out surface.
4. **Developer & Power-User Activities** *(not started)* — downloads/file-transfer, system monitor, then (later) dev-tool and cloud-deploy integrations.
5. **Website** *(shipped)*.
6. **Communications & Live Activities** *(later)* — calls/meetings, sports/travel — deliberately last, since these depend on the least stable APIs.
7. **Ship** — Apple Developer Program enrollment, notarization, one-time-purchase licensing.
8. **Intelligence, Windows & Future** *(later)* — an AI command layer, an all-displays mode, a Windows port.

---

## 🛡️ License

Proprietary. All rights reserved, except the vendored `mediaremote-adapter` under `app/macos/Runner/Resources/MediaRemoteAdapter/`, which is BSD-3-Clause (© Jonas van den Berg and contributors) — see the `LICENSE` file alongside it.
