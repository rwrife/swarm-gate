import Testing
@testable import SwarmGateKit

@Test func liveInputsAreCapturedOnTheirExactTickAndReplayIdentically() {
    var live = Simulation(seed: RunSeed(42), rules: .v2)
    live.queue(.move(lane: 2))
    live.step()
    live.queue(.fire)
    live.step()
    live.advance(ticks: 400)
    var replay = Simulation(seed: RunSeed(42), rules: .v2, inputs: live.inputs)
    replay.advance(ticks: 402)
    #expect(live.isEnded)
    #expect(replay.ledger.encodedBytes() == live.ledger.encodedBytes())
    #expect(replay.health == live.health)
    #expect(replay.tick == live.tick)
}
