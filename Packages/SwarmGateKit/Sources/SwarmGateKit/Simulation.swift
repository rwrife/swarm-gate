/// SplitMix64 uses explicitly wrapping UInt64 arithmetic on every platform.
public struct SplitMix64: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}

/// Integer distances are in simulation units; time is measured only in ticks.
/// Freeze a table and its version when sharing a run. Each wave adds one column,
/// one zombie per column, and one speed unit, up to the configured caps.
public struct RuleTable: Equatable, Sendable {
    public var version: Int = 1
    public var laneCount: Int = 5
    public var spawnDistance: Int = 120
    public var convergenceRadius: Int = 24
    public var playerHealth: Int = 100
    public var zombieHealth: Int = 2
    public var bossHealth: Int = 40
    public var biteDamage: Int = 10
    public var shotDamage: Int = 2
    public var waveInterval: Int = 30
    public var initialColumns: Int = 1
    public var maximumColumns: Int = 5
    public var initialDepth: Int = 1
    public var maximumDepth: Int = 6
    public var initialSpeed: Int = 1
    public var maximumSpeed: Int = 4
    public var bossEveryWaves: Int = 5
    /// 0 disables pickups entirely, byte-preserving pre-M2b replays. Otherwise
    /// one pickup is placed on every `pickupEveryWaves`-th wave.
    public var pickupEveryWaves: Int = 0
    /// Ticks a pickup stays decidable once it reaches the gate zone.
    public var pickupZoneTicks: Int = 3
    public var maximumFirepower: Int = 4
    public var maximumWeaponAmmo: Int = 12
    public var weaponGrantAmmo: Int = 6
    public var maximumBombs: Int = 3
    /// Zombies at or inside this distance are inside the lane segment a bomb clears.
    public var bombReach: Int = 45
    /// Buffs are temporary: firepower drops one step on this cadence, floor 1.
    public var firepowerDecayTicks: Int = 45

    public init(version: Int = 1, laneCount: Int = 5, spawnDistance: Int = 120,
                convergenceRadius: Int = 24, playerHealth: Int = 100,
                zombieHealth: Int = 2, bossHealth: Int = 40, biteDamage: Int = 10,
                shotDamage: Int = 2, waveInterval: Int = 30, initialColumns: Int = 1,
                maximumColumns: Int = 5, initialDepth: Int = 1, maximumDepth: Int = 6,
                initialSpeed: Int = 1, maximumSpeed: Int = 4, bossEveryWaves: Int = 5) {
        self.version = version
        self.laneCount = laneCount
        self.spawnDistance = spawnDistance
        self.convergenceRadius = convergenceRadius
        self.playerHealth = playerHealth
        self.zombieHealth = zombieHealth
        self.bossHealth = bossHealth
        self.biteDamage = biteDamage
        self.shotDamage = shotDamage
        self.waveInterval = waveInterval
        self.initialColumns = initialColumns
        self.maximumColumns = maximumColumns
        self.initialDepth = initialDepth
        self.maximumDepth = maximumDepth
        self.initialSpeed = initialSpeed
        self.maximumSpeed = maximumSpeed
        self.bossEveryWaves = bossEveryWaves
    }

    public static let v1 = RuleTable()
    public static let v2: RuleTable = {
        var rules = RuleTable(version: 2)
        rules.pickupEveryWaves = 1
        return rules
    }()

    /// Playable 10 Hz cadence. Freeze with the input script for exact replay.
    public static let v3: RuleTable = {
        var rules = RuleTable.v2
        rules.version = 3
        rules.waveInterval = 60
        rules.spawnDistance = 180
        rules.pickupZoneTicks = 30
        rules.firepowerDecayTicks = 150
        return rules
    }()

    fileprivate func validateEconomy() {
        precondition(pickupEveryWaves >= 0 && pickupZoneTicks > 0)
        precondition(shotDamage <= Int.max / 2)
        precondition(maximumFirepower >= 1 && maximumFirepower <= Int.max / (shotDamage * 2))
        precondition(maximumWeaponAmmo > 0 && weaponGrantAmmo > 0 && maximumBombs > 0)
        precondition(bombReach >= 0 && firepowerDecayTicks > 0)
    }

    fileprivate func validate() {
        precondition(version > 0 && laneCount > 0 && spawnDistance > 0)
        precondition(convergenceRadius >= 0 && playerHealth > 0 && zombieHealth > 0)
        precondition(bossHealth > zombieHealth && biteDamage > 0 && shotDamage > 0)
        precondition(waveInterval > 0 && bossEveryWaves > 0)
        precondition(initialColumns > 0 && maximumColumns >= initialColumns && maximumColumns <= laneCount)
        precondition(initialDepth > 0 && maximumDepth >= initialDepth)
        precondition(initialSpeed > 0 && maximumSpeed >= initialSpeed)
        precondition(spawnDistance <= Int.max - maximumDepth)
        validateEconomy()
    }
}

public enum InputAction: Equatable, Sendable {
    case move(lane: Int)
    case fire
    case acceptPickup(id: Int)
    case ignorePickup(id: Int)
    case bomb
}

public struct TickInput: Equatable, Sendable {
    public let tick: Int
    public let action: InputAction
    public init(tick: Int, action: InputAction) {
        precondition(tick >= 0)
        self.tick = tick
        self.action = action
    }
}

/// Capture order is preserved for inputs on the same tick, even when captured
/// out of tick order. Simulation takes an immutable snapshot of this script.
public struct InputScript: Equatable, Sendable {
    public private(set) var events: [TickInput]
    public init(events: [TickInput] = []) { self.events = events }
    public mutating func capture(tick: Int, action: InputAction) {
        events.append(TickInput(tick: tick, action: action))
    }
}

public struct Zombie: Equatable, Sendable {
    public let id: Int
    public var lane: Int
    public var distance: Int
    public var health: Int
    public let speed: Int
    public let isBoss: Bool
}

public struct LedgerEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case input, spawn, bossSpawn, hit, kill, bite, end
        case pickupSpawn, pickupReady, pickupAccept, pickupIgnore, pickupExpire
        case buffDecay, bomb, bombKill
    }
    public let tick: Int
    public let kind: Kind
    public let id: Int
    public let lane: Int
    public let distance: Int
    public let value: Int
}

public struct EventLedger: Equatable, Sendable {
    public let ruleVersion: Int
    public let seed: UInt64
    public fileprivate(set) var events: [LedgerEvent] = []

    /// Canonical v1 UTF-8 format: header then ordered integer event rows.
    /// No locale, wall clock, dictionaries, floating point, or native byte order.
    public func encodedBytes() -> [UInt8] {
        var text = "swarm-gate|\(ruleVersion)|\(seed)\n"
        for event in events {
            text += "\(event.tick)|\(event.kind.rawValue)|\(event.id)|\(event.lane)|\(event.distance)|\(event.value)\n"
        }
        return Array(text.utf8)
    }
}

/// Call step once per fixed tick. Rendering and elapsed time never enter the engine.
/// Tick order: inputs, wave spawn (plus seeded pickup drop), steering (using
/// pre-move distance), advance, bites, pickup descent/decay. A zombie bites once
/// on arrival, regardless of lane, then is removed.
///
/// Fairness invariant: only explicit accept grants a pickup effect. Spawn,
/// descent, expiry, and ignore cannot grant buffs, weapons, bombs or penalties.
/// Buffs decay to base 1; firing spends ammo and a bomb action spends inventory.
public struct Simulation: Sendable {
    public let rules: RuleTable
    /// Inputs captured at init plus everything queued live. Appending only ever
    /// adds rows at the current or a later tick, so a replay of the same seed,
    /// rules and captured script reproduces the ledger byte for byte.
    public private(set) var inputs: InputScript
    public private(set) var tick = 0
    public private(set) var playerLane: Int
    public private(set) var health: Int
    public private(set) var zombies: [Zombie] = []
    public private(set) var pickups: [Pickup] = []
    public private(set) var firepower = 1
    public private(set) var weaponAmmo = 0
    public private(set) var bombs = 0
    public private(set) var ledger: EventLedger
    public var isEnded: Bool { health == 0 }
    private var random: SplitMix64
    private var nextID = 0
    private var nextPickupID = 0

    public init(seed: RunSeed, rules: RuleTable = .v1, inputs: InputScript = InputScript()) {
        rules.validate()
        self.rules = rules
        self.inputs = inputs
        playerLane = rules.laneCount / 2
        health = rules.playerHealth
        ledger = EventLedger(ruleVersion: rules.version, seed: seed.value)
        random = SplitMix64(seed: seed.value)
    }

    /// Capture intent, never mutate game state between ticks. Terminal input is ignored.
    public mutating func queue(_ action: InputAction) {
        guard !isEnded else { return }
        inputs.capture(tick: tick, action: action)
    }

    public mutating func advance(ticks: Int) {
        precondition(ticks >= 0)
        for _ in 0..<ticks {
            if isEnded { break }
            step()
        }
    }

    public mutating func step() {
        guard !isEnded else { return }
        for input in inputs.events where input.tick == tick {
            switch input.action {
            case .move(let lane):
                playerLane = max(0, min(rules.laneCount - 1, lane))
                record(.input, value: lane)
            case .fire:
                record(.input)
                fire()
            case .acceptPickup(let id):
                record(.input, value: id)
                acceptPickup(id: id)
            case .ignorePickup(let id):
                record(.input, value: id)
                ignorePickup(id: id)
            case .bomb:
                record(.input)
                triggerBomb()
            }
        }
        if tick % rules.waveInterval == 0 { spawnWave() }
        var survivors: [Zombie] = []
        for var zombie in zombies {
            if zombie.distance <= rules.convergenceRadius {
                if zombie.lane < playerLane { zombie.lane += 1 }
                if zombie.lane > playerLane { zombie.lane -= 1 }
            }
            zombie.distance = max(0, zombie.distance - zombie.speed)
            if zombie.distance == 0 {
                health = max(0, health - rules.biteDamage)
                record(.bite, zombie: zombie, value: health)
                if isEnded {
                    record(.end, value: 0)
                    break
                }
            } else {
                survivors.append(zombie)
            }
        }
        zombies = survivors
        if !isEnded {
            advancePickups()
            decayBuffsIfNeeded()
        }
        tick += 1
    }

    private mutating func spawnWave() {
        let index = tick / rules.waveInterval
        let columns = rules.initialColumns + min(index, rules.maximumColumns - rules.initialColumns)
        let depth = rules.initialDepth + min(index, rules.maximumDepth - rules.initialDepth)
        let speed = rules.initialSpeed + min(index, rules.maximumSpeed - rules.initialSpeed)
        let startLane = Int(random.next() % UInt64(rules.laneCount))
        for column in 0..<columns {
            // Avoid overflow while wrapping adjacent distinct lanes.
            let lane = column >= rules.laneCount - startLane
                ? column - (rules.laneCount - startLane) : startLane + column
            for row in 0..<depth {
                spawn(lane: lane, distance: rules.spawnDistance + row, speed: speed, boss: false)
            }
        }
        if index % rules.bossEveryWaves == rules.bossEveryWaves - 1 {
            let lane = Int(random.next() % UInt64(rules.laneCount))
            spawn(lane: lane, distance: rules.spawnDistance, speed: speed, boss: true)
        }
        spawnPickupIfNeeded(waveIndex: index, speed: speed, clusterLane: startLane)
    }

    private mutating func spawn(lane: Int, distance: Int, speed: Int, boss: Bool) {
        let zombie = Zombie(id: nextID, lane: lane, distance: distance,
                            health: boss ? rules.bossHealth : rules.zombieHealth,
                            speed: speed, isBoss: boss)
        nextID += 1
        zombies.append(zombie)
        record(boss ? .bossSpawn : .spawn, zombie: zombie, value: zombie.health)
    }

    /// Seeded drop drawn after the wave's zombie lanes so existing v1 replays
    /// (pickupEveryWaves == 0) consume zero extra randomness and stay byte-stable.
    /// Power-downs are deliberately placed at the front of the densest fresh
    /// column so the bait is tempting; the fairness guarantee is that nothing
    /// applies until an explicit accept.
    private mutating func spawnPickupIfNeeded(waveIndex: Int, speed: Int, clusterLane: Int) {
        guard rules.pickupEveryWaves > 0, waveIndex % rules.pickupEveryWaves == 0 else { return }
        let kind = PickupKind(roll: Int(random.next() % 100))
        let lane: Int
        if kind == .powerDown {
            lane = clusterLane
        } else {
            lane = Int(random.next() % UInt64(rules.laneCount))
        }
        let pickup = Pickup(id: nextPickupID, kind: kind, lane: lane,
                            distance: rules.spawnDistance, speed: speed)
        nextPickupID += 1
        pickups.append(pickup)
        recordPickup(.pickupSpawn, pickup: pickup, value: kind.rawValue)
    }

    private mutating func advancePickups() {
        var survivors: [Pickup] = []
        for var pickup in pickups {
            if pickup.distance == 0 {
                // Already in zone: count down.
                pickup.zoneTicksLeft -= 1
                if pickup.zoneTicksLeft <= 0 {
                    recordPickup(.pickupExpire, pickup: pickup, value: pickup.kind.rawValue)
                    continue
                }
                survivors.append(pickup)
            } else {
                pickup.distance = max(0, pickup.distance - pickup.speed)
                if pickup.distance == 0 {
                    pickup.zoneTicksLeft = rules.pickupZoneTicks
                    recordPickup(.pickupReady, pickup: pickup, value: pickup.kind.rawValue)
                }
                survivors.append(pickup)
            }
        }
        pickups = survivors
    }

    private mutating func decayBuffsIfNeeded() {
        guard rules.firepowerDecayTicks > 0 else { return }
        if tick > 0 && tick % rules.firepowerDecayTicks == 0 {
            if firepower > 1 {
                firepower -= 1
                record(.buffDecay, value: firepower)
            }
        }
    }

    private mutating func acceptPickup(id: Int) {
        guard let index = pickups.firstIndex(where: { $0.id == id && $0.inZone }) else { return }
        let pickup = pickups.remove(at: index)
        switch pickup.kind {
        case .buff:
            firepower = min(rules.maximumFirepower, firepower + 1)
        case .weapon:
            weaponAmmo += min(rules.weaponGrantAmmo, rules.maximumWeaponAmmo - weaponAmmo)
        case .bomb:
            bombs = min(rules.maximumBombs, bombs + 1)
        case .powerDown:
            // Explicit opt-in penalty: reset stacked buffs and drain ammo.
            firepower = 1
            weaponAmmo = 0
        }
        recordPickup(.pickupAccept, pickup: pickup, value: pickup.kind.rawValue)
    }

    private mutating func ignorePickup(id: Int) {
        guard let index = pickups.firstIndex(where: { $0.id == id && $0.inZone }) else { return }
        let pickup = pickups.remove(at: index)
        recordPickup(.pickupIgnore, pickup: pickup, value: pickup.kind.rawValue)
    }

    private mutating func triggerBomb() {
        guard bombs > 0 else { return }
        bombs -= 1
        record(.bomb, value: bombs)
        var survivors: [Zombie] = []
        for zombie in zombies {
            if zombie.lane == playerLane && zombie.distance <= rules.bombReach {
                record(.bombKill, zombie: zombie)
            } else {
                survivors.append(zombie)
            }
        }
        zombies = survivors
    }

    private mutating func fire() {
        // Nearest in the player lane; stable spawn order breaks distance ties.
        guard let index = zombies.indices.filter({ zombies[$0].lane == playerLane }).min(by: {
            zombies[$0].distance < zombies[$1].distance
        }) else { return }
        let damage: Int
        if weaponAmmo > 0 {
            weaponAmmo -= 1
            damage = rules.shotDamage * 2 * firepower
        } else {
            damage = rules.shotDamage * firepower
        }
        zombies[index].health = max(0, zombies[index].health - damage)
        let zombie = zombies[index]
        record(.hit, zombie: zombie, value: zombie.health)
        if zombie.health == 0 {
            record(.kill, zombie: zombie)
            zombies.remove(at: index)
        }
    }

    private mutating func record(_ kind: LedgerEvent.Kind, zombie: Zombie? = nil, value: Int = 0) {
        ledger.events.append(LedgerEvent(tick: tick, kind: kind, id: zombie?.id ?? -1,
                                        lane: zombie?.lane ?? playerLane,
                                        distance: zombie?.distance ?? 0, value: value))
    }

    private mutating func recordPickup(_ kind: LedgerEvent.Kind, pickup: Pickup, value: Int) {
        ledger.events.append(LedgerEvent(tick: tick, kind: kind, id: pickup.id,
                                        lane: pickup.lane, distance: pickup.distance,
                                        value: value))
    }
}
