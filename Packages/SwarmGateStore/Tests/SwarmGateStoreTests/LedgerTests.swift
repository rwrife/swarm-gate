import Foundation
import GRDB
import SwarmGateKit
@testable import SwarmGateStore
import Testing

private func sampleRun(id: String = "complete", mode: RunMode = .endless) -> RunRecord {
    var sim = Simulation(seed: RunSeed(UInt64.max))
    sim.advance(ticks: 1_000)
    precondition(sim.isEnded)
    return RunRecord(id: id, mode: mode, ledger: sim.ledger, waveInterval: sim.rules.waveInterval)
}

@Test func immutableRunRoundTripAndUnknownSafeRecords() throws {
    let store = try RunStore(path: ":memory:")
    let run = sampleRun()
    try store.append(run)
    #expect(try store.runs() == [run])
    let known = try store.personalBests()
    #expect(known.bestWave != nil)
    #expect(known.longestEndlessTicks == run.summary?.ticks)
    // Truncated run: first event missing breaks sequence and hash.
    var truncated = run
    truncated.id = "truncated"
    truncated.events.removeFirst()
    try store.append(truncated)
    #expect(truncated.summary == nil)
    #expect(try store.personalBests() == known)

    // Parallel ledger with identical complete runs, omitting the truncated run.
    let parallel = try RunStore(path: ":memory:")
    try parallel.append(run)
    let parallelBests = try parallel.personalBests()
    let actualBests = try store.personalBests()
    #expect(parallelBests == actualBests)
    #expect(throws: (any Error).self) { try store.append(run) }
    #expect(try store.runs().count == 2)
    let csv = try store.csv()
    #expect(csv.hasPrefix("id,mode,rule_version,seed,status,wave,score,ticks,bosses_slain\n"))
    #expect(csv.contains("\"truncated\",\"endless\",\"1\",\"18446744073709551615\",\"unknown\",\"\",\"\",\"\",\"\"\n"))
    #expect(csv.contains("\"complete\",\"endless\",\"1\",\"18446744073709551615\",\"complete\","))
}

@Test func backupIdentityPreviewAndReplaceRollback() throws {
    let source = try RunStore(path: ":memory:")
    let first = sampleRun(id: "a,\"\n")
    try source.append(first)
    let encoded = try source.backup()
    let target = try RunStore(path: ":memory:")
    try target.append(sampleRun(id: "old", mode: .career))
    let preview = try target.previewRestore(encoded)
    #expect(preview == BackupPreview(existing: 1, incoming: 1, added: 1, removed: 1, changed: 0))
    try target.restoreReplacingAll(encoded)
    #expect(try target.runs() == [first])
    #expect(try target.backup() == encoded)
    #expect(try target.csv().contains("\"a,\"\"\n\""))
    #expect(throws: (any Error).self) { try target.restoreReplacingAll(Data(#"{"version":2,"runs":[]}"#.utf8)) }
    #expect(try target.runs() == [first])
    #expect(throws: (any Error).self) { try target.restoreReplacingAll(Data(#"{"version":1,"runs":[{},{}]}"#.utf8)) }
    #expect(try target.runs() == [first])
    let empty = Data(#"{"runs":[],"version":1}"#.utf8)
    #expect(try target.previewRestore(empty) == BackupPreview(existing: 1, incoming: 0, added: 0, removed: 1, changed: 0))
    try target.restoreReplacingAll(empty)
    #expect(try target.runs().isEmpty)
    try target.restoreReplacingAll(encoded)
    #expect(try target.runs() == [first])
    // DB trigger guards survive the replace transaction.
    #expect(throws: (any Error).self) {
        try target.debugWrite { db in try db.execute(sql: "DELETE FROM run") }
    }
}

@Test func committedV1FixtureMigratesAndSurvivesReopen() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/v1.sqlite")
    #expect(FileManager.default.fileExists(atPath: fixture.path))
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: destination) }
    try FileManager.default.copyItem(at: fixture, to: destination)
    let store = try RunStore(path: destination.path)
    let legacy = try store.runs()
    #expect(legacy.count == 1)
    #expect(legacy[0].id == "fixture-1")
    #expect(legacy[0].summary != nil)
    try store.append(sampleRun(id: "fresh"))
    let reopened = try RunStore(path: destination.path)
    #expect(try reopened.runs().count == 2)
    #expect(throws: (any Error).self) { try reopened.append(sampleRun(id: "fixture-1")) }
}
