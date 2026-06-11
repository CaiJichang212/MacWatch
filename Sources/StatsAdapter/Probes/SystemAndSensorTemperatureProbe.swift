import Foundation
import MacWatchCore

private struct RawTemperatureReading: Sendable {
    let valueCelsius: Double
    let rawKey: String
}

public struct SystemTemperatureProbe: TemperatureProbe {
    public let id = "system.primary"
    public let domain: TemperatureDomain = .system
    public let source: TemperatureSource = .hidSensors
    public let defaultMetricName: String = TemperatureMetricName.systemHottest

    private let platformDetector: any ApplePlatformDetecting
    private let hidReader: any AppleSiliconTemperatureReading
    private let smcReader: any SMCValueReading
    private let catalog: AppleSiliconSensorCatalog

    public init(
        platformDetector: any ApplePlatformDetecting = ApplePlatformDetector(),
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        smcReader: any SMCValueReading = SMCReadOnlyClient(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.platformDetector = platformDetector
        self.hidReader = hidReader
        self.smcReader = smcReader
        self.catalog = catalog
    }

    public func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        let sample = (await read(sessionID: sessionID, at: timestamp)).first
        return TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .system,
            source: sample?.source ?? .hidSensors,
            supported: sample?.quality == .valid,
            readable: sample?.quality == .valid,
            reasonCode: sample?.quality == .valid ? "ok" : "readFailed",
            reasonMessage: sample?.quality.rawValue ?? "readFailed",
            rawKey: sample?.rawKey,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    public func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        let hidReadings = collectHIDReadings()

        if let hottest = hottestReading(from: hidReadings) {
            return [makeValidSample(
                sessionID: sessionID,
                timestamp: timestamp,
                value: hottest.valueCelsius,
                rawKey: hottest.rawKey,
                source: .hidSensors,
                attributes: [
                    "rawKeys": hidReadings.map(\.rawKey).sorted().joined(separator: ","),
                    "sourcePriority": sourcePriorityValue,
                ]
            )]
        }

        let smcReadings = collectSMCReadings()
        if let hottest = hottestReading(from: smcReadings) {
            return [makeValidSample(
                sessionID: sessionID,
                timestamp: timestamp,
                value: hottest.valueCelsius,
                rawKey: hottest.rawKey,
                source: .smc,
                attributes: [
                    "rawKeys": smcReadings.map(\.rawKey).sorted().joined(separator: ","),
                    "sourcePriority": sourcePriorityValue,
                ]
            )]
        }

        return [makeReadFailedSample(
            sessionID: sessionID,
            timestamp: timestamp,
            availableHIDKeys: hidReadings.map(\.rawKey).sorted(),
            availableSMCKeys: allSMCKeys().sorted()
        )]
    }

    private func collectHIDReadings() -> [RawTemperatureReading] {
        hidReader.readTemperatureValues().compactMap { rawKey, value in
            guard isValidTemperature(value) else {
                return nil
            }

            return RawTemperatureReading(valueCelsius: value, rawKey: rawKey)
        }
    }

    private func collectSMCReadings() -> [RawTemperatureReading] {
        allSMCKeys().compactMap { rawKey in
            guard let value = smcReader.getValue(rawKey), isValidTemperature(value) else {
                return nil
            }

            return RawTemperatureReading(valueCelsius: value, rawKey: rawKey)
        }
    }

    private func allSMCKeys() -> [String] {
        let platform = platformDetector.detect() ?? .intel
        return Array(
            Set(
                catalog.smcCPUKeys(for: platform)
                    + catalog.smcGPUKeys(for: platform)
                    + catalog.smcMemoryKeys(for: platform)
                    + catalog.smcSSDKeys()
                    + catalog.smcBatteryKeys()
            )
        )
    }

    private func hottestReading(
        from readings: [RawTemperatureReading]
    ) -> RawTemperatureReading? {
        readings.max {
            let lhsValue = $0.valueCelsius
            let rhsValue = $1.valueCelsius

            if lhsValue == rhsValue {
                return $0.rawKey < $1.rawKey
            }

            return lhsValue < rhsValue
        }
    }

    private var sourcePriorityValue: String {
        "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)"
    }

    private func makeValidSample(
        sessionID: UUID,
        timestamp: Date,
        value: Double,
        rawKey: String,
        source: TemperatureSource,
        attributes: [String: String]
    ) -> TemperatureSample {
        try! TemperatureSample.makeValid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: TemperatureMetricName.systemHottest,
            domain: .system,
            deviceID: "system",
            displayName: "System Hottest",
            valueCelsius: value,
            source: source,
            rawKey: rawKey,
            attributes: attributes
        )
    }

    private func makeReadFailedSample(
        sessionID: UUID,
        timestamp: Date,
        availableHIDKeys: [String],
        availableSMCKeys: [String]
    ) -> TemperatureSample {
        try! TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: TemperatureMetricName.systemHottest,
            domain: .system,
            deviceID: "system",
            displayName: "System Hottest",
            quality: .readFailed,
            source: .hidSensors,
            errorCode: "temperatureUnavailable",
            attributes: [
                "availableRawKeys": availableHIDKeys.joined(separator: ","),
                "attemptedSMCKeys": availableSMCKeys.joined(separator: ","),
                "readerError": "temperatureUnavailable",
                "sourcePriority": sourcePriorityValue,
            ]
        )
    }

    private func isValidTemperature(_ value: Double) -> Bool {
        TemperatureSample.isValidTemperatureValue(value)
    }
}

public struct SensorTemperatureProbe: TemperatureProbe {
    public let id = "sensor.raw.primary"
    public let domain: TemperatureDomain = .sensor
    public let source: TemperatureSource = .hidSensors
    public let defaultMetricName: String = TemperatureMetricName.sensorTemperatureRaw

    private let hidReader: any AppleSiliconTemperatureReading
    private let catalog: AppleSiliconSensorCatalog

    public init(
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.hidReader = hidReader
        self.catalog = catalog
    }

    public func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        let sample = (await read(sessionID: sessionID, at: timestamp)).first
        return TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .sensor,
            source: sample?.source ?? .hidSensors,
            supported: sample?.quality == .valid,
            readable: sample?.quality == .valid,
            reasonCode: sample?.quality == .valid ? "ok" : "readFailed",
            reasonMessage: sample?.quality.rawValue ?? "readFailed",
            rawKey: sample?.rawKey,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    public func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        let sensorReadings = collectUnknownHIDReadings()
        guard let hottest = hottestReading(from: sensorReadings) else {
            return [makeReadFailedSample(sessionID: sessionID, timestamp: timestamp)]
        }

        return [
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.sensorTemperatureRaw,
                domain: .sensor,
                deviceID: "raw-sensor",
                displayName: catalog.displayName(forRawKey: hottest.rawKey),
                valueCelsius: hottest.valueCelsius,
                source: .hidSensors,
                rawKey: hottest.rawKey,
                attributes: [
                    "rawKeys": sensorReadings
                        .map(\.rawKey)
                        .sorted()
                        .joined(separator: ","),
                    "sourcePriority": TemperatureSource.hidSensors.rawValue,
                ]
            )
        ]
    }

    private func collectUnknownHIDReadings() -> [RawTemperatureReading] {
        hidReader.readTemperatureValues().compactMap { rawKey, value in
            guard catalog.domain(forRawKey: rawKey) == nil,
                  isValidTemperature(value) else {
                return nil
            }

            return RawTemperatureReading(valueCelsius: value, rawKey: rawKey)
        }
    }

    private func hottestReading(
        from readings: [RawTemperatureReading]
    ) -> RawTemperatureReading? {
        readings.max {
            let lhsValue = $0.valueCelsius
            let rhsValue = $1.valueCelsius

            if lhsValue == rhsValue {
                return $0.rawKey < $1.rawKey
            }

            return lhsValue < rhsValue
        }
    }

    private func makeReadFailedSample(sessionID: UUID, timestamp: Date) -> TemperatureSample {
        let rawKeys = hidReader.readTemperatureValues().keys.sorted()
        return try! TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: TemperatureMetricName.sensorTemperatureRaw,
            domain: .sensor,
            deviceID: "raw-sensor",
            displayName: "Raw Sensor",
            quality: .readFailed,
            source: .hidSensors,
            errorCode: "temperatureUnavailable",
            attributes: [
                "attemptedRawKeys": rawKeys.joined(separator: ","),
                "sourcePriority": TemperatureSource.hidSensors.rawValue,
                "readerError": "noUnknownRawTemperatureKey",
            ]
        )
    }

    private func isValidTemperature(_ value: Double) -> Bool {
        TemperatureSample.isValidTemperatureValue(value)
    }
}
