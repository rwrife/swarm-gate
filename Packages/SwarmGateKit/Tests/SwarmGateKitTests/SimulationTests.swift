import Testing
import SwarmGateKit

@Test func splitMix64HasKnownVector() {
    var random = SplitMix64(seed: 0)
    #expect((0..<3).map { _ in random.next() } == [
        0xe220a8397b1dcdaf, 0x6e789e6aa1b965f4, 0x06c45d188009454f,
    ])
}

private func smallRules() -> RuleTable {
    RuleTable(version: 7, laneCount: 3, spawnDistance: 10, convergenceRadius: 3,
              playerHealth: 100, zombieHealth: 2, bossHealth: 20, biteDamage: 2,
              shotDamage: 2, waveInterval: 4, initialColumns: 1, maximumColumns: 3,
              initialDepth: 1, maximumDepth: 3, initialSpeed: 1, maximumSpeed: 2,
              bossEveryWaves: 2)
}

@Test func replayLedgersAreByteIdenticalAcrossSeedsIncludingBosses() {
    for seed: UInt64 in [0, 1, 42, UInt64.max] {
        let script = InputScript(events: [
            TickInput(tick: 0, action: .move(lane: 0)),
            TickInput(tick: 3, action: .move(lane: 2)),
            TickInput(tick: 3, action: .fire),
            TickInput(tick: 8, action: .move(lane: 1)),
        ])
        var first = Simulation(seed: RunSeed(seed), rules: smallRules(), inputs: script)
        var second = Simulation(seed: RunSeed(seed), rules: smallRules(), inputs: script)
        first.advance(ticks: 30)
        for _ in 0..<30 { second.step() }
        #expect(first.ledger.encodedBytes() == second.ledger.encodedBytes())
        #expect(first.ledger.events.contains { $0.kind == .bossSpawn })
        #expect(first.ledger.events.filter { $0.kind == .input }.count == 4)
        #expect(first.ledger.ruleVersion == 7)
        #expect(first.ledger.seed == seed)
    }
    var a = Simulation(seed: RunSeed(1), rules: smallRules())
    var b = Simulation(seed: RunSeed(42), rules: smallRules())
    a.advance(ticks: 8)
    b.advance(ticks: 8)
    #expect(a.ledger.encodedBytes() != b.ledger.encodedBytes())
}

@Test func ignoringEveryPickupLeavesStateUnmodifiedExceptDecayRules() {
    var rules = smallRules()
    rules.pickupEveryWaves = 1
    rules.waveInterval = 2
    rules.spawnDistance = 2
    rules.initialSpeed = 2
    rules.maximumSpeed = 2
    rules.firepowerDecayTicks = 100
    rules.playerHealth = 10000
    var script = InputScript()
    for id in 0..<5 { script.capture(tick: id * 2 + 1, action: .ignorePickup(id: id)) }
    var sim = Simulation(seed: RunSeed(42), rules: rules, inputs: script)
    #expect(sim.firepower == 1)
    #expect(sim.weaponAmmo == 0)
    #expect(sim.bombs == 0)
    // Explicitly ignore every pickup after arrival; no inventory changes.
    sim.advance(ticks: 10)
    #expect(sim.firepower == 1)
    #expect(sim.weaponAmmo == 0)
    #expect(sim.bombs == 0)
    #expect(sim.ledger.events.contains { $0.kind == .pickupSpawn })
    #expect(sim.ledger.events.filter { $0.kind == .pickupReady }.count == 5)
    #expect(sim.ledger.events.filter { $0.kind == .pickupIgnore }.count == 5)
    #expect(!sim.ledger.events.contains { $0.kind == .pickupAccept })
}

@Test func noAcceptEventImpliesNoPowerDownEffectAnywhereUnderRandomInputs() {
    var rules = smallRules()
    rules.pickupEveryWaves = 1
    rules.waveInterval = 2
    rules.spawnDistance = 4
    rules.initialSpeed = 2
    rules.maximumSpeed = 2
    rules.firepowerDecayTicks = 1000

    // Fuzz test over multiple seeds and random non-accept inputs (move, fire, bomb, ignore)
    for fuzzSeed in [0, 7, 13, 99, 1337] {
        var rng = SplitMix64(seed: UInt64(fuzzSeed))
        var script = InputScript()
        for t in 0..<30 {
            let roll = rng.next() % 4
            switch roll {
            case 0:
                script.capture(tick: t, action: .move(lane: Int(rng.next() % UInt64(rules.laneCount))))
            case 1:
                script.capture(tick: t, action: .fire)
            case 2:
                script.capture(tick: t, action: .ignorePickup(id: Int(rng.next() % 10)))
            default:
                break
            }
        }
        var sim = Simulation(seed: RunSeed(UInt64(fuzzSeed)), rules: rules, inputs: script)
        for _ in 0..<30 {
            sim.step()
            #expect(sim.firepower == 1)
            #expect(sim.weaponAmmo == 0)
            #expect(sim.bombs == 0)
            #expect(!sim.ledger.events.contains { $0.kind == .pickupAccept })
        }
    }
}

// Locate deterministic seeds by running the actual spawn path, rather than
// injecting pickups through a test-only engine API. The scripts below accept
// only after each pickup has reached the gate zone.
private func pickupRules() -> RuleTable {
    var rules = smallRules()
    rules.pickupEveryWaves = 1
    rules.waveInterval = 12
    rules.spawnDistance = 10
    rules.initialSpeed = 1
    rules.maximumSpeed = 1
    rules.bossEveryWaves = 100
    rules.playerHealth = 10000
    rules.firepowerDecayTicks = 1000
    return rules
}

private func seedForPrefix(_ kinds: [PickupKind], rules: RuleTable) -> RunSeed? {
    for value: UInt64 in 0..<5000 {
        var probe = Simulation(seed: RunSeed(value), rules: rules)
        probe.advance(ticks: 12 * kinds.count)
        let spawned = probe.ledger.events.filter { $0.kind == .pickupSpawn }
        if spawned.count == kinds.count && zip(spawned, kinds).allSatisfy({ $0.value == $1.rawValue }) {
            return RunSeed(value)
        }
    }
    return nil
}

@Test func buffsStackIncrementallyWithDefinedCaps() throws {
    var rules = pickupRules()
    rules.maximumFirepower = 3
    let seed = try #require(seedForPrefix([.buff, .buff, .buff], rules: rules))
    let script = InputScript(events: [
        TickInput(tick: 10, action: .acceptPickup(id: 0)),
        TickInput(tick: 22, action: .acceptPickup(id: 1)),
        TickInput(tick: 34, action: .acceptPickup(id: 2)),
    ])
    var sim = Simulation(seed: seed, rules: rules, inputs: script)
    sim.advance(ticks: 11)
    #expect(sim.firepower == 2)
    sim.advance(ticks: 12)
    #expect(sim.firepower == 3)
    sim.advance(ticks: 12)
    #expect(sim.firepower == 3)
    #expect(sim.ledger.events.filter { $0.kind == .pickupAccept }.count == 3)
}

@Test func powerDownPenaltyNeverAppliesWithoutExplicitAccept() throws {
    let rules = pickupRules()
    let seed = try #require(seedForPrefix([.buff, .powerDown], rules: rules))
    var script = InputScript()
    script.capture(tick: 10, action: .acceptPickup(id: 0))
    script.capture(tick: 22, action: .ignorePickup(id: 1))
    var sim = Simulation(seed: seed, rules: rules, inputs: script)
    sim.advance(ticks: 23)
    #expect(sim.firepower == 2)
    #expect(!sim.ledger.events.contains { $0.kind == .pickupAccept && $0.value == PickupKind.powerDown.rawValue })
}

@Test func powerDownPenaltyAppliesWhenExplicitlyAccepted() throws {
    let rules = pickupRules()
    let seed = try #require(seedForPrefix([.buff, .powerDown], rules: rules))
    var script = InputScript()
    script.capture(tick: 10, action: .acceptPickup(id: 0))
    script.capture(tick: 22, action: .acceptPickup(id: 1))
    var sim = Simulation(seed: seed, rules: rules, inputs: script)
    sim.advance(ticks: 23)
    #expect(sim.firepower == 1)
    #expect(sim.ledger.events.contains { $0.kind == .pickupAccept && $0.value == PickupKind.powerDown.rawValue })
}

@Test func buffDecayReducesFirepowerToFloorAtConfiguredCadence() throws {
    var rules = pickupRules()
    rules.firepowerDecayTicks = 5
    let seed = try #require(seedForPrefix([.buff, .buff], rules: rules))
    let script = InputScript(events: [TickInput(tick: 11, action: .acceptPickup(id: 0))])
    var sim = Simulation(seed: seed, rules: rules, inputs: script)
    sim.advance(ticks: 12)
    #expect(sim.firepower == 2)
    sim.advance(ticks: 4)
    #expect(sim.firepower == 1)
    #expect(sim.ledger.events.contains { $0.kind == .buffDecay && $0.tick == 15 && $0.value == 1 })
    sim.advance(ticks: 5)
    #expect(sim.firepower == 1)
    #expect(sim.ledger.events.filter { $0.kind == .buffDecay }.count == 1)
}

@Test func nonAcceptedPowerDownPreservesEarnedBuffAndAmmoAcrossScripts() throws {
    var rules = pickupRules()
    rules.firepowerDecayTicks = 1000
    let seed = try #require(seedForPrefix([.buff, .weapon, .powerDown], rules: rules))
    for inputSeed: UInt64 in 0..<32 {
        var rng = SplitMix64(seed: inputSeed)
        var script = InputScript()
        script.capture(tick: 10, action: .acceptPickup(id: 0))
        script.capture(tick: 22, action: .acceptPickup(id: 1))
        for tick in 24..<35 {
            switch rng.next() % 3 {
            case 0: script.capture(tick: tick, action: .move(lane: Int(rng.next() % 3)))
            case 1: script.capture(tick: tick, action: .ignorePickup(id: 2))
            default: script.capture(tick: tick, action: .bomb)
            }
        }
        var sim = Simulation(seed: seed, rules: rules, inputs: script)
        sim.advance(ticks: 36)
        #expect(sim.ledger.events.contains { $0.kind == .pickupSpawn && $0.value == PickupKind.powerDown.rawValue })
        #expect(!sim.ledger.events.contains { $0.kind == .pickupAccept && $0.value == PickupKind.powerDown.rawValue })
        #expect(sim.firepower == 2)
        #expect(sim.weaponAmmo == rules.weaponGrantAmmo)
    }
}

@Test func weaponGrantCapsAndFireConsumesOnlyOnHit() throws {
    var rules = pickupRules()
    rules.maximumWeaponAmmo = 7
    rules.weaponGrantAmmo = 4
    rules.zombieHealth = 15
    rules.bossHealth = 40
    let seed = try #require(seedForPrefix([.weapon, .weapon], rules: rules))
    var probe = Simulation(seed: seed, rules: rules)
    probe.advance(ticks: 13)
    let lane = try #require(probe.ledger.events.first { $0.kind == .spawn && $0.tick == 12 }?.lane)
    var script = InputScript()
    script.capture(tick: 10, action: .acceptPickup(id: 0))
    script.capture(tick: 13, action: .move(lane: lane))
    script.capture(tick: 13, action: .fire)
    script.capture(tick: 22, action: .acceptPickup(id: 1))
    var sim = Simulation(seed: seed, rules: rules, inputs: script)
    sim.advance(ticks: 14)
    #expect(sim.weaponAmmo == 3)
    #expect(sim.ledger.events.contains { $0.kind == .hit && $0.tick == 13 && $0.value == 11 })
    sim.advance(ticks: 9)
    #expect(sim.weaponAmmo == 7)
    #expect(sim.ledger.events.filter { $0.kind == .pickupAccept && $0.value == PickupKind.weapon.rawValue }.count == 2)
}

@Test func invalidAndDuplicateAcceptInputsAreNoOps() throws {
    let rules = pickupRules()
    let seed = try #require(seedForPrefix([.buff], rules: rules))
    let script = InputScript(events: [
        TickInput(tick: 0, action: .acceptPickup(id: 0)),
        TickInput(tick: 9, action: .acceptPickup(id: 0)),
        TickInput(tick: 10, action: .acceptPickup(id: 999)),
        TickInput(tick: 10, action: .acceptPickup(id: 0)),
        TickInput(tick: 10, action: .acceptPickup(id: 0)),
    ])
    var sim = Simulation(seed: seed, rules: rules, inputs: script)
    sim.advance(ticks: 14)
    #expect(sim.firepower == 2)
    #expect(sim.ledger.events.filter { $0.kind == .pickupAccept }.count == 1)
    #expect(sim.ledger.events.contains { $0.kind == .pickupReady })
    #expect(!sim.pickups.contains { $0.id == 0 })
}

@Test func expiredPickupCannotBeAccepted() throws {
    let rules = pickupRules()
    let seed = try #require(seedForPrefix([.buff, .powerDown], rules: rules))
    var script = InputScript()
    script.capture(tick: 10, action: .acceptPickup(id: 0))
    script.capture(tick: 25, action: .acceptPickup(id: 1))
    var sim = Simulation(seed: seed, rules: rules, inputs: script)
    sim.advance(ticks: 26)
    #expect(sim.ledger.events.contains { $0.kind == .pickupExpire && $0.id == 1 })
    #expect(!sim.ledger.events.contains { $0.kind == .pickupAccept && $0.id == 1 })
    #expect(sim.firepower == 2)
}

@Test func bombClearsOnlyCurrentLaneSegmentAndPreservesOthers() throws {
    var rules = pickupRules()
    rules.bombReach = 4
    rules.maximumBombs = 1
    let seed = try #require(seedForPrefix([.bomb, .bomb], rules: rules))
    var script = InputScript()
    script.capture(tick: 10, action: .acceptPickup(id: 0))
    script.capture(tick: 22, action: .acceptPickup(id: 1))
    var sim = Simulation(seed: seed, rules: rules, inputs: script)
    sim.advance(ticks: 23)
    #expect(sim.bombs == 1) // Capped at 1
    var probe = Simulation(seed: seed, rules: rules)
    probe.advance(ticks: 18)
    let lane = try #require(probe.zombies.first { $0.distance <= rules.bombReach }?.lane)
    let killed = probe.zombies.filter { $0.lane == lane && $0.distance <= rules.bombReach }
    let preserved = probe.zombies.filter { $0.lane != lane || $0.distance > rules.bombReach }
    #expect(!killed.isEmpty)
    #expect(preserved.contains { $0.lane != lane })
    #expect(preserved.contains { $0.lane == lane && $0.distance > rules.bombReach })
    script = InputScript()
    script.capture(tick: 10, action: .acceptPickup(id: 0))
    script.capture(tick: 18, action: .move(lane: lane))
    script.capture(tick: 18, action: .bomb)
    script.capture(tick: 18, action: .bomb) // Empty inventory: no second clear.
    sim = Simulation(seed: seed, rules: rules, inputs: script)
    sim.advance(ticks: 19)
    #expect(sim.bombs == 0)
    #expect(sim.ledger.events.filter { $0.kind == .bomb }.count == 1)
    #expect(sim.ledger.events.filter { $0.kind == .bombKill }.map(\.id) == killed.map(\.id))
    for zombie in preserved {
        #expect(sim.zombies.contains { $0.id == zombie.id })
    }
}

@Test func goldenSeedPickupLedgerIsByteIdentical() {
    let rules = pickupRules()
    var script = InputScript()
    script.capture(tick: 10, action: .acceptPickup(id: 0))
    script.capture(tick: 11, action: .fire)
    var sim = Simulation(seed: RunSeed(42), rules: rules, inputs: script)
    sim.advance(ticks: 15)
    let golden = "swarm-gate|7|42\n"
        + "0|spawn|0|1|10|2\n"
        + "0|pickupSpawn|0|1|10|3\n"
        + "9|bite|0|1|0|9998\n"
        + "9|pickupReady|0|1|0|3\n"
        + "10|input|-1|1|0|0\n"
        + "10|pickupAccept|0|1|0|3\n"
        + "11|input|-1|1|0|0\n"
        + "12|spawn|1|0|10|2\n"
        + "12|spawn|2|0|11|2\n"
        + "12|spawn|3|1|10|2\n"
        + "12|spawn|4|1|11|2\n"
        + "12|pickupSpawn|1|1|10|1\n"
    #expect(sim.ledger.encodedBytes() == Array(golden.utf8))
}

@Test func seededPickupReplaysAreByteIdentical() {
    let rules = pickupRules()
    for seed: UInt64 in [0, 1, 42, UInt64.max] {
        var script = InputScript()
        script.capture(tick: 10, action: .acceptPickup(id: 0))
        script.capture(tick: 22, action: .ignorePickup(id: 1))
        script.capture(tick: 24, action: .bomb)
        var first = Simulation(seed: RunSeed(seed), rules: rules, inputs: script)
        var second = Simulation(seed: RunSeed(seed), rules: rules, inputs: script)
        first.advance(ticks: 36)
        for _ in 0..<36 { second.step() }
        #expect(first.ledger.encodedBytes() == second.ledger.encodedBytes())
        #expect(first.pickups == second.pickups)
        #expect(first.ledger.events.filter { $0.kind == .pickupSpawn }.count == 3)
    }
}

@Test func columnsStayTightAndConvergeOnlyInsideRadius() {
    var rules = smallRules()
    rules.waveInterval = 100
    rules.initialDepth = 3
    rules.maximumSpeed = 1
    rules.bossEveryWaves = 100
    var sim = Simulation(seed: RunSeed(0), rules: rules,
                         inputs: InputScript(events: [TickInput(tick: 0, action: .move(lane: 2))]))
    sim.step()
    #expect(sim.zombies.count == 3)
    #expect(Set(sim.zombies.map(\.lane)).count == 1)
    #expect(sim.zombies.map(\.distance) == [9, 10, 11])
    var sawSteering = false
    for _ in 0..<12 {
        let before = sim.zombies
        sim.step()
        for old in before {
            if let new = sim.zombies.first(where: { $0.id == old.id }) {
                if old.distance > rules.convergenceRadius {
                    #expect(new.lane == old.lane)
                } else if old.lane != sim.playerLane {
                    #expect(abs(new.lane - old.lane) == 1)
                    #expect(abs(new.lane - sim.playerLane) < abs(old.lane - sim.playerLane))
                    sawSteering = true
                }
            }
        }
    }
    #expect(sawSteering)
}

@Test func wavesEscalateAndBossesFollowWaveSchedule() {
    var sim = Simulation(seed: RunSeed(42), rules: smallRules())
    sim.advance(ticks: 9)
    let spawns = sim.ledger.events.filter { $0.kind == .spawn || $0.kind == .bossSpawn }
    #expect(spawns.filter { $0.tick == 0 }.count == 1)
    #expect(spawns.filter { $0.tick == 4 }.count == 5)
    #expect(spawns.filter { $0.tick == 8 }.count == 9)
    #expect(spawns.filter { $0.kind == .bossSpawn }.map(\.tick) == [4])
    #expect(spawns.first { $0.kind == .bossSpawn }?.value == 20)
    #expect(sim.zombies.contains { $0.speed == 2 })
}

@Test func gateBitesDepleteHealthAndEndRunExactlyOnce() {
    var rules = smallRules()
    rules.spawnDistance = 1
    rules.convergenceRadius = 0
    rules.playerHealth = 3
    rules.waveInterval = 1
    var sim = Simulation(seed: RunSeed(0), rules: rules)
    sim.step()
    #expect(sim.health == 1)
    #expect(!sim.isEnded)
    sim.step()
    #expect(sim.health == 0)
    #expect(sim.isEnded)
    #expect(sim.ledger.events.filter { $0.kind == .end }.count == 1)
    let bytes = sim.ledger.encodedBytes()
    let tick = sim.tick
    sim.advance(ticks: 10)
    #expect(sim.tick == tick)
    #expect(sim.ledger.encodedBytes() == bytes)
}

@Test func inputCaptureReplaysStableSameTickOrderAndFire() {
    var rules = smallRules()
    rules.laneCount = 1
    rules.maximumColumns = 1
    rules.waveInterval = 100
    var captured = InputScript()
    captured.capture(tick: 1, action: .fire)
    captured.capture(tick: 0, action: .move(lane: 99))
    captured.capture(tick: 0, action: .move(lane: -99))
    var sim = Simulation(seed: RunSeed(0), rules: rules, inputs: captured)
    sim.advance(ticks: 2)
    #expect(sim.playerLane == 0)
    #expect(sim.zombies.isEmpty)
    #expect(sim.ledger.events.filter { $0.kind == .input }.map(\.value) == [99, -99, 0])
    #expect(sim.ledger.events.contains { $0.kind == .kill })
    let golden = "swarm-gate|7|0\n"
        + "0|input|-1|0|0|99\n0|input|-1|0|0|-99\n"
        + "0|spawn|0|0|10|2\n1|input|-1|0|0|0\n"
        + "1|hit|0|0|9|0\n1|kill|0|0|9|0\n"
    #expect(sim.ledger.encodedBytes() == Array(golden.utf8))
}

@Test func bossWaveGoldenBytes() {
    // Independently pinned SplitMix64 lane draws: first wave, second wave, boss.
    let fixtures: [(UInt64, [Int])] = [
        (0, [1, 0, 1]), (1, [2, 1, 0]), (42, [1, 1, 0]), (UInt64.max, [2, 0, 1]),
    ]
    var rules = smallRules()
    rules.waveInterval = 2
    rules.maximumDepth = 1
    rules.maximumSpeed = 1
    for (seed, lanes) in fixtures {
        var sim = Simulation(seed: RunSeed(seed), rules: rules)
        sim.advance(ticks: 3)
        let golden = "swarm-gate|7|\(seed)\n"
            + "0|spawn|0|\(lanes[0])|10|2\n"
            + "2|spawn|1|\(lanes[1])|10|2\n"
            + "2|spawn|2|\((lanes[1] + 1) % 3)|10|2\n"
            + "2|bossSpawn|3|\(lanes[2])|10|20\n"
        #expect(sim.ledger.encodedBytes() == Array(golden.utf8))
    }
}
