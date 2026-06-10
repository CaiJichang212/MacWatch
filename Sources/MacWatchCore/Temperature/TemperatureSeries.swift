public struct TemperatureSeries: Codable, Equatable, Sendable {
    public let metricName: String
    public let domain: TemperatureDomain
    public let samples: [TemperatureSample]
    public let gaps: [TimelineEvent]

    public init(
        metricName: String,
        domain: TemperatureDomain,
        samples: [TemperatureSample],
        gaps: [TimelineEvent]
    ) {
        self.metricName = metricName
        self.domain = domain
        self.samples = samples
        self.gaps = gaps
    }
}
