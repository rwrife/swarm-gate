# SwarmGateKit

Pure Swift integer fixed-tick engine. `Simulation(seed:rules:inputs:)` snapshots a
`RuleTable` and an `InputScript`; call `step()` or `advance(ticks:)` to simulate.
`RuleTable.v1` starts with one column and one zombie, adding a column, depth unit,
and speed unit each wave until their caps. Every fifth wave includes a boss.
Seeded SplitMix64 chooses column start and boss lanes. Columns use adjacent lanes
and one distance unit of spacing; steering moves one lane per tick only when the
pre-move distance is within the convergence radius.

Capture inputs with `InputScript.capture(tick:action:)`. Same-tick capture order
is preserved. Tick order is inputs, scheduled spawns, steering, movement, bites,
then pickup descent and buff decay. Lane inputs clamp to the battlefield. Fire
hits the nearest zombie in the player lane, with spawn order breaking ties.
Gate arrival bites once and removes the zombie. Health depletion ends the run;
subsequent steps do nothing.

`RuleTable.v1` remains the no-pickup replay table. `RuleTable.v2` uses a seeded
pickup per wave. Pickups descend with the wave and wait in the gate zone for
`pickupZoneTicks` ticks. Only `acceptPickup(id:)` while ready grants an effect:
stacking firepower up to `maximumFirepower`, counted double-damage weapon ammo
up to `maximumWeaponAmmo`, or a bomb up to `maximumBombs`. An accepted power-down
resets firepower to 1 and drains ammo. `ignorePickup(id:)` and expiry have no
inventory effect. Buffs decay one step every `firepowerDecayTicks`, to floor 1.
A `bomb` input spends one bomb to clear the current lane within `bombReach`.
Fire spends one weapon round only when a target is hit.

`ledger.encodedBytes()` returns canonical UTF-8 bytes: a
`swarm-gate|ruleVersion|seed` header, then ordered
`tick|kind|id|lane|distance|value` rows, each ending in LF. Zombie and pickup
IDs occupy separate namespaces; pickup `value` is `PickupKind.rawValue` for
spawn/ready/accept/ignore/expire. A successful accept always records
`pickupAccept` on that tick; no power-down is applied without one. Non-entity
input and buff-decay events use ID -1. Rules and ledger encoding are a versioned
gameplay contract; share the same rule table and script for replay. Custom tables
must meet the simulation initializer's preconditions and use a new version
when behavior changes. No rendering or persistence lives here.

Run the Linux tests with the repository CI toolchain:

```sh
docker run --rm -v "$PWD:/workspace" -w /workspace swift:6.2-noble swift test --package-path Packages/SwarmGateKit
```
