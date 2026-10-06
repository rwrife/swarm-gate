# Swarm Gate

**Pitch:** Local-first iPhone zombie-wave lane-defense game: hold the gate against converging hordes, weigh buffs against power-downs, drop bombs, face boss zombies, and keep honest personal-best records with user-owned backup — no accounts, no cloud, no ads.

Swarm Gate is a portrait-only arcade lane-defense game. Waves of stylized zombies descend from the top of the screen in tight columns; once they get close they converge on the player at the bottom. The player holds the gate with incremental firepower buffs, limited-use weapons, and bombs — and must decide whether to grab a power-down that sits in front of a deadly cluster. If the horde reaches the gate, the player is overrun and the run ends. Rounds start easy and escalate fast into a panic-inducing rush.

## Motivation

Wave-defense arcade games are deep in the App Store charts, but the modern leaders are wrapped in energy timers, daily-login mechanics, ad breaks, loot boxes, and cloud accounts. The core fantasy — one thumb, a tightening horde, split-second buff-vs-curse decisions — is still thrilling when stripped back. Swarm Gate rebuilds that loop as a fully offline, deterministic, session-short game: every run is seeded, every personal best is honest, and every byte of data belongs to the player.

The thought inbox capture that seeded this project (2026-09-02) asked for exactly this: portrait wave defense, hundreds of zombies in tight columns that converge near the player, incremental firepower power-ups, limited-use weapons and bombs, meaningful power-downs you must *choose* to take, boss zombies that take a long time to kill, and an easy-to-panic difficulty curve.

## Target users

- iPhone players who want a one-handed, portrait, session-short arcade game.
- Fans of classic wave-defense/shmup-adjacent arcade action who dislike energy systems, ads, and accounts.
- Score-attack players who care about reproducible runs, honest records, and owning their data.

## Concrete use cases

- A two-to-five minute run on the commute: start a seeded run, survive escalating waves, die at a personal-best wave number, see the honest run summary.
- A challenge week: share a seed code locally (face to face, not over a network) so two players fight the identical horde and compare the ledger.
- Endless mode: no boss schedule cap, leaderboard of your own personal bests only, stored on-device.
- Boss hunt: random boss-sized zombies appear mid-run with heavy HP, forcing bomb/limited-weapon timing decisions.

## How to use (intended end-to-end workflow)

1. Launch the app (offline works; nothing needs the network).
2. Pick Quick Run (random seed), Seed Run (enter/share a seed), or Endless mode.
3. Hold the gate with one thumb: tap/drag to aim fire, tap pickups to accept or ignore buffs and power-downs, swipe to drop a bomb.
4. When overrun, review the run summary: waves survived, peak firepower, buffs vs power-downs taken, bombs used, boss encounters, and whether any personal best changed.
5. Records live on-device. Export a CSV of the run ledger or a versioned JSON backup from Settings whenever you want; restoring a backup previews the diff first.

## MVP features

- Deterministic, seeded fixed-tick wave engine (pure-Swift `SwarmGateKit`): column spawn scheduler, proximity convergence steering, player-gate bite/overrun rule, boss-zombie spawn schedule with heavy HP.
- Pickup economy: incremental firepower buffs, limited-use weapons, bombs, and power-downs that are always opt-in — taking one is always a visible choice, never a forced effect.
- Career + endless modes; append-only run ledger; personal-best derivation that is unknown-safe (a run with missing data never counts as a zero or a record).
- Versioned JSON backup with previewed restore and CSV run-ledger export, all user-initiated via Files.
- Portrait-only, one-thumb, accessible SwiftUI shell + SpriteKit battlefield; Dynamic Type in menus, reduce-motion respect, VoiceOver coverage of all non-gameplay chrome.
- Zero network: the binary makes no outbound connections; CI enforces an empty network allowlist.

## Explicit non-goals

- No cross-platform/hybrid frameworks: native Swift only — no Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or equivalents anywhere (scaffolds, docs, CI, issues, PRs).
- Android is out of scope; native iPad support is disabled and out of scope without explicit user opt-in.
- No accounts, no cloud sync, no ads, no in-app purchases, no loot boxes, no energy systems, no daily-login mechanics.
- No franchise IP: all zombies, names, art, and audio are original. No licensed properties.
- No multiplayer, no leaderboards over the network, no telemetry or analytics.
- Not a medical or wellness product; no health-benefit claims. Stylized cartoon-vs-monsters conflict only — no realistic gore or real-world violence theming.
- No live fold/dual-screen SDK dependency today (see dual-screen plan below).

## iPhone Duo dual-screen design target

The thought that seeded this game was captured for the iPhone Duo dual-screen concept: battlefield and opponent pressure on the top screen, player state plus a persistent one-thumb control deck (fire, pickups, bombs) on the bottom screen. That split is the design target, not a current dependency: full dual-screen/foldable SDK support does not exist yet, so Swarm Gate scaffolds and ships as a standard native Swift iPhone app with iPad support disabled by default. All workspace-split decisions are isolated behind a single `DefenseWorkspaceLayout` seam. When Apple ships usable dual-screen APIs, migrating the battlefield and the control deck onto the two surfaces is a layout swap behind that seam — no engine or data-layer change. Tablet/iPad layouts are deferred and require explicit opt-in.

## Privacy, permissions, and data storage

- Fully offline. The app requests no network permission, no push, no HealthKit, no camera, no microphone. Game Center is not used; records are local-only.
- All game data (run ledger, settings, backups) is stored locally (GRDB/SQLite) and never leaves the device unless the user explicitly exports a file via the iOS Files share.
- Backups are versioned JSON with a previewed, replace-only restore; CSV export is a flat run ledger.
- No advertising identifiers, no trackers, no third-party SDKs.

## iOS identity, signing, and release plan

- Bundle identifier: `com.infinityball.swarmgate` (registered in App Store Connect at scaffold time; result: `CREATED com.infinityball.swarmgate`). It is used in PRODUCT_BUNDLE_IDENTIFIER, Info.plist, and all signing/provisioning configuration — never another prefix.
- Device family: iPhone-only. TARGETED_DEVICE_FAMILY = 1 in every app-target build configuration; the built app's UIDeviceFamily must verify as `[1]` on an Apple build environment.
- Toolchain: iOS 26+ SDK, pinned Xcode 26.0.1 (17A400) / iOS SDK 26.0 / Swift 6 in `toolchain.json`. Never scaffold against an older SDK.
- Release path: `.github/workflows/release.yml` ported from the proven rwrife/cook-console template (also green in rise-log, split-slip, catch-tally): `v*` tag or manual dispatch → macos-26 job → iOS 26+ SDK enforcement → signed IPA archive → TestFlight upload via the App Store Connect API using the repository secrets ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, and ASC_TEAM_ID (names only; values are never logged) → GitHub release.
- App Store listing copy lives at `AppStore/description.txt` and must stay truthful to implemented features. The app icon is generated with the `hermes-image-gen` model into `AppStore/icon.png` (real generated artwork only — no placeholders) and wired into the Xcode app-icon asset catalog.

## Current status

Native SwiftUI iPhone app scaffold and two Swift packages are checked in. The app currently displays an under-construction screen; wave simulation, pickup economy, persistence migrations, and playable battlefield are **not implemented**. No icon or TestFlight build exists yet. CI builds the app and tests the package scaffolds; its results are not gameplay validation.

Milestones:
1. **M1 — Skeleton & CI:** Xcode app + Swift package layout, Linux package-test lane, macOS build lane, toolchain/zero-network contract gates.
2. **M2 — Engine:** `SwarmGateKit` seeded wave simulation + pickup economy with golden-seed tests.
3. **M3 — Store & records:** GRDB ledger, personal-best derivation, backup/export.
4. **M4 — Playable UI:** SwiftUI shell + SpriteKit battlefield, HUD, portrait controls, accessibility.
5. **M5 — Release:** icon + listing copy review, `.github/workflows/release.yml`, TestFlight with real evidence.

## Development quickstart

- macOS with the pinned Xcode 26.0.1 (17A400) for the app target; any Swift 6 toolchain for the pure-Swift package.
- `Packages/SwarmGateKit` holds the deterministic engine and runs `swift test` on Linux CI.
- The app target builds with `xcodebuild` on the macOS lane; CI asserts TARGETED_DEVICE_FAMILY = 1 and the exact bundle identifier.
- `swift test --package-path Packages/SwarmGateKit` and `swift test --package-path Packages/SwarmGateStore` run the two independent package test targets. The store package resolves GRDB and needs SQLite development headers on Linux.
- `python3 scripts/check_contract.py` checks the committed project and toolchain identity; `python3 -m unittest discover -s scripts -p 'test_*.py'` tests its negative paths.
- No asset-catalog icon has been generated yet. M5 owns the real generated artwork and its wiring.

## License

MIT — see `LICENSE`.
