/// A stable seed value for the fixed-tick simulation.
public struct RunSeed: Equatable, Sendable {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }
}