/// Pickups descend with the horde and become decidable once they sit in the
/// gate zone. The fairness contract lives here: an effect is applied ONLY on
/// the accept path. Spawning, descending, expiring, and ignoring never touch
/// firepower, ammo, or bomb inventory.
public enum PickupKind: Int, Equatable, Sendable, CaseIterable {
    case buff = 0
    case weapon = 1
    case bomb = 2
    case powerDown = 3

    /// Seeded 0..<100 roll to kind. Power-downs are deliberately tempting
    /// bait placed near dense clusters; fairness comes from accept-only
    /// application, not from spawn frequency.
    init(roll: Int) {
        switch roll {
        case 0..<40: self = .buff
        case 40..<65: self = .weapon
        case 65..<85: self = .bomb
        default: self = .powerDown
        }
    }
}

/// Rendered-agnostic pickup state. `zoneTicksLeft` is strictly positive
/// exactly while the pickup is decidable in the gate zone; the countdown to
/// expiry is the only decay rule that consumes an untouched pickup.
public struct Pickup: Equatable, Sendable {
    public let id: Int
    public let kind: PickupKind
    public var lane: Int
    public var distance: Int
    public let speed: Int
    public var zoneTicksLeft: Int

    public var inZone: Bool { zoneTicksLeft > 0 }

    init(id: Int, kind: PickupKind, lane: Int, distance: Int, speed: Int) {
        self.id = id
        self.kind = kind
        self.lane = lane
        self.distance = distance
        self.speed = speed
        self.zoneTicksLeft = 0
    }
}
