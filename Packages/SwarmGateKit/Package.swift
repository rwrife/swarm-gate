// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwarmGateKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "SwarmGateKit", targets: ["SwarmGateKit"])],
    targets: [
        .target(name: "SwarmGateKit"),
        .testTarget(name: "SwarmGateKitTests", dependencies: ["SwarmGateKit"]),
    ]
)