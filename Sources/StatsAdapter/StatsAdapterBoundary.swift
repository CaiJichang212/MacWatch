import MacWatchCore

public struct StatsAdapterBoundary: Equatable, Sendable {
    public let allowedSources: [String]

    public init(allowedSources: [String]) {
        self.allowedSources = allowedSources
    }
}

public extension StatsAdapterBoundary {
    static let placeholder = StatsAdapterBoundary(allowedSources: [])
}
