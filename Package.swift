// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacWatch",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "MacWatchApp", targets: ["MacWatchApp"]),
        .library(name: "MacWatchCore", targets: ["MacWatchCore"]),
        .library(name: "StatsAdapter", targets: ["StatsAdapter"]),
    ],
    targets: [
        .executableTarget(
            name: "MacWatchApp",
            dependencies: [
                "MacWatchCore",
                "StatsAdapter",
            ]
        ),
        .target(
            name: "MacWatchCore"
        ),
        .target(
            name: "StatsAdapter",
            dependencies: [
                "MacWatchCore",
            ]
        ),
        .testTarget(
            name: "MacWatchCoreTests",
            dependencies: [
                "MacWatchCore",
            ]
        ),
        .testTarget(
            name: "StatsAdapterTests",
            dependencies: [
                "StatsAdapter",
            ]
        ),
    ]
)
