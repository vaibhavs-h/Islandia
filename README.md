# Islandia

> **The Dynamic Island for your Mac.**

Islandia is a native macOS app that turns the dead space around the notch and menu bar into a persistent "island" — like iPhone's Dynamic Island, but for the Mac. One shell, one state machine, many activities: Now Playing, battery, Bluetooth, Wi-Fi, the Clock app, and more all move through the same collapsed → hover → expanded → interactive → collapse lifecycle, so nothing has to invent its own UI.

This repo has two parts:

* **`/`** — the marketing site (Next.js). Shipped.
* **`app/`** — the actual macOS app (Flutter + Swift). In active development; Technical Alpha is done, Phase 2 (core system activities) is mostly real.

---

## ⚡ Key Capabilities

**Working today:**

* **Now Playing**: Real system-wide media info (title, artist, artwork, elapsed/duration) via the private MediaRemote framework, plus working play/pause/next/previous controls. Spacebar (while expanded and the window is key) and hardware media keys (F7/F8/F9, in any state) control playback — media keys are left to macOS's own routing rather than double-sent, so Islandia only resets its own auto-collapse clock on one. Tapping the artwork/title activates the source app (browser tabs correctly bring the browser forward, not its internal media process) and, with Accessibility permission granted, un-minimizes and raises its window. The collapsed pill's "is actually playing" indicator is a looping waveform video, muted and decorative, falling back to a static glyph if it can't initialize. Auto-hides after sitting paused for 15 seconds with no change.
* **Battery**: Live charge percentage and charging state via IOKit, event-driven (no polling).
* **Output device**: Shows "via AirPods Pro" (etc.) whenever audio isn't on the built-in speakers, via CoreAudio.
* **Bluetooth accessory battery & connectivity** — two independent paths, since macOS's own Bluetooth APIs split the same way:
  * **BLE devices** (Magic Mouse/Keyboard/Trackpad, many third-party accessories): live battery via the standard GATT Battery Service, with a 15s backstop poll since macOS has no push notification for a newly-connected peripheral.
  * **Classic devices** (headphones, earbuds, speakers — anything paired over A2DP): CoreBluetooth can't see these at all, so connect/disconnect comes from IOBluetooth instead. Battery for these comes from `bluetoothd`'s own diagnostic log (the same source macOS's own Bluetooth menu reads) — no root access or packet sniffing needed.
  * Either path surfaces a brief connect/disconnect notification; not AirPods, which use a separate undocumented protocol (see Planned).
* **Wi-Fi network join/leave**: A brief notification when the current network changes, via CoreWLAN's real push API. Reading the network name requires Location Services authorization (an Apple-imposed anti-tracking gate, not a sandboxing issue) — silent with no fallback until granted.
* **Microphone-, camera-, and screen-capture-in-use indicators**: Mic via a public CoreAudio property (doesn't work for Bluetooth microphones, only built-in/wired — needs no microphone permission of its own). Camera and screen capture both via the same underlying signal — WindowServer's own `StatusIndicator` logging, the same one driving macOS's own menu-bar dots, confirmed working for both native apps and browser-based (WebRTC) camera access. All three follow iOS's own privacy-indicator pattern: full prominence for 5 seconds, then recede to a small persistent dot at the pill's edge (or a brief fixed dot instead of a banner, for anything shorter than that) — overlaid on top of whatever else the island is showing, expanded or not, so a privacy signal can never be hidden.
* **macOS Clock app mirroring** — timers, a stopwatch (with laps), and alarms, read from Clock's own private state and, for timers and the stopwatch, genuinely controllable from the island:
  * **Timers**: countdown, progress bar, Cancel and Pause/Resume — pressing the island's buttons presses Clock's own real buttons via Accessibility UI-scripting.
  * **Stopwatch**: elapsed time plus a live lap table (fastest/slowest highlighted, ranked across the full history) matching Clock's own Stopwatch tab; Lap and Stop drive the real app the same way.
  * **Alarms**: a brief notification when one is created, deleted, edited (time changes), or enabled/disabled — diffed from successive reads of Clock's own state, since there's no push API for any of this. A ringing alarm takes over the island entirely (the app's only P1-priority activity) until it's dismissed; a ringing *timer* holds its own view instead of yielding to a running stopwatch, for as long as the expanded view stays open.
  * The one real limitation: a command can't reach Clock while its window sits on a macOS Space that isn't currently active (some other app full-screen, or a different desktop) — a genuine WindowServer/Accessibility restriction with no public workaround (the same one window-management tools like `yabai`/`AltTab` hit), not a bug. The island shows a brief "Can't Reach Clock" message rather than silently doing nothing when this happens.
* **Priority preemption**: The Activity Engine's priority stack lets a higher-tier activity take over the surface and hand control back to exactly what was showing before, state intact — a ringing alarm is the one real activity in the app that exercises this today.
* **Multi-display / notch-less support**: Live-repositions on display connect/disconnect, no restart needed.

Islandia only ever *reflects* state — nothing in its own interface starts a task (no in-app timer, no way to place a call from it). Everything above is something already happening elsewhere that the island surfaces, never something it originates; the app's own in-app countdown timer was removed in favor of mirroring the real Clock app for exactly this reason.

Several of the above depend on undocumented sources rather than a public API: camera/screen-capture and Clock's alarm-ringing state (both a private system log), Bluetooth Classic accessory battery (`bluetoothd`'s own log), and Clock's timer/stopwatch/alarm state itself (a private preferences file). Any of these could change or go silent on any macOS update with no notice — the deliberate, consistent failure mode everywhere this applies is silence, never a crash.

**Planned, not yet built:**
* AirPods battery (needs their undocumented Bluetooth protocol, not the standard GATT service above — deferred until there's real AirPods hardware on hand to verify a decoder against)
* Weather, the Clipboard/File Shelf, calendar, system monitor, and everything that depends on a third-party account (dev/cloud integrations, calls & meetings)

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
       │          │           │           │           │           │
       ▼          ▼           ▼           ▼           ▼           ▼
  ┌─────────┐┌─────────┐┌───────────┐┌───────────┐┌──────────┐┌──────────┐
  │MediaRe- ││CoreAudio││  IOKit /  ││  Private  ││ CoreWLAN ││WindowSer-│
  │mote /   ││/CoreWLAN││CoreBlue-  ││  Clock    ││          ││ver logs /│
  │ IOKit   ││         ││tooth/IOBt ││  state    ││          ││bluetoothd│
  └─────────┘└─────────┘└───────────┘└───────────┘└──────────┘└──────────┘
```

* **App shell**: Flutter compiled to native macOS. The window is a hand-rolled, borderless `NSWindow` (`.nonactivatingPanel`) whose *frame is the pill itself* — there's no invisible canvas around it, so anything outside its bounds is click-through for free. (Considered `macos_window_utils`; it only manipulates a standard window and doesn't support the non-activating/click-through/all-Spaces behavior this needs, so the window is hand-written instead.) Not sandboxed — the app spawns log-watching subprocesses, reads another app's private preferences, and drives Clock via Accessibility, none of which are compatible with the App Sandbox.
* **Native bridge** (`app/macos/Runner/`): one Swift file per integration, each isolating a fragile or privileged dependency so it can never take the rest of the app down:
  * `NowPlayingChannel.swift` — MediaRemote is locked down to Apple-signed processes since macOS 15.4. Worked around via the vendored, open-source [`mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause, see `app/macos/Runner/Resources/MediaRemoteAdapter/LICENSE`): `/usr/bin/perl` — which macOS trusts — dynamically loads a small bundled framework and streams JSON over stdout. Islandia manages that subprocess; it never touches MediaRemote directly. Also handles hardware media keys (global + local `NSEvent` monitors) and activating the source app (with an Accessibility-gated un-minimize/raise as a best-effort fallback).
  * `BatteryStreamHandler.swift` — IOKit power-source notifications.
  * `AudioRouteChannel.swift` — CoreAudio default-output-device tracking.
  * `BluetoothBatteryChannel.swift` — CoreBluetooth, standard GATT Battery Service only.
  * `BluetoothClassicChannel.swift` — IOBluetooth for Classic (A2DP) connect/disconnect, plus a `log stream` against `bluetoothd`'s own `CBPowerSource` category for battery.
  * `WiFiConnectionChannel.swift` — CoreWLAN's `CWEventDelegate`, gated on Location Services authorization for reading the SSID.
  * `MicrophoneActivityChannel.swift` — CoreAudio's `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input device; reads a HAL property, never opens an audio stream, so it needs no microphone permission of its own.
  * `CameraActivityChannel.swift` / `ScreenCaptureActivityChannel.swift` — both thin wrappers around `WindowServerStatusIndicatorAdapter.swift`, which spawns `/usr/bin/log stream` against WindowServer's own `StatusIndicator` logging (the same signal behind macOS's own menu-bar dots), with a one-shot backfill on launch/restart and crash-restart with backoff. No public API exists for either at all; it's a log message format, not a documented one.
  * `ClockPreferencesReader.swift` — reads Clock's own timer/stopwatch/alarm state straight out of its private preferences file; no public API exists.
  * `ClockAlarmRingingWatcher.swift` — the plist can't distinguish "just fired, still ringing" from "already dismissed," so this watches a separate private log for the alert-tone play/stop lines that can.
  * `ClockUIController.swift` / `ClockStopwatchController.swift` / `ClockTimerController.swift` — Accessibility UI-scripting to actually press Clock's own real buttons (Clock has no AppleScript dictionary beyond the generic `application` suite).
  * `ClockActivityChannel.swift` — combines all of the above into one stream + one command channel for the Dart side.
  * `IslandWindowChannel.swift` — window frame/position, notch geometry, outside-click detection, live screen-change handling.
  * `MainFlutterWindow.swift` — the window itself.

---

## 🛠️ Tech Stack

* **App Shell** (`app/`): [Flutter](https://flutter.dev/) (Dart) for the UI/Activity Engine, Swift for everything AppKit-only (window behavior, MediaRemote, CoreAudio, CoreBluetooth/IOBluetooth, CoreWLAN, Accessibility). `video_player` for the Now Playing waveform indicator.
* **Marketing Site** (`/`): [Next.js 16](https://nextjs.org/) (App Router), React 19, TypeScript, TailwindCSS 4, Framer Motion, Lucide React Icons, `clsx`, `tailwind-merge`.
* **Distribution (initial)**: Free Apple ID + Xcode personal-team signing; Apple Developer Program enrollment and notarization planned for the ship phase.
* **Permissions requested**: Bluetooth, Location (Wi-Fi SSID only — never used for actual location), and Accessibility (Clock control, source-app window raising). Notably *not* microphone or camera — both privacy indicators read out-of-band system signals instead.

---

## 📁 Repository Structure

```text
├── src/                          # Marketing site (Next.js App Router)
│   ├── app/
│   ├── components/
│   └── lib/
├── public/
├── app/                          # The macOS app (Flutter + Swift)
│   ├── assets/video/              # Now Playing waveform indicator asset
│   ├── lib/
│   │   ├── engine/                # Activity model, the priority stack
│   │   ├── shell/                 # The Island widget, window channel, motion, geometry, privacy indicators
│   │   ├── providers/             # Real data sources: Now Playing, Battery, Audio Route, Bluetooth (BLE + Classic),
│   │   │                          # Wi-Fi, Mic, Camera, Screen capture, Clock (timer/stopwatch/alarm)
│   │   └── main.dart
│   ├── test/                      # Mirrors lib/ — unit tests for the engine/providers/geometry,
│   │   │                          # widget tests for the shell and privacy indicators
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
2. **Core System Activities** *(mostly done)* — Now Playing, Battery, Audio Route, Bluetooth (BLE + Classic accessory battery/connectivity), Wi-Fi connect/disconnect, microphone/camera/screen-capture-in-use, and macOS Clock mirroring (timers, stopwatch, alarms — read *and* controlled) are all real. AirPods battery remains blocked (v1 tier) on their undocumented protocol — deferred until real hardware is on hand to verify a decoder against.
3. **Weather & the Shelf** *(not started)* — Open-Meteo weather, Clipboard History, the Shelf as a first-class drag-in/drag-out surface.
4. **Developer & Power-User Activities** *(not started)* — downloads/file-transfer, system monitor, then (later) dev-tool and cloud-deploy integrations.
5. **Website** *(shipped)*.
6. **Communications & Live Activities** *(later)* — calls/meetings, sports/travel — deliberately last, since these depend on the least stable APIs.
7. **Ship** — Apple Developer Program enrollment, notarization, one-time-purchase licensing.
8. **Intelligence, Windows & Future** *(later)* — an AI command layer, an all-displays mode, a Windows port.

---

## 🛡️ License

Proprietary. All rights reserved, except the vendored `mediaremote-adapter` under `app/macos/Runner/Resources/MediaRemoteAdapter/`, which is BSD-3-Clause (© Jonas van den Berg and contributors) — see the `LICENSE` file alongside it.
