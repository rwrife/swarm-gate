/// A stable seed value for a future fixed-tick simulation.
/// Gameplay and pickup decisions are not implemented in this scaffold.
public struct RunSeed: Equatable, Sendable {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }
}