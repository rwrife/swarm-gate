import Foundation
import GRDB
import SwarmGateKit

public enum RunMode: String, Codable, Sendable { case career, endless }

public struct RunSummary: Codable, Equatable, Sendable {
    public let wave: Int
    public let score: Int
    public let ticks: Int
    public let bossesSlain: Int
}

public struct PersonalBests: Equatable, Sendable {
    public let bestWave: Int?
    public let bestScore: Int?
    public let longestEndlessTicks: Int?
    public let mostBossesSlain: Int?
}

public struct RunRecord: Codable, Equatable, Sendable {
    public var id: String
    public let mode: RunMode
    public let ruleVersion: Int
    public let seed: UInt64
    public let waveInterval: Int
    public var events: [LedgerEvent]
    public let eventCount: Int
    public let fingerprint: UInt64

    fileprivate init(id: String, mode: RunMode, ruleVersion: Int, seed: UInt64, waveInterval: Int, events: [LedgerEvent], eventCount: Int, fingerprint: UInt64) {
        self.id = id
        self.mode = mode
        self.ruleVersion = ruleVersion
        self.seed = seed
        self.waveInterval = waveInterval
        self.events = events
        self.eventCount = eventCount
        self.fingerprint = fingerprint
    }

    public init(id: String, mode: RunMode, ledger: EventLedger, waveInterval: Int) {
        self.id = id
        self.mode = mode
        ruleVersion = ledger.ruleVersion
        seed = ledger.seed
        self.waveInterval = waveInterval
        events = ledger.events
        eventCount = events.count
        fingerprint = Self.hash(ledger.encodedBytes())
    }

    public var summary: RunSummary? {
        guard waveInterval > 0, ruleVersion > 0, eventCount == events.count,
              let last = events.last, last.kind == .end, last.value == 0,
              last.tick >= 0, last.tick < Int.max,
              !events.dropLast().contains(where: { $0.kind == .end }),
              zip(events, events.dropFirst()).allSatisfy({ $0.tick <= $1.tick }),
              fingerprint == Self.hash(canonicalBytes()) else { return nil }
        let bossIDs = Set(events.filter { $0.kind == .bossSpawn }.map(\.id))
        let bosses = events.filter { $0.kind == .kill && bossIDs.contains($0.id) }.count
        return RunSummary(wave: last.tick / waveInterval + 1,
                          score: events.filter { $0.kind == .kill || $0.kind == .bombKill }.count,
                          ticks: last.tick + 1, bossesSlain: bosses)
    }

    private func canonicalBytes() -> [UInt8] {
        var text = "swarm-gate|\(ruleVersion)|\(seed)\n"
        for e in events {
            text += "\(e.tick)|\(e.kind.rawValue)|\(e.id)|\(e.lane)|\(e.distance)|\(e.value)\n"
        }
        return Array(text.utf8)
    }

    private static func hash(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(0xcbf29ce484222325) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }
}

public struct BackupPreview: Equatable, Sendable {
    public let existing: Int
    public let incoming: Int
    public let added: Int
    public let removed: Int
    public let changed: Int
}

public enum StoreError: Error { case invalidBackup, unsupportedVersion, duplicateRun, invalidID }

public final class RunStore {
    private let queue: DatabaseQueue
    private static let encoder: JSONEncoder = {
        let codec = JSONEncoder()
        codec.outputFormatting = [.sortedKeys]
        return codec
    }()
    private static let decoder = JSONDecoder()
    private static let guards = [
        "CREATE TRIGGER run_no_update BEFORE UPDATE ON run BEGIN SELECT RAISE(ABORT, 'append-only run'); END",
        "CREATE TRIGGER run_no_delete BEFORE DELETE ON run BEGIN SELECT RAISE(ABORT, 'append-only run'); END",
        "CREATE TRIGGER event_no_update BEFORE UPDATE ON event BEGIN SELECT RAISE(ABORT, 'append-only event'); END",
        "CREATE TRIGGER event_no_delete BEFORE DELETE ON event BEGIN SELECT RAISE(ABORT, 'append-only event'); END",
    ]

    public init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: "CREATE TABLE run (id TEXT PRIMARY KEY, mode TEXT NOT NULL, rule_version INTEGER NOT NULL, seed TEXT NOT NULL, wave_interval INTEGER NOT NULL, event_count INTEGER NOT NULL, fingerprint TEXT NOT NULL)")
            try db.execute(sql: "CREATE TABLE event (run_id TEXT NOT NULL REFERENCES run(id) ON DELETE RESTRICT, ordinal INTEGER NOT NULL, tick INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (run_id, ordinal))")
            for sql in Self.guards { try db.execute(sql: sql) }
        }
        try migrator.migrate(queue)
    }

    public func append(_ run: RunRecord) throws {
        guard !run.id.isEmpty else { throw StoreError.invalidID }
        guard Self.validMetadata(run) else { throw StoreError.invalidBackup }
        try queue.write { db in try Self.insert(run, into: db) }
    }

    private static func insert(_ run: RunRecord, into db: Database) throws {
        try db.execute(sql: "INSERT INTO run VALUES (?, ?, ?, ?, ?, ?, ?)", arguments: [run.id, run.mode.rawValue, run.ruleVersion, String(run.seed), run.waveInterval, run.eventCount, String(run.fingerprint)])
        for (index, event) in run.events.enumerated() {
            try db.execute(sql: "INSERT INTO event VALUES (?, ?, ?, ?)", arguments: [run.id, index, event.tick, try encoder.encode(event)])
        }
    }

    public func runs() throws -> [RunRecord] {
        try queue.read { db in try Self.fetch(db) }
    }

    private static func fetch(_ db: Database) throws -> [RunRecord] {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM run ORDER BY id")
        return try rows.map { row in
            let id: String = row["id"]
            let modeText: String = row["mode"]
            let seedText: String = row["seed"]
            let hashText: String = row["fingerprint"]
            guard let mode = RunMode(rawValue: modeText), let seed = UInt64(seedText),
                  let fingerprint = UInt64(hashText) else { throw StoreError.invalidBackup }
            let eventRows = try Row.fetchAll(db, sql: "SELECT ordinal, tick, payload FROM event WHERE run_id = ? ORDER BY ordinal", arguments: [id])
            let events = try eventRows.enumerated().map { index, eventRow -> LedgerEvent in
                let ordinal: Int = eventRow["ordinal"]
                let tick: Int = eventRow["tick"]
                let payload: Data = eventRow["payload"]
                let event = try decoder.decode(LedgerEvent.self, from: payload)
                guard ordinal == index, tick == event.tick else { throw StoreError.invalidBackup }
                return event
            }
            let run = RunRecord(id: id, mode: mode, ruleVersion: row["rule_version"],
                             seed: seed, waveInterval: row["wave_interval"],
                             events: events, eventCount: row["event_count"], fingerprint: fingerprint)
            return run
        }
    }

    public func personalBests() throws -> PersonalBests {
        let completed = try runs().compactMap { run -> (RunMode, RunSummary)? in
            run.summary.map { (run.mode, $0) }
        }
        return PersonalBests(bestWave: completed.map(\.1.wave).max(),
                             bestScore: completed.map(\.1.score).max(),
                             longestEndlessTicks: completed.filter { $0.0 == .endless }.map(\.1.ticks).max(),
                             mostBossesSlain: completed.map(\.1.bossesSlain).max())
    }

    private struct Backup: Codable { let version: Int; let runs: [RunRecord] }

    public func backup() throws -> Data {
        try queue.read { db in try Self.encoder.encode(Backup(version: 1, runs: Self.fetch(db))) }
    }

    private static func validated(_ data: Data) throws -> [RunRecord] {
        let backup = try decodeBackup(data)
        guard backup.version == 1 else { throw StoreError.unsupportedVersion }
        guard Set(backup.runs.map(\.id)).count == backup.runs.count,
              backup.runs.allSatisfy(validMetadata) else {
            throw StoreError.invalidBackup
        }
        return backup.runs
    }

    private static func validMetadata(_ run: RunRecord) -> Bool {
        !run.id.isEmpty && run.id.utf8.count <= 256 && run.ruleVersion > 0 && run.waveInterval > 0
            && run.eventCount >= run.events.count && run.events.count <= 100_000
            && run.events.allSatisfy { $0.tick >= 0 && $0.tick < Int.max }
    }

    private static func decodeBackup(_ data: Data) throws -> Backup {
        guard data.count <= 32 * 1_024 * 1_024 else { throw StoreError.invalidBackup }
        return try decoder.decode(Backup.self, from: data)
    }

    public func previewRestore(_ data: Data) throws -> BackupPreview {
        let incoming = try Self.validated(data)
        let old = Dictionary(uniqueKeysWithValues: try runs().map { ($0.id, $0) })
        let fresh = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        return BackupPreview(existing: old.count, incoming: fresh.count,
                             added: fresh.keys.filter { old[$0] == nil }.count,
                             removed: old.keys.filter { fresh[$0] == nil }.count,
                             changed: fresh.filter { old[$0.key] != nil && old[$0.key] != $0.value }.count)
    }

    public func restoreReplacingAll(_ data: Data) throws {
        let incoming = try Self.validated(data)
        try queue.write { db in
            // ponytail: Replace-only restore; no merge UI until conflicts have product semantics.
            try db.execute(sql: "DROP TRIGGER event_no_delete")
            try db.execute(sql: "DROP TRIGGER run_no_delete")
            try db.execute(sql: "DELETE FROM event")
            try db.execute(sql: "DELETE FROM run")
            for run in incoming { try Self.insert(run, into: db) }
            try db.execute(sql: Self.guards[1])
            try db.execute(sql: Self.guards[3])
        }
    }

    func debugWrite(_ body: (Database) throws -> Void) throws {
        try queue.write { db in try body(db) }
    }

    public func csv() throws -> String {
        var lines = ["id,mode,rule_version,seed,status,wave,score,ticks,bosses_slain"]
        for run in try runs() {
            // CSV fields are quoted even for numeric text; IDs may include commas/quotes/newlines.
            let values = [run.id, run.mode.rawValue, String(run.ruleVersion), String(run.seed),
                          run.summary == nil ? "unknown" : "complete", run.summary.map { String($0.wave) } ?? "",
                          run.summary.map { String($0.score) } ?? "", run.summary.map { String($0.ticks) } ?? "",
                          run.summary.map { String($0.bossesSlain) } ?? ""]
            lines.append(values.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
