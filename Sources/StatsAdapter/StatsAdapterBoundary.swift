public struct StatsAdapterBoundary: Equatable, Sendable {
    public let allowedSources: [StatsReadOnlySource]
    public let prohibitedCapabilities: [String]

    public init(
        allowedSources: [StatsReadOnlySource],
        prohibitedCapabilities: [String]
    ) {
        self.allowedSources = allowedSources
        self.prohibitedCapabilities = prohibitedCapabilities
    }
}

public extension StatsAdapterBoundary {
    static let stageOne = StatsAdapterBoundary(
        allowedSources: StatsReadOnlySource.allCases,
        prohibitedCapabilities: [
            "Stats.Reader",
            "Stats.Module lifecycle",
            "Stats.DB.shared",
            "LevelDB",
            "Remote",
            "MQTT",
            "OAuth",
            "Updater",
            "Notifications",
            "LaunchAtLogin helper",
            "SMC privileged helper",
            "SMC write operations",
        ]
    )
}
