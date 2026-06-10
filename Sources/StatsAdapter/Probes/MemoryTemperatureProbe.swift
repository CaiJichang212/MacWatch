import Foundation
import MacWatchCore

public struct MemoryTemperatureProbe: TemperatureProbe {
    public let id: String = "memory.proximity.primary"
    public let domain: TemperatureDomain = .memory
    public let source: TemperatureSource = .smc
    public let defaultMetricName: String = TemperatureMetricName.memoryProximity

    private let platformDetector: any ApplePlatformDetecting
    private let smcReader: any SMCValueReading
    private let catalog: AppleSiliconSensorCatalog

    public init(
        platformDetector: any ApplePlatformDetecting = ApplePlatformDetector(),
        smcReader: any SMCValueReading = SMCReadOnlyClient(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.platformDetector = platformDetector
        self.smcReader = smcReader
        self.catalog = catalog
    }

    public func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        let sample = await read(sessionID: sessionID, at: timestamp).first
        return TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .memory,
            source: .smc,
            supported: true,
            readable: sample?.quality == .valid,
            reasonCode: sample?.quality == .valid ? "ok" : "readFailed",
            reasonMessage: sample?.quality.rawValue ?? "readFailed",
            rawKey: sample?.rawKey,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    public func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        let platform = platformDetector.detect() ?? .intel
        let readings = catalog.smcMemoryKeys(for: platform).compactMap { rawKey -> (String, Double)? in
            guard let value = smcReader.getValue(rawKey), value.isNaN == false, value >= 0, value < 110 else {
                return nil
            }
            return (rawKey, value)
        }

        guard let hottest = readings.max(by: { $0.1 < $1.1 }) else {
            let attemptedRawKeys = catalog.smcMemoryKeys(for: platform)
            return [
                try! TemperatureSample.makeInvalid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.memoryProximity,
                    domain: .memory,
                    deviceID: "memory-package",
                    displayName: "Memory Proximity",
                    quality: .readFailed,
                    source: .smc,
                    errorCode: "temperatureUnavailable",
                    attributes: [
                        "attemptedRawKeys": attemptedRawKeys.joined(separator: ","),
                        "readerError": "temperatureUnavailable",
                        "sourcePriority": TemperatureSource.smc.rawValue,
                    ]
                )
            ]
        }

        return [
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.memoryProximity,
                domain: .memory,
                deviceID: "memory-package",
                displayName: "Memory Proximity",
                valueCelsius: hottest.1,
                source: .smc,
                rawKey: hottest.0,
                attributes: ["rawKeys": readings.map(\.0).joined(separator: ",")]
            )
        ]
    }
}
