# Roadmap

Living document. Items are ordered roughly by priority within each tier,
not strictly committed. PRs welcome on anything here.

## Now — next bundle

| # | Item | Why |
|---|------|-----|
| 1 | **Screenshots + animated GIFs in README and landing page** | The repo currently shows zero visuals; readers can't tell at a glance what they get. |
| 2 | **`fanctl-cli diag`** — collect helper + app + system state into a single zip suitable for bug reports | Asking users to run multiple `log stream` commands is painful; one command should produce everything we need. |
| 3 | **Helper / curve / watchdog tests** | `SMCKit` has 5 tests; the helper logic, hysteresis, dead-man and thermal panic have zero. |
| 4 | **CPU / GPU load sensing** | Today the curve only reacts to temperature; combining with `IOReport`-fed load lets us anticipate instead. |

## Engineering polish

| # | Item | Why |
|---|------|-----|
| 5 | **Lower hysteresis floor for slow drifts** | Current 5% rejects useful slow ramps; consider time-based instead of pure delta-based. |
| 6 | **Persist + display recent watchdog events** | When the watchdog forces auto, surface a non-modal log inside the popover so users learn why. |
| 7 | **Standalone main window** with bigger chart, full temp list, exportable history | The popover is great for at-a-glance, but enthusiasts want more breadth. |
| 8 | **Per-fan modes** | M5 has 1 fan so it doesn't matter for me, but MBP 16" users may want different curves per fan. |
| 9 | **Curve editor: add/delete points** | Editor currently locks point count at 3 (the default seed). |
| 10 | **Curve editor: snap-to-temperature gridlines** | Easier to land on round numbers (40, 50, 60 °C). |

## Advanced features

| # | Item | Why |
|---|------|-----|
| 11 | **Battery vs AC profiles** | Different curves on battery (silence-first) vs plugged in (cool-first). |
| 12 | **Lid-state awareness** | Closed-lid clamshell + plugged in is a different thermal regime. |
| 13 | **Multi-Mac sync via iCloud** | Share custom curves across your Macs. |
| 14 | **Per-app profiles** | Switch to Performance when the active app is Final Cut, Silent for Slack. Polls `NSWorkspace.frontmostApplication`. |
| 15 | **HUD on RPM change** | Like the volume HUD: a small overlay when the fan target moves dramatically. |
| 16 | **Daily / weekly digest** | Notification summarizing peak temp, time spent at >80 °C, etc. |

## Distribution & community

| # | Item | Why |
|---|------|-----|
| 17 | **Submit cask to `homebrew/cask`** | Wider visibility than the personal tap. Requires meeting their checklist. |
| 18 | **Localize to Portuguese, French, Japanese** | Spanish is in; expanding to common Mac markets is cheap once `Localizable.strings` is wired. |
| 19 | **Press kit / launch announcement** | Hacker News / Lobsters / r/macapps post when v2 ships. |
| 20 | **CONTRIBUTING.md expansion** | Test matrix per Mac model, how to add a sensor, how to add a mode. |

## Wild / probably never

| # | Item | Why we're skipping for now |
|---|------|----------------------------|
| 21 | Intel Mac support | Would require maintaining the legacy `AppleSMC` IOKit path; my hardware is M5 and drift is real. |
| 22 | Older macOS support (< 15) | `MenuBarExtra` + Liquid Glass + `Charts` API surface is too useful to drop. |
| 23 | Apple Developer ID + notarization | Out of scope by author preference. Ad-hoc + the cask `postflight xattr` clear is good enough for personal use. |
| 24 | Submit to the App Store | Sandbox + privileged-helper interaction won't be accepted; ad-hoc redistribution is the only realistic channel. |

## Done (recent highlights)

- Five smart cooling modes (Auto, Silent, Cool, Performance, Manual)
- Custom curve mode + draggable curve editor in Preferences
- Sensor picker (any SMC temperature key drives the curve)
- Notifications (>90 °C, watchdog kick)
- Mode pill tooltips with curve summary
- Outdated-helper banner with one-click restart
- Sparkle in-app auto-updates
- Homebrew cask in `Juanipis/tap` with auto-bump in CI
- semantic-release pipeline + EdDSA-signed appcast
- Spanish localization
- GitHub Pages landing page
- App icon generator (Swift + SF Symbols)
- History persistence + curve hysteresis

> _If you want to pick something up, open an issue first so we can discuss
> scope. Most items above are good first issues — the SMC layer is the
> deep magic, everything else is regular Swift._
