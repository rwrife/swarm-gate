import Testing
import SwarmGateKit

@Test func seedsRetainTheirIdentity() {
    #expect(RunSeed(42) == RunSeed(42))
    #expect(RunSeed(42) != RunSeed(43))
}