// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwarmGateStore",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "SwarmGateStore", targets: ["SwarmGateStore"])],
    dependencies: [
        .package(path: "../SwarmGateKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "SwarmGateStore", dependencies: ["SwarmGateKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "SwarmGateStoreTests", dependencies: ["SwarmGateStore", .product(name: "GRDB", package: "GRDB.swift")],
                    exclude: ["Fixtures"]),
    ]
)