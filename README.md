# Islandia

> **The Dynamic Island for your Mac.**

Islandia is a native macOS app that turns the dead space around the notch and menu bar into a persistent "island" — like iPhone's Dynamic Island, but for the Mac. It consolidates Now Playing, AirPods battery, weather, and quick file handoff into one always-visible surface at the top of the screen, so you never have to tab away or dig into System Settings.

---

## ⚡ Key Capabilities

* **Now Playing**: System-wide media info with synced lyrics, driven off the private MediaRemote framework.
* **Lock-Screen Media Controls**: Play, pause, and skip without unlocking.
* **AirPods Battery at a Glance**: Live per-bud/case battery levels decoded straight from the CoreBluetooth broadcast.
* **File Shelf**: A drop zone for quick drag-and-drop handoffs between apps.
* **Weather Glance**: Current conditions pulled from a lightweight third-party weather API.
* **Multi-Display Support**: Follows the notch across every connected screen.
* **Performance-First**: Event-driven architecture with near-zero idle CPU/memory — no polling loops.

---

## 🏗️ Architecture Overview

Islandia pairs a cross-platform shell with a native bridge for the things only macOS APIs can do:

```
                      ┌────────────────────────────────────────┐
                      │         Flutter (Dart) App Shell        │
                      │   Borderless, always-on-top, notch UI   │
                      └───────────────────┬────────────────────┘
                                          │  platform channel
                                          ▼
                      ┌────────────────────────────────────────┐
                      │            Swift Native Bridge          │
                      └───────────────────┬────────────────────┘
                          │                │                │
                          ▼                ▼                ▼
                  ┌───────────────┐ ┌──────────────┐ ┌───────────────┐
                  │  MediaRemote  │ │ CoreBluetooth │ │     IOKit     │
                  │  Now Playing  │ │ AirPods Batt. │ │  Power State  │
                  └───────────────┘ └──────────────┘ └───────────────┘
```

* **App shell**: Flutter (Dart) compiled to native macOS, using `window_manager` for the borderless, always-on-top, notch-positioned window — chosen over Electron (footprint) and pure Swift (shared, learnable framework).
* **Native bridge**: A thin Swift platform-channel layer for MediaRemote (system Now Playing data), CoreBluetooth (AirPods battery), IOKit (power/charging state), and weather.

---

## 🛠️ Tech Stack

* **App Shell**: [Flutter](https://flutter.dev/) (Dart), `window_manager` for borderless/always-on-top notch-positioned windows.
* **Native Bridge**: Swift platform channels — MediaRemote, CoreBluetooth, IOKit.
* **Marketing Site**: [Next.js 16](https://nextjs.org/) (App Router), React 19, TypeScript, TailwindCSS 4, Framer Motion, Lucide React Icons, `clsx`, `tailwind-merge`.
* **Distribution (initial)**: Free Apple ID + Xcode personal-team signing; Apple Developer Program enrollment and notarization planned for ship phase.

---

## 📁 Repository Structure

```text
├── src/
│   ├── app/                    # Next.js App Router pages
│   │   ├── layout.tsx
│   │   ├── page.tsx
│   │   └── globals.css
│   ├── components/
│   │   ├── hero/                # Scroll-driven hero (video, laurel reveal)
│   │   ├── sections/             # Features, FAQ, CTA, feature cards
│   │   ├── site/                 # Footer, reveal/scroll utilities, shared marks
│   │   └── ui/                   # Dynamic Island, Mac frame, music player, toggles
│   └── lib/                     # Shared utilities
├── public/
│   └── video/                    # Hero background video assets
└── README.md
```

This repo is currently just the marketing site (Next.js), at the root. Run it locally with:

```bash
npm run dev
```

Then open [http://localhost:3000](http://localhost:3000). The macOS app itself will live as a sibling directory (e.g. `app/`) once that phase starts.

---

## 🗺️ Roadmap

1. **Core Shell** — Flutter macOS project scaffolded, borderless floating window at the notch.
2. **Now Playing** — MediaRemote wired into the UI (first genuinely working milestone).
3. **AirPods Battery** — CoreBluetooth integration.
4. **Polish** — Power state, weather, multi-display, file shelf.
5. **Website** — Marketing site *(in progress)*.
6. **Ship** — Apple Developer Program enrollment, notarization, one-time-purchase licensing.
7. **(Future)** — Windows port via Flutter desktop.

---

## 🛡️ License

Proprietary. All rights reserved.
