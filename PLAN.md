# Swarm Gate — PLAN

## Scope

A portrait-only, local-first iPhone zombie-wave lane-defense arcade game. One thumb holds a bottom-of-screen gate against seeded waves of stylized zombies that descend in tight columns and converge at close range; opt-in pickups grant incremental firepower, limited-use weapons, and bombs, and power-downs that must be consciously chosen. Boss zombies appear on a seeded schedule. Runs end on overrun; personal bests are derived from an append-only on-device ledger. Zero network, zero accounts, zero ads/IAP.

Dual-screen (iPhone Duo) battlefield + persistent control-deck split is the documented design target behind the single `DefenseWorkspaceLayout` seam; the shipped shape today is a standard iPhone app because dual-screen SDK APIs do not exist yet.

Out of scope: Android, native iPad support, accounts, cloud, telemetry, multiplayer, monetization, franchise IP, realistic gore. Native Swift only — no Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or other cross-platform/hybrid frameworks anywhere in scaffolds, docs, CI, issues, or PRs.

## Architecture

```
SwarmGateApp (Xcode app target — SwiftUI shell)
├── App scene, menus, settings, run summary (SwiftUI)
├── SpriteKit battlefield scene (gameplay rendering only)
├── DefenseWorkspaceLayout  ← sole dual-screen migration seam
│     today: battlefield + HUD in one portrait window
│     future: battlefield on surface A, persistent control deck on surface B
│
├── SwarmGateKit (pure-Swift SPM package, no UI imports)
│   ├── DeterministicSim   fixed-tick simulation, integer arithmetic
│   ├── SpawnScheduler     seeded column spawns, boss schedule
│   ├── ConvergenceModel   proximity steering into the player lane
│   ├── PickupEconomy      buffs / limited weapons / bombs / power-downs (opt-in)
│   ├── RunLedger          append-only event log; personal-best derivation is unknown-safe
│   └── BackupCodec        versioned JSON backup + previewed restore, CSV export
│
└── SwarmGateStore (GRDB/SQLite persistence, versioned migrations)
```

Key decisions:
- **Simulation is deterministic**: seeded PRNG (splitmix64-style), integer fixed-tick math, and rule-table spawn/boss schedules so the same seed + inputs reproduce the identical run. This makes golden-seed tests meaningful and local seed-challenge sharing honest.
- **Power-downs are never forced**: every pickup landing in the gate zone is accept-or-ignore; the choice is the game's signature decision.
- **Unknown-safe records**: runs with missing/partial ledger data are excluded from derivations rather than counted as zeros; a personal best is only declared from complete evidence.

## Technology choices (rationale)

- **Native Swift (SwiftUI + SpriteKit)** — fleet policy and best tooling fit; SpriteKit is Apple's first-party 2D engine, so the game-track build shape stays native. No prohibited frameworks: no Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity.
- **Pure-Swift engine package** — the deterministic core is testable with `swift test` on Linux CI (fast, cheap), while only the thin shell needs the macOS/Apple lane.
- **GRDB/SQLite store** — append-only ledger with versioned migrations plus a committed fixture DB matches the proven fleet pattern (delve, haymaker, pump-log).
- **Zero network by construction** — empty `network_allowlist` in `toolchain.json`, enforced as a CI contract gate; no permission prompts, no privacy labels needed beyond tracking-off declarations.
- **iOS 26 SDK / Xcode 26.0.1 (17A400) / Swift 6** — fleet pin in `toolchain.json`; never scaffold against an older SDK. iPhone-only device family: TARGETED_DEVICE_FAMILY = 1 in every app-target configuration, native iPad support disabled, built UIDeviceFamily verified `[1]` on the Apple lane.

## Milestones & dependency order

1. **M1 Skeleton & CI** (#1): Xcode project + SPM layout, Linux swift-test lane, macOS xcodebuild lane, contract gates (bundle id, device family, iOS 26 SDK, zero network). No dependencies.
2. **M2 Engine core** (#2): `SwarmGateKit` sim + spawn scheduler + convergence + boss rules. Depends on M1.
3. **M2b Pickup economy** (#3): buffs/limited weapons/bombs/power-down decision state machine. Depends on M2.
4. **M3 Store & records** (#4): GRDB ledger, personal-best derivation, backup/export, fixture-DB tests. Depends on M2 (ledger event schema); parallel with M2b.
5. **M4 Playable UI** (#5): SwiftUI shell + SpriteKit scene + HUD + accessibility, wiring M2/M2b/M3. Depends on M2, M2b, M3.
6. **M5 Listing + icon** (#6): App Store copy review against implemented features, `hermes-image-gen` icon at AppStore/icon.png wired into the asset catalog, privacy/permissions audit. Depends on M4 (copy must match reality).
7. **M6 Release** (#7): `.github/workflows/release.yml` ported from rwrife/cook-console, TestFlight upload with real ASC processing evidence, GitHub release. Depends on M5.

## Testing strategy

- **Engine unit tests (Linux CI):** golden-seed determinism (same seed + scripted inputs ⇒ identical event hash), boss schedule coverage, convergence invariants (columns converge only inside the radius), power-down opt-in guarantee (no state path applies a power-down without an accept event), overrun rule, unknown-safe PB derivations.
- **Persistence tests (Linux CI):** migration round-trips on a committed fixture DB; backup codec property checks (encode→decode identity, restore preview diffs).
- **Apple lane (macos-26):** `xcodebuild` build for simulator, target-family/bundle-ID plist asserts, UI smoke journey on the menus/HUD (no fold APIs; generic simulator destination acceptable for build-only lanes).
- **Evidence discipline:** static checks, Linux package tests, simulator builds, and TestFlight status are always reported distinctly; nothing is "tested" without real tool output.

## Packaging / distribution

- App Store distribution via TestFlight first. The release issue (#7) is satisfied only by a real `.github/workflows/release.yml` ported from the proven rwrife/cook-console template: `v*` tag or manual dispatch → macos-26 job → iOS 26+ SDK enforcement → signed IPA archive → TestFlight upload via the App Store Connect API using the repo's four ASC secrets ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID (names only; values never logged) → wait for ASC processing → GitHub release. Never invent a new signing flow.
- Signing identity: bundle id `com.infinityball.swarmgate` (registered in App Store Connect; `CREATED com.infinityball.swarmgate`), iPhone-only, iOS 26+.
- Listing artifacts: `AppStore/description.txt` kept truthful to shipped features; generated app icon at `AppStore/icon.png` (hermes-image-gen, square, opaque, edge-to-edge, no text/borders/corner radius) wired into the Xcode app-icon asset catalog.

## Risks

- **Determinism vs SpriteKit timing** — gameplay rendering must not drive simulation; the sim advances on fixed ticks fed by captured inputs. Mitigated by golden-seed tests at the engine boundary.
- **Performance with hundreds of entities** — cap on-screen entities, pooling, and SpriteKit texture atlases; measure on-device before claiming "hundreds on screen" in copy.
- **Apple-lane flake** — simctl boot flakes are runner-pool issues; rerun same head SHA, never mask with empty commits.
- **Scope creep toward live-service patterns** — the offline/no-IAP contract is enforced by non-goals above and CI gates.

## Explicit non-goals

No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, or Unity. No Android, no native iPad support (explicit user opt-in required), no accounts, no cloud, no ads, no IAP, no loot boxes, no energy systems, no telemetry, no multiplayer, no network leaderboards, no franchise IP, no realistic gore, no health claims, no live dual-screen SDK dependency (only the DefenseWorkspaceLayout seam).
