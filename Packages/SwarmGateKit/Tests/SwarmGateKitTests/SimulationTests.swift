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
