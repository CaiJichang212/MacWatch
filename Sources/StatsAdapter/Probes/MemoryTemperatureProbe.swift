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
        guard platformDetector.detect() != nil else {
            return TemperatureCapability(
                id: UUID(),
                sessionID: sessionID,
                domain: .memory,
                source: .smc,
                supported: false,
                readable: false,
                reasonCode: "platformUnsupported",
                reasonMessage: "Memory temperature sensor keys are unavailable for this platform.",
                rawKey: nil,
                detectedAt: timestamp,
                updatedAt: timestamp
            )
        }

        let sample = await read(sessionID: sessionID, at: timestamp).first
        let isReadable = sample?.quality == .valid
        return TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .memory,
            source: .smc,
            supported: true,
            readable: isReadable,
            reasonCode: isReadable ? "ok" : sample?.errorCode ?? "noReadableTemperature",
            reasonMessage: isReadable ? "ok" : "No readable memory temperature from SMC.",
            rawKey: sample?.rawKey,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    public func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        guard let platform = platformDetector.detect() else {
            return [
                try! TemperatureSample.makeInvalid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.memoryProximity,
                    domain: .memory,
                    deviceID: "memory-package",
                    displayName: "Memory Proximity",
                    quality: .unsupported,
                    source: .smc,
                    errorCode: "platformUnsupported",
                    attributes: [
                        "readerError": "platformUnsupported",
                        "sourcePriority": TemperatureSource.smc.rawValue,
                    ]
                )
            ]
        }

        let readings = catalog.smcMemoryKeys(for: platform).compactMap { rawKey -> (String, Double)? in
            guard let value = smcReader.getValue(rawKey), TemperatureSample.isValidTemperatureValue(value) else {
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
                    errorCode: "noReadableTemperature",
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
