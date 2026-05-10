# FanCtl

> A native, polished macOS fan controller for Apple Silicon — with smart cooling modes, live charts, and a Liquid Glass menu-bar UI.

[![CI](https://github.com/Juanipis/fanctl/actions/workflows/ci.yml/badge.svg)](https://github.com/Juanipis/fanctl/actions/workflows/ci.yml)
[![Release](https://github.com/Juanipis/fanctl/actions/workflows/release.yml/badge.svg)](https://github.com/Juanipis/fanctl/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/Juanipis/fanctl?display_name=tag&sort=semver)](https://github.com/Juanipis/fanctl/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue.svg)](https://www.apple.com/macos/)

FanCtl talks to the SMC (System Management Controller) directly through IOKit, runs every privileged operation through a tiny background daemon, and ships with a SwiftUI popover that lives in your menu bar. It works on M1, M2, M3, M4, and M5 MacBooks — including macOS 26 Tahoe.

| | |
|--|--|
| **Hero** | Live RPM, hottest temperature, 60-second sparkline. |
| **Smart modes** | Auto, Silent, Cool ❄️, Performance ⚡, Manual. |
| **Watchdog** | Dead-man heartbeat + 95 °C thermal panic. Forces auto if anything goes wrong. |
| **Privileged helper** | Single root daemon, registered via `SMAppService`. App stays sandboxable. |
| **No dependencies** | Pure Swift + IOKit. No third-party tools, no kernel extensions. |

## Why this exists

Apple Silicon stopped accepting the legacy `AppleSMC` IOKit calling convention that all the older fan-control tools (`smcFanControl`, `Macs Fan Control`, `stats`) relied on. On macOS 26 the user-client class is `AppleSMCKeysEndpoint` and the wire layout flipped to host-byte-order packed FourCC keys. FanCtl re-derives that from scratch and ships it as a tested Swift Package.

You can read the technical write-up in [`docs/research.md`](docs/research.md) (coming soon).

## Modes

| Mode | Curve (hottest temp → fan target as % of `[Mn, Mx]`) |
|------|------------------------------------------------------|
| **Auto** | _macOS owns the fans. Default._ |
| **Silent** | 50 °C → 0 % · 75 °C → 50 % · 90 °C → 100 % |
| **Cool** | 40 °C → 0 % · 60 °C → 50 % · 75 °C → 100 % |
| **Performance** | 35 °C → 50 % · 50 °C → 100 % |
| **Manual** | Whatever you drag the slider to. |

The helper polls the hottest temperature every 2 s, smooths it with an EMA, and writes the new target — even when the app is closed.

## Install

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Juanipis/fanctl/main/scripts/install.sh | bash
```

That script:
1. Downloads the latest `FanCtl.app.zip` from GitHub Releases.
2. Verifies its `sha256` against the `.sha256` sidecar.
3. Drops `FanCtl.app` into `/Applications`, removes the quarantine flag (the build is ad-hoc signed, not notarized).
4. Opens the app. The fan icon appears in your menu bar.

### Manual

1. Grab `FanCtl-X.Y.Z.zip` from the [latest release](https://github.com/Juanipis/fanctl/releases/latest).
2. Unzip and move `FanCtl.app` to `/Applications`.
3. Because it isn't notarized, run once:
   ```bash
   xattr -dr com.apple.quarantine /Applications/FanCtl.app
   ```
4. Open it. A small fan icon appears in the menu bar.

### From source

```bash
git clone https://github.com/Juanipis/fanctl.git
cd fanctl
swift test                          # unit tests
bash Bundle/build-app.sh release    # builds + ad-hoc signs FanCtl.app
bash Bundle/install.sh   release    # copies to /Applications, opens it
```

Requirements: macOS 15+, Xcode 16+ (Swift 6 toolchain).

## First run

The app needs a tiny privileged background helper to talk to the SMC, since
fan writes require root. macOS makes you approve this once.

1. Click the fan icon in your menu bar.
2. Click **Install Helper**.
3. macOS opens **System Settings → General → Login Items & Extensions**. Scroll to **Allow in the Background** and switch the **FanCtl** entry to **ON**.
4. Click **Retry** in the popover. The hero card lights up with live RPM and a sparkline.

You only do this once. The helper survives reboots and runs in the background even when the FanCtl app is closed — that way your selected mode keeps working.

## Daily use

Click the fan icon and pick a mode:

- **Auto** — hands off, macOS owns the fans. Default and safe.
- **Silent** — keeps the fan as quiet as possible. Best for normal browsing/coding.
- **Cool** ❄️ — keeps the chassis cold. Spins up earlier than Apple would.
- **Performance** ⚡ — aggressive cooling under load. Best for compiles, exports, gaming.
- **Manual** — the slider appears. Drag wherever; presets for Min / Mid / Max underneath.

The selected mode is **persisted** — if you reboot, the helper restarts and resumes the same mode automatically.

If anything ever goes wrong (app crash, helper hang, machine over-heats), the helper falls back to **Auto** within seconds and macOS regains control. You can never leave the machine stuck in manual.

## Uninstall

```bash
git clone https://github.com/Juanipis/fanctl.git    # if you don't have it
cd fanctl
bash Bundle/uninstall.sh
```

Or by hand:

1. Quit FanCtl from the menu bar.
2. System Settings → General → Login Items & Extensions → set **FanCtl** to **OFF**.
3. `rm -rf /Applications/FanCtl.app`.

## Architecture

```
┌──────────────────────────────────────────┐
│ FanCtl.app  (SwiftUI · MenuBarExtra)     │
│  - Liquid Glass popover                  │
│  - Sparkline (Charts framework)          │
│  - Mode picker, slider, temps            │
└────────────┬─────────────────────────────┘
             │ NSXPCConnection
             ▼
┌──────────────────────────────────────────┐
│ com.jpdiaz.FanCtl.Helper                 │
│  (LaunchDaemon, root, SMAppService)      │
│  - Curve evaluator (2 Hz)                │
│  - Watchdog: dead-man + thermal panic    │
│  - Rate limit: ≤ 2 writes/sec/fan        │
└────────────┬─────────────────────────────┘
             │ IOConnectCallStructMethod
             ▼
┌──────────────────────────────────────────┐
│ AppleSMCKeysEndpoint  (IOKit)            │
└──────────────────────────────────────────┘
```

The shared `SMCKit` Swift Package is reused by the app, the helper, and a small `fanctl-cli` for debugging.

## CLI

The package also produces a CLI binary, useful for development and triage:

```
$ swift run fanctl-cli status
Fans: 1
  F0  cur=  2502  tgt=  2317  min=  2317  max=  6550  [AUTO]

Top temperatures:
  TVmS   60.83 °C
  TVMS   55.23 °C
  ...

$ sudo swift run fanctl-cli set 0 4500    # write needs root
$ sudo swift run fanctl-cli auto 0
$ swift run fanctl-cli watch              # live refresh
$ swift run fanctl-cli dump | head        # enumerate every SMC key
```

## Safety

FanCtl can never leave your machine stuck in manual at 0 RPM:

- The helper **clamps** every target to `[F<n>Mn, F<n>Mx]`.
- A **2 s rate limit** prevents accidental SMC hammering.
- The **dead-man watchdog** forces `auto` if the app stops sending heartbeats.
- The **thermal panic** forces `auto` if the hottest sensor crosses 95 °C.
- On uninstall (`Bundle/uninstall.sh`) the helper sets every fan to `auto` first.

## Author

**Juan Pablo Díaz Correa**
[github.com/Juanipis](https://github.com/Juanipis)

## License

MIT — see [LICENSE](LICENSE).
