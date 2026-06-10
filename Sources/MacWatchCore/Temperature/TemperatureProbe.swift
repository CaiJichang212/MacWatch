import Foundation

public protocol TemperatureProbe: Sendable {
    var domain: TemperatureDomain { get }
    var source: TemperatureSource { get }
    var defaultMetricName: String { get }

    func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability
    func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample]
}
