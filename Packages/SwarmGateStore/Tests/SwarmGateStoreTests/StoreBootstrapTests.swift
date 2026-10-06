import GRDB
import SwarmGateStore
import Testing

@Test func opensLocalMemoryDatabase() throws {
    let queue = try StoreBootstrap.open(at: ":memory:")
    let count = try queue.read { db in try Int.fetchOne(db, sql: "SELECT 1") }
    #expect(count == 1)
}