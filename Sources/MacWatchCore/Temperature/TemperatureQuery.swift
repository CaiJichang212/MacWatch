import Foundation

public struct TemperatureQuery: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let domains: [TemperatureDomain]
    public let metricNames: [String]?
    public let start: Date
    public let end: Date
    public let maxPoints: Int

    public init(
        sessionID: UUID,
        domains: [TemperatureDomain],
        metricNames: [String]?,
        start: Date,
        end: Date,
        maxPoints: Int
    ) throws {
        guard start <= end, maxPoints > 0 else {
            throw TemperatureModelError.invalidQuery
        }

        self.sessionID = sessionID
        self.domains = domains
        self.metricNames = metricNames
        self.start = start
        self.end = end
        self.maxPoints = maxPoints
    }
}
