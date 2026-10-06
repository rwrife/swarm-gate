# SwarmGateKit

Pure Swift integer fixed-tick engine. `Simulation(seed:rules:inputs:)` snapshots a
`RuleTable` and an `InputScript`; call `step()` or `advance(ticks:)` to simulate.
`RuleTable.v1` starts with one column and one zombie, adding a column, depth unit,
and speed unit each wave until their caps. Every fifth wave includes a boss.
Seeded SplitMix64 chooses column start and boss lanes. Columns use adjacent lanes
and one distance unit of spacing; steering moves one lane per tick only when the
pre-move distance is within the convergence radius.

Capture inputs with `InputScript.capture(tick:action:)`. Same-tick capture order
is preserved. Tick order is inputs, scheduled spawns, steering, movement, bites.
Lane inputs clamp to the battlefield. Fire hits the nearest zombie in the player
lane, with spawn order breaking ties. Gate arrival bites once and removes the
zombie. Health depletion ends the run; subsequent steps do nothing.

`ledger.encodedBytes()` returns canonical UTF-8 bytes: a
`swarm-gate|ruleVersion|seed` header, then ordered
`tick|kind|id|lane|distance|value` rows, each ending in LF. Non-zombie events use
ID -1. Values are the requested lane for move input, remaining zombie HP for
spawn/hit, remaining player HP for bite, and zero otherwise. Rules and ledger
encoding are a versioned gameplay contract; share the same rule table and script
for replay. Custom tables must meet the simulation initializer's preconditions and use a
new version when behavior changes. No pickups, rendering, or persistence live here.

Run the Linux tests with the repository CI toolchain:

```sh
docker run --rm -v "$PWD:/workspace" -w /workspace swift:6.2-noble swift test --package-path Packages/SwarmGateKit
```
