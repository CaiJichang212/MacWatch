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
        let hidReadings = hidCPUReadings()
        let chosenReadings: [RawTemperatureReading]
        let winningSource: TemperatureSource

        if hidReadings.isEmpty == false {
            chosenReadings = hidReadings
            winningSource = .hidSensors
        } else {
            let smcReadings = smcCPUReadings()
            if smcReadings.isEmpty == false {
                chosenReadings = smcReadings
                winningSource = .smc
            } else {
                return [makeReadFailedSample(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    availableHIDKeys: hidReader.readTemperatureValues().keys.sorted(),
                    availableSMCKeys: smcReader.getAllKeys()
                )]
            }
        }

        let sortedReadings = chosenReadings.sorted(by: isPreferred(lhs:rhs:))
        guard let hottest = sortedReadings.max(by: { $0.valueCelsius < $1.valueCelsius }) else {
            return [makeReadFailedSample(
                sessionID: sessionID,
                timestamp: timestamp,
                availableHIDKeys: hidReader.readTemperatureValues().keys.sorted(),
                availableSMCKeys: smcReader.getAllKeys()
            )]
        }

        let rawKeys = sortedReadings.map(\.rawKey).joined(separator: ",")
        var samples: [TemperatureSample] = [
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu-package",
                displayName: "CPU Hottest",
                valueCelsius: hottest.valueCelsius,
                source: winningSource,
                rawKey: hottest.rawKey,
                attributes: [
                    "rawKeys": rawKeys,
                    "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
                ]
            )
        ]

        if sortedReadings.count >= 2 {
            let average = sortedReadings.map(\.valueCelsius).reduce(0, +) / Double(sortedReadings.count)
            samples.append(
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.cpuAverage,
                    domain: .cpu,
                    deviceID: "cpu-package",
                    displayName: "CPU Average",
                    valueCelsius: average,
                    source: winningSource,
                    attributes: [
                        "rawKeys": rawKeys,
                        "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
                    ]
                )
            )
        }

        return samples
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
        value.isNaN == false && value >= 0 && value < 110
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

    private func makeReadFailedSample(
        sessionID: UUID,
        timestamp: Date,
        availableHIDKeys: [String],
        availableSMCKeys: [String]
    ) -> TemperatureSample {
        let platform = platformDetector.detect() ?? .intel
        let candidateSMCKeys = catalog.smcCPUKeys(for: platform)
        let attemptedRawKeys = candidateSMCKeys + ["pACC MTR Temp Sensor0", "eACC MTR Temp Sensor0"]
        let matchingSMCKeys = availableSMCKeys.filter(candidateSMCKeys.contains)

        return try! TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu-package",
            displayName: "CPU Hottest",
            quality: .readFailed,
            source: .smc,
            errorCode: "temperatureUnavailable",
            attributes: [
                "attemptedRawKeys": attemptedRawKeys.joined(separator: ","),
                "availableHIDKeys": availableHIDKeys.joined(separator: ","),
                "matchingSMCKeys": matchingSMCKeys.joined(separator: ","),
                "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
            ]
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
