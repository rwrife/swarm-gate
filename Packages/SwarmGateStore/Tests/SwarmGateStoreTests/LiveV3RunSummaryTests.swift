import Testing
import SwarmGateKit
@testable import SwarmGateStore

@Test func runRecordFromLiveV3SimulationProducesHonestSummary() {
    var sim = Simulation(seed: RunSeed(99), rules: .v3)
    sim.queue(.move(lane: 0))
    sim.queue(.fire)
    sim.step()
    sim.advance(ticks: 400)
    #expect(sim.isEnded)

    let record = RunRecord(id: "test-v3-run", mode: .career, ledger: sim.ledger, waveInterval: sim.rules.waveInterval)
    let summary = record.summary
    #expect(summary != nil)
    #expect(summary?.wave == sim.tick / sim.rules.waveInterval + 1)
    #expect(summary?.score == sim.ledger.events.filter { $0.kind == .kill || $0.kind == .bombKill }.count)
    #expect(summary?.ticks == sim.tick)
}
