import Foundation

public struct LiveTemperatureState: Equatable, Sendable {
    public let sessionID: UUID
    public let updatedAt: Date?
    public let samplesByMetricName: [String: TemperatureSample]
    public let capabilitiesByDomain: [TemperatureDomain: TemperatureCapability]
    public let hottestValidSample: TemperatureSample?

    public init(
        sessionID: UUID,
        updatedAt: Date?,
        samplesByMetricName: [String: TemperatureSample],
        capabilitiesByDomain: [TemperatureDomain: TemperatureCapability],
        hottestValidSample: TemperatureSample?
    ) {
        self.sessionID = sessionID
        self.updatedAt = updatedAt
        self.samplesByMetricName = samplesByMetricName
        self.capabilitiesByDomain = capabilitiesByDomain
        self.hottestValidSample = hottestValidSample
    }
}
