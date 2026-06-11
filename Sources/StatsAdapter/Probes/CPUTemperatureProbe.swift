import Foundation
import MacWatchCore
import StatsAdapterIOHID

public protocol ApplePlatformDetecting: Sendable {
    func detect() -> ApplePlatform?
}

extension ApplePlatformDetector: ApplePlatformDetecting {}

public protocol AppleSiliconTemperatureReading: Sendable {
    func readTemperatureValues() -> [String: Double]
}

public final class AppleSiliconHIDTemperatureReader: AppleSiliconTemperatureReading, @unchecked Sendable {
    private let page: Int32
    private let usage: Int32
    private let eventType: Int32

    public init(
        page: Int32 = 0xff00,
        usage: Int32 = 0x0005,
        eventType: Int32 = StatsAdapterIOHIDEventTypeTemperature
    ) {
        self.page = page
        self.usage = usage
        self.eventType = eventType
    }

    public func readTemperatureValues() -> [String: Double] {
        guard let raw = StatsAdapterCopyAppleSiliconTemperatureSensors(page, usage, eventType) else {
            return [:]
        }

        var values: [String: Double] = [:]
        for (key, value) in raw {
            values[key] = value.doubleValue
        }
        return values
    }
}

public struct CPUTemperatureProbe: TemperatureProbe {
    public let id: String = "cpu.hid-sensors.primary"
    public let domain: TemperatureDomain = .cpu
    public let source: TemperatureSource = .hidSensors
    public let defaultMetricName: String = TemperatureMetricName.cpuHottest

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

    public func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        let readings = cpuReadings()
        if let reading = readings.first {
            return makeCapability(
                sessionID: sessionID,
                timestamp: timestamp,
                source: reading.source,
                readable: true,
                reasonCode: "ok",
                rawKey: reading.rawKey
            )
        }

        return makeCapability(
            sessionID: sessionID,
            timestamp: timestamp,
            source: .smc,
            readable: false,
            reasonCode: "readFailed",
            rawKey: nil
        )
    }

    public func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        let snapshot = readSnapshot()
        let chosenReadings = snapshot.readings(for: .cpu, averageOnly: true)

        guard chosenReadings.isEmpty == false else {
            return makeReadFailedSamples(
                sessionID: sessionID,
                timestamp: timestamp,
                availableHIDKeys: snapshot.availableHIDKeys,
                availableSMCKeys: snapshot.availableSMCKeys
            )
        }

        guard let hottest = chosenReadings.max(by: { $0.valueCelsius < $1.valueCelsius }) else {
            return makeReadFailedSamples(
                sessionID: sessionID,
                timestamp: timestamp,
                availableHIDKeys: snapshot.availableHIDKeys,
                availableSMCKeys: snapshot.availableSMCKeys
            )
        }

        let rawKeys = chosenReadings.sorted(by: isPreferredRawKey(lhs:rhs:)).map(\.rawKey).joined(separator: ",")
        let average = chosenReadings.map(\.valueCelsius).reduce(0, +) / Double(chosenReadings.count)
        let sourceSet = Self.sourceSet(from: chosenReadings)
        return [
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu-package",
                displayName: "CPU Hottest",
                valueCelsius: hottest.valueCelsius,
                source: hottest.source,
                rawKey: hottest.rawKey,
                attributes: [
                    "rawKeys": rawKeys,
                    "sourceSet": sourceSet,
                    "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
                ]
            ),
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.cpuAverage,
                domain: .cpu,
                deviceID: "cpu-package",
                displayName: "CPU Average",
                valueCelsius: average,
                source: hottest.source,
                attributes: [
                    "rawKeys": rawKeys,
                    "sourceSet": sourceSet,
                    "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
                ]
            ),
        ]
    }

    private func cpuReadings() -> [StatsTemperatureSensorReading] {
        readSnapshot().readings(for: .cpu, averageOnly: true)
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

    private func makeCapability(
        sessionID: UUID,
        timestamp: Date,
        source: TemperatureSource,
        readable: Bool,
        reasonCode: String,
        rawKey: String?
    ) -> TemperatureCapability {
        TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .cpu,
            source: source,
            supported: readable,
            readable: readable,
            reasonCode: reasonCode,
            reasonMessage: reasonCode,
            rawKey: rawKey,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func makeReadFailedSamples(
        sessionID: UUID,
        timestamp: Date,
        availableHIDKeys: [String],
        availableSMCKeys: [String]
    ) -> [TemperatureSample] {
        let platform = platformDetector.detect() ?? .intel
        let candidateSMCKeys = catalog.smcCPUKeys(for: platform)
        let attemptedRawKeys = candidateSMCKeys + ["pACC MTR Temp Sensor0", "eACC MTR Temp Sensor0"]
        let matchingSMCKeys = availableSMCKeys.filter(candidateSMCKeys.contains)
        let attributes = [
            "attemptedRawKeys": attemptedRawKeys.joined(separator: ","),
            "availableHIDKeys": availableHIDKeys.joined(separator: ","),
            "matchingSMCKeys": matchingSMCKeys.joined(separator: ","),
            "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
        ]

        return [
            makeReadFailedSample(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.cpuHottest,
                displayName: "CPU Hottest",
                attributes: attributes
            ),
            makeReadFailedSample(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.cpuAverage,
                displayName: "CPU Average",
                attributes: attributes
            ),
        ]
    }

    private func makeReadFailedSample(
        sessionID: UUID,
        timestamp: Date,
        metricName: String,
        displayName: String,
        attributes: [String: String]
    ) -> TemperatureSample {
        try! TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: metricName,
            domain: .cpu,
            deviceID: "cpu-package",
            displayName: displayName,
            quality: .readFailed,
            source: .smc,
            errorCode: "temperatureUnavailable",
            attributes: attributes
        )
    }

    private static func sourceSet(from readings: [StatsTemperatureSensorReading]) -> String {
        let sources = Set(readings.map(\.source))
        return [TemperatureSource.hidSensors, .smc]
            .filter(sources.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }

    private func isPreferredRawKey(
        lhs: StatsTemperatureSensorReading,
        rhs: StatsTemperatureSensorReading
    ) -> Bool {
        let leftPriority = rawKeyPriority(lhs.rawKey)
        let rightPriority = rawKeyPriority(rhs.rawKey)
        if leftPriority == rightPriority {
            return lhs.rawKey < rhs.rawKey
        }
        return leftPriority < rightPriority
    }

    private func rawKeyPriority(_ rawKey: String) -> Int {
        let platform = platformDetector.detect() ?? .intel
        if let index = catalog.smcCPUKeys(for: platform).firstIndex(of: rawKey) {
            return index
        }
        if rawKey.hasPrefix("pACC MTR Temp Sensor") {
            return 10_000 + (sensorIndex(in: rawKey) ?? 0)
        }
        if rawKey.hasPrefix("eACC MTR Temp Sensor") {
            return 20_000 + (sensorIndex(in: rawKey) ?? 0)
        }
        return 30_000
    }

    private func sensorIndex(in rawKey: String) -> Int? {
        let digits = rawKey.reversed().prefix { $0.isNumber }.reversed()
        guard digits.isEmpty == false else {
            return nil
        }
        return Int(String(digits))
    }
}
