# v1 migration fixture

`v1.sqlite` was generated from `RunStore(path:)` at schema version `v1` using a deterministic `Simulation(seed: RunSeed(UInt64.max))` advanced 1,000 ticks until its terminal `end` event, with `RunRecord(id: "fixture-1", mode: .endless, ledger: sim.ledger, waveInterval: sim.rules.waveInterval)`. The database was closed before commit. Keep this frozen when adding v2 migrations; the migration test opens a copy, asserts the source record and appends a fresh one after migration.

Recreate only when intentionally changing the v1 baseline: temporarily add a test that creates the store at `SWARM_GATE_FIXTURE_PATH`, appends that exact run, execute it in `swift:6.2-noble` with `libsqlite3-dev` in the same container, then remove the test and run `swift test --package-path Packages/SwarmGateStore` against the new fixture. Never overwrite the committed fixture during ordinary tests.
