import Testing
@testable import SwarmGateKit

@Test func headlessReplayBindsSameSeedToIdenticalSummaryAndLedger() {
    let rules = RuleTable.v3
    #expect(rules.version == 3)
    #expect(rules.pickupEveryWaves == 1)

    var simA = Simulation(seed: RunSeed(1337), rules: rules)
    simA.queue(.move(lane: 1))
    simA.queue(.fire)
    simA.advance(ticks: 120)
    simA.queue(.bomb)
    simA.advance(ticks: 300)

    var simB = Simulation(seed: RunSeed(1337), rules: rules, inputs: simA.inputs)
    simB.advance(ticks: simA.tick)

    #expect(simA.ledger.encodedBytes() == simB.ledger.encodedBytes())
    #expect(simA.health == simB.health)
    #expect(simA.firepower == simB.firepower)
    #expect(simA.bombs == simB.bombs)
}
