// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacWatch",
    platforms: [
        .macOS(.v13),
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
            name: "MacWatchCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "StatsAdapter",
            dependencies: [
                "MacWatchCore",
                "StatsAdapterIOHID",
            ]
        ),
        .target(
            name: "StatsAdapterIOHID",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
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
        .testTarget(
            name: "MacWatchAppTests",
            dependencies: [
                "MacWatchApp",
            ]
        ),
    ]
)
