import Foundation

public struct TemperatureSeriesStatistics: Codable, Equatable, Sendable {
    public let validSampleCount: Int
    public let maximumCelsius: Double?
    public let minimumCelsius: Double?
    public let averageCelsius: Double?
    public let peakAt: Date?

    public init(
        validSampleCount: Int,
        maximumCelsius: Double?,
        minimumCelsius: Double?,
        averageCelsius: Double?,
        peakAt: Date?
    ) {
        self.validSampleCount = validSampleCount
        self.maximumCelsius = maximumCelsius
        self.minimumCelsius = minimumCelsius
        self.averageCelsius = averageCelsius
        self.peakAt = peakAt
    }

    public static let empty = TemperatureSeriesStatistics(
        validSampleCount: 0,
        maximumCelsius: nil,
        minimumCelsius: nil,
        averageCelsius: nil,
        peakAt: nil
    )

    public static func compute(samples: [TemperatureSample]) -> TemperatureSeriesStatistics {
        let validSamples = samples.filter { sample in
            sample.quality == .valid && sample.valueCelsius != nil
        }

        guard validSamples.isEmpty == false else {
            return .empty
        }

        let sortedByValue = validSamples.sorted { lhs, rhs in
            let lhsValue = lhs.valueCelsius ?? -.infinity
            let rhsValue = rhs.valueCelsius ?? -.infinity
            if lhsValue == rhsValue {
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.timestamp < rhs.timestamp
            }
            return lhsValue < rhsValue
        }

        let maximum = sortedByValue.last?.valueCelsius
        let minimum = sortedByValue.first?.valueCelsius
        let total = validSamples.reduce(0.0) { partial, sample in
            partial + (sample.valueCelsius ?? 0)
        }
        let peakAt = validSamples
            .filter { $0.valueCelsius == maximum }
            .min { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.timestamp < rhs.timestamp
            }?
            .timestamp

        return TemperatureSeriesStatistics(
            validSampleCount: validSamples.count,
            maximumCelsius: maximum,
            minimumCelsius: minimum,
            averageCelsius: total / Double(validSamples.count),
            peakAt: peakAt
        )
    }
}
