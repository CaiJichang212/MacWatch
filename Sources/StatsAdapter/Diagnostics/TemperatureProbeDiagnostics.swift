import Foundation
import MacWatchCore

public struct TemperatureProbeDiagnosticRecord: Codable, Sendable {
    public let domain: String
    public let metricName: String
    public let quality: String
    public let valueCelsius: Double?
    public let source: String
    public let rawKey: String?
    public let errorCode: String?
    public let attributes: [String: String]
}

public enum TemperatureProbeDiagnostics {
    public static func readOnceJSONLines(
        sessionID: UUID = UUID(),
        timestamp: Date = Date()
    ) -> String {
        let probes = StatsTemperatureProbeFactory().makeDefaultProbes()
        let semaphore = DispatchSemaphore(value: 0)
        var lines: [String] = []

        Task {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]

            for probe in probes {
                let samples = await probe.read(sessionID: sessionID, at: timestamp)
                let resolvedSamples = samples.isEmpty
                    ? [fallbackSample(for: probe, sessionID: sessionID, timestamp: timestamp)]
                    : samples

                for sample in resolvedSamples {
                    let record = TemperatureProbeDiagnosticRecord(
                        domain: sample.domain.rawValue,
                        metricName: sample.metricName,
                        quality: sample.quality.rawValue,
                        valueCelsius: sample.valueCelsius,
                        source: sample.source.rawValue,
                        rawKey: sample.rawKey,
                        errorCode: sample.errorCode,
                        attributes: sample.attributes
                    )
                    if let data = try? encoder.encode(record),
                       let line = String(data: data, encoding: .utf8) {
                        lines.append(line)
                    }
                }
            }

            semaphore.signal()
        }

        semaphore.wait()
        return lines.joined(separator: "\n")
    }

    private static func fallbackSample(
        for probe: any TemperatureProbe,
        sessionID: UUID,
        timestamp: Date
    ) -> TemperatureSample {
        try! TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: probe.defaultMetricName,
            domain: probe.domain,
            deviceID: "\(probe.domain.rawValue)-device",
            displayName: probe.defaultMetricName,
            quality: .readFailed,
            source: probe.source,
            errorCode: "probeReturnedNoSamples",
            attributes: ["sourcePriority": probe.source.rawValue]
        )
    }
}
