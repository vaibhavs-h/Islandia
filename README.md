# Islandia

Islandia is a native macOS app that turns the dead space around the notch and menu bar into a persistent "island" — like iPhone's Dynamic Island, but for the Mac.

Mac's top-of-screen real estate mostly sits unused. Checking what's playing or how much AirPods battery is left means tabbing away or digging into System Settings. Islandia consolidates all of that into one always-visible surface at the top of the screen.

## What it does

- Now Playing with synced lyrics
- Lock-screen media controls
- AirPods battery at a glance
- A file shelf for quick drag-and-drop handoffs
- Weather glance
- Multi-display support
- Performance-first: event-driven, near-zero idle CPU/memory

## Stack

- **App shell** — Flutter (Dart) compiled to native macOS, using `window_manager` for a borderless, always-on-top, notch-positioned window. Chosen over Electron (footprint) and pure Swift (shared, learnable framework).
- **Native bridge** — a thin Swift platform-channel layer for what Flutter can't reach directly: MediaRemote (system Now Playing data), CoreBluetooth (AirPods battery), IOKit (power/charging state), and a third-party weather API.
- **Marketing site** — Next.js + Tailwind + Framer Motion, in [`website/`](website/).

## Repo layout

- `website/` — the marketing site (Next.js). Run it locally with:

  ```bash
  cd website
  npm run dev
  ```

  Then open [http://localhost:3000](http://localhost:3000).
- The macOS app itself will live as a sibling directory once that phase starts.

## Roadmap

1. Core shell — Flutter macOS project scaffolded, borderless floating window at the notch
2. Now Playing — MediaRemote wired into the UI
3. AirPods battery — CoreBluetooth integration
4. Polish — power state, weather, multi-display, file shelf
5. Website — marketing site (in progress)
6. Ship — Apple Developer Program enrollment, notarization, one-time-purchase licensing
7. (future) Windows port via Flutter desktop
