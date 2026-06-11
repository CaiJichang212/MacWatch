import Foundation
import MacWatchCore

public struct SystemTemperatureProbe: TemperatureProbe {
    public let id = "system.primary"
    public let domain: TemperatureDomain = .system
    public let source: TemperatureSource = .hidSensors
    public let defaultMetricName: String = TemperatureMetricName.systemHottest

    private let platformDetector: any ApplePlatformDetecting
    private let hidReader: any AppleSiliconTemperatureReading
    private let smcReader: any SMCValueReading
    private let catalog: AppleSiliconSensorCatalog
    private let snapshotProvider: (any StatsTemperatureSensorSnapshotProviding)?

    public init(
        platformDetector: any ApplePlatformDetecting = ApplePlatformDetector(),
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        smcReader: any SMCValueReading = SMCReadOnlyClient(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog(),
        snapshotProvider: (any StatsTemperatureSensorSnapshotProviding)? = nil
    ) {
        self.platformDetector = platformDetector
        self.hidReader = hidReader
        self.smcReader = smcReader
        self.catalog = catalog
        self.snapshotProvider = snapshotProvider
    }

    public init(
        snapshotProvider: any StatsTemperatureSensorSnapshotProviding,
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.platformDetector = ApplePlatformDetector()
        self.hidReader = AppleSiliconHIDTemperatureReader()
        self.smcReader = SMCReadOnlyClient()
        self.catalog = catalog
        self.snapshotProvider = snapshotProvider
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
        let snapshot = readSnapshot()
        let systemReadings = snapshot.readings(for: .system)

        if let hottest = hottestReading(from: systemReadings) {
            return [makeValidSample(
                sessionID: sessionID,
                timestamp: timestamp,
                value: hottest.valueCelsius,
                rawKey: hottest.rawKey,
                source: hottest.source,
                attributes: [
                    "rawKeys": systemReadings.map(\.rawKey).sorted().joined(separator: ","),
                    "sourceSet": Self.sourceSet(from: systemReadings),
                    "sourcePriority": sourcePriorityValue,
                ]
            )]
        }

        return [makeReadFailedSample(
            sessionID: sessionID,
            timestamp: timestamp,
            availableRawKeys: snapshot.readings.map(\.rawKey).sorted(),
            availableSMCKeys: snapshot.availableSMCKeys
        )]
    }

    private func readSnapshot() -> StatsTemperatureSensorSnapshot {
        if let snapshotProvider {
            return snapshotProvider.readSnapshot()
        }
        return StatsTemperatureSensorSnapshotProvider(
            platformDetector: platformDetector,
            hidReader: hidReader,
            smcReader: smcReader,
            catalog: catalog,
            cacheDuration: 0
        ).readSnapshot()
    }

    private func hottestReading(
        from readings: [StatsTemperatureSensorReading]
    ) -> StatsTemperatureSensorReading? {
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
        availableRawKeys: [String],
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
                "availableRawKeys": availableRawKeys.joined(separator: ","),
                "attemptedSMCKeys": availableSMCKeys.joined(separator: ","),
                "readerError": "temperatureUnavailable",
                "sourcePriority": sourcePriorityValue,
            ]
        )
    }

    private func isValidTemperature(_ value: Double) -> Bool {
        TemperatureSample.isValidTemperatureValue(value)
    }

    private static func sourceSet(from readings: [StatsTemperatureSensorReading]) -> String {
        let sources = Set(readings.map(\.source))
        return [TemperatureSource.hidSensors, .smc]
            .filter(sources.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }
}

public struct SensorTemperatureProbe: TemperatureProbe {
    public let id = "sensor.raw.primary"
    public let domain: TemperatureDomain = .sensor
    public let source: TemperatureSource = .hidSensors
    public let defaultMetricName: String = TemperatureMetricName.sensorTemperatureRaw

    private let hidReader: any AppleSiliconTemperatureReading
    private let catalog: AppleSiliconSensorCatalog
    private let snapshotProvider: (any StatsTemperatureSensorSnapshotProviding)?

    public init(
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog(),
        snapshotProvider: (any StatsTemperatureSensorSnapshotProviding)? = nil
    ) {
        self.hidReader = hidReader
        self.catalog = catalog
        self.snapshotProvider = snapshotProvider
    }

    public init(
        snapshotProvider: any StatsTemperatureSensorSnapshotProviding,
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.hidReader = AppleSiliconHIDTemperatureReader()
        self.catalog = catalog
        self.snapshotProvider = snapshotProvider
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
        let snapshot = readSnapshot()
        let sensorReadings = snapshot.readings(for: .sensor)
        guard let hottest = hottestReading(from: sensorReadings) else {
            return [makeReadFailedSample(sessionID: sessionID, timestamp: timestamp, snapshot: snapshot)]
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
                    "sourceSet": Self.sourceSet(from: sensorReadings),
                    "sourcePriority": TemperatureSource.hidSensors.rawValue,
                ]
            )
        ]
    }

    private func readSnapshot() -> StatsTemperatureSensorSnapshot {
        if let snapshotProvider {
            return snapshotProvider.readSnapshot()
        }
        return StatsTemperatureSensorSnapshotProvider(
            hidReader: hidReader,
            catalog: catalog,
            cacheDuration: 0
        ).readSnapshot()
    }

    private func hottestReading(
        from readings: [StatsTemperatureSensorReading]
    ) -> StatsTemperatureSensorReading? {
        readings.max {
            let lhsValue = $0.valueCelsius
            let rhsValue = $1.valueCelsius

            if lhsValue == rhsValue {
                return $0.rawKey < $1.rawKey
            }

            return lhsValue < rhsValue
        }
    }

    private func makeReadFailedSample(
        sessionID: UUID,
        timestamp: Date,
        snapshot: StatsTemperatureSensorSnapshot
    ) -> TemperatureSample {
        let rawKeys = snapshot.readings.map(\.rawKey).sorted()
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

    private static func sourceSet(from readings: [StatsTemperatureSensorReading]) -> String {
        let sources = Set(readings.map(\.source))
        return [TemperatureSource.hidSensors, .smc]
            .filter(sources.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }
}
