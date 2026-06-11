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
        let hidReadings = hidCPUReadings()
        if let reading = hidReadings.first {
            return makeCapability(
                sessionID: sessionID,
                timestamp: timestamp,
                source: .hidSensors,
                readable: true,
                reasonCode: "ok",
                rawKey: reading.rawKey
            )
        }

        let smcReadings = smcCPUReadings()
        if let reading = smcReadings.first {
            return makeCapability(
                sessionID: sessionID,
                timestamp: timestamp,
                source: .smc,
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
        let smcReadings = smcCPUReadings()
        let hidReadings = hidCPUReadings().sorted(by: isPreferred(lhs:rhs:))
        let chosenReadings = smcReadings + hidReadings

        guard chosenReadings.isEmpty == false else {
            return makeReadFailedSamples(
                sessionID: sessionID,
                timestamp: timestamp,
                availableHIDKeys: hidReader.readTemperatureValues().keys.sorted(),
                availableSMCKeys: smcReader.getAllKeys()
            )
        }

        guard let hottest = chosenReadings.max(by: { $0.valueCelsius < $1.valueCelsius }) else {
            return makeReadFailedSamples(
                sessionID: sessionID,
                timestamp: timestamp,
                availableHIDKeys: hidReader.readTemperatureValues().keys.sorted(),
                availableSMCKeys: smcReader.getAllKeys()
            )
        }

        let rawKeys = chosenReadings.map(\.rawKey).joined(separator: ",")
        let average = chosenReadings.map(\.valueCelsius).reduce(0, +) / Double(chosenReadings.count)
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
                    "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
                ]
            ),
        ]
    }

    private func hidCPUReadings() -> [RawTemperatureReading] {
        hidReader
            .readTemperatureValues()
            .compactMap { rawKey, value in
                guard catalog.isCPUHIDKey(rawKey), isValidTemperature(value) else {
                    return nil
                }

                return RawTemperatureReading(
                    displayName: catalog.displayName(forRawKey: rawKey),
                    valueCelsius: value,
                    source: .hidSensors,
                    rawKey: rawKey
                )
            }
    }

    private func smcCPUReadings() -> [RawTemperatureReading] {
        let platform = platformDetector.detect() ?? .intel
        return catalog.smcCPUKeys(for: platform).compactMap { rawKey in
            guard let value = smcReader.getValue(rawKey), isValidTemperature(value) else {
                return nil
            }

            return RawTemperatureReading(
                displayName: catalog.displayName(forRawKey: rawKey),
                valueCelsius: value,
                source: .smc,
                rawKey: rawKey
            )
        }
    }

    private func isValidTemperature(_ value: Double) -> Bool {
        TemperatureSample.isValidTemperatureValue(value)
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

    private func isPreferred(lhs: RawTemperatureReading, rhs: RawTemperatureReading) -> Bool {
        let leftPriority = sourcePriority(for: lhs.rawKey)
        let rightPriority = sourcePriority(for: rhs.rawKey)
        if leftPriority == rightPriority {
            return lhs.rawKey < rhs.rawKey
        }
        return leftPriority < rightPriority
    }

    private func sourcePriority(for rawKey: String) -> Int {
        if rawKey.hasPrefix("pACC MTR Temp Sensor") {
            return 0
        }
        if rawKey.hasPrefix("eACC MTR Temp Sensor") {
            return 1
        }
        return 2
    }
}

private struct RawTemperatureReading: Sendable {
    let displayName: String
    let valueCelsius: Double
    let source: TemperatureSource
    let rawKey: String
}
