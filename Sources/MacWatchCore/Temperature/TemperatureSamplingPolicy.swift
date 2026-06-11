import Foundation

public struct TemperatureSamplingPolicy: Sendable, Equatable {
    public let realtimeInterval: TimeInterval
    public let historyInterval: TimeInterval
    public let minimumInterval: TimeInterval
    public let staleMultiplier: Double

    public init(
        realtimeInterval: TimeInterval,
        historyInterval: TimeInterval,
        minimumInterval: TimeInterval,
        staleMultiplier: Double = 2.5
    ) {
        self.realtimeInterval = max(realtimeInterval, minimumInterval)
        self.historyInterval = max(historyInterval, minimumInterval)
        self.minimumInterval = minimumInterval
        self.staleMultiplier = staleMultiplier
    }

    public static func `default`(for domain: TemperatureDomain, userRealtimeInterval: TimeInterval? = nil) -> Self {
        let rawPolicy: TemperatureSamplingPolicy
        switch domain {
        case .cpu, .gpu:
            rawPolicy = TemperatureSamplingPolicy(
                realtimeInterval: 5,
                historyInterval: 10,
                minimumInterval: 5
            )
        case .ssd, .battery:
            rawPolicy = TemperatureSamplingPolicy(
                realtimeInterval: 30,
                historyInterval: 60,
                minimumInterval: 30
            )
        case .system, .sensor:
            rawPolicy = TemperatureSamplingPolicy(
                realtimeInterval: 10,
                historyInterval: 30,
                minimumInterval: 10
            )
        }

        guard let userRealtimeInterval else {
            return rawPolicy
        }
        let clampedRealtime = max(userRealtimeInterval, rawPolicy.minimumInterval)
        let clampedHistory = max(rawPolicy.historyInterval, clampedRealtime * 2)
        return TemperatureSamplingPolicy(
            realtimeInterval: clampedRealtime,
            historyInterval: clampedHistory,
            minimumInterval: rawPolicy.minimumInterval,
            staleMultiplier: rawPolicy.staleMultiplier
        )
    }
}
