import Foundation
import MacWatchCore

public struct BatteryTemperatureProbe: TemperatureProbe {
    public let id: String = "battery.primary"
    public let domain: TemperatureDomain = .battery
    public let source: TemperatureSource = .batteryIORegistry
    public let defaultMetricName: String = TemperatureMetricName.battery

    private let batteryReader: any BatteryTemperatureReadingSource
    private let hidReader: any AppleSiliconTemperatureReading
    private let smcReader: any SMCValueReading
    private let catalog: AppleSiliconSensorCatalog
    private let snapshotProvider: (any StatsTemperatureSensorSnapshotProviding)?

    public init(
        batteryReader: any BatteryTemperatureReadingSource = BatteryTemperatureIORegistryReader(),
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        smcReader: any SMCValueReading = SMCReadOnlyClient(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog(),
        snapshotProvider: (any StatsTemperatureSensorSnapshotProviding)? = nil
    ) {
        self.batteryReader = batteryReader
        self.hidReader = hidReader
        self.smcReader = smcReader
        self.catalog = catalog
        self.snapshotProvider = snapshotProvider
    }

    public init(
        batteryReader: any BatteryTemperatureReadingSource = BatteryTemperatureIORegistryReader(),
        snapshotProvider: any StatsTemperatureSensorSnapshotProviding,
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.batteryReader = batteryReader
        self.hidReader = AppleSiliconHIDTemperatureReader()
        self.smcReader = SMCReadOnlyClient()
        self.catalog = catalog
        self.snapshotProvider = snapshotProvider
    }

    public func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        guard batteryReader.hasBatteryService() else {
            return TemperatureCapability(
                id: UUID(),
                sessionID: sessionID,
                domain: .battery,
                source: .batteryIORegistry,
                supported: false,
                readable: false,
                reasonCode: "batteryServiceUnavailable",
                reasonMessage: "No AppleSmartBattery service is available on this device.",
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
            domain: .battery,
            source: sample?.source ?? .batteryIORegistry,
            supported: true,
            readable: isReadable,
            reasonCode: isReadable ? "ok" : sample?.errorCode ?? "noReadableTemperature",
            reasonMessage: isReadable ? "ok" : "No readable battery temperature from Battery IORegistry, HID Sensors, or SMC.",
            rawKey: sample?.rawKey,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    public func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        guard batteryReader.hasBatteryService() else {
            return [
                try! TemperatureSample.makeInvalid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.battery,
                    domain: .battery,
                    deviceID: "battery-pack",
                    displayName: "Battery",
                    quality: .unsupported,
                    source: .batteryIORegistry,
                    errorCode: "batteryServiceUnavailable",
                    attributes: [
                        "ioRegistryService": "AppleSmartBattery",
                        "ioRegistryProperty": "Temperature",
                    ]
                )
            ]
        }

        if let batteryReading = batteryReader.readTemperature(),
           TemperatureSample.isValidTemperatureValue(batteryReading.valueCelsius) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.battery,
                    domain: .battery,
                    deviceID: "battery-pack",
                    displayName: "Battery",
                    valueCelsius: batteryReading.valueCelsius,
                    source: .batteryIORegistry,
                    attributes: ["ioRegistryProperty": batteryReading.ioRegistryProperty]
                )
            ]
        }

        let snapshotReadings = readSnapshot().readings(for: .battery)
        if let hottest = snapshotReadings.max(by: { $0.valueCelsius < $1.valueCelsius }) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.battery,
                    domain: .battery,
                    deviceID: "battery-pack",
                    displayName: "Battery",
                    valueCelsius: hottest.valueCelsius,
                    source: hottest.source,
                    rawKey: hottest.rawKey,
                    attributes: [
                        "rawKeys": snapshotReadings.map(\.rawKey).sorted().joined(separator: ","),
                        "sourceSet": Self.sourceSet(from: snapshotReadings),
                        "sourcePriority": "\(TemperatureSource.batteryIORegistry.rawValue),\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
                    ]
                )
            ]
        }

        return [
            try! TemperatureSample.makeInvalid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.battery,
                domain: .battery,
                deviceID: "battery-pack",
                displayName: "Battery",
                quality: .readFailed,
                source: .batteryIORegistry,
                errorCode: "noReadableTemperature",
                attributes: [
                    "attemptedRawKeys": catalog.smcBatteryKeys().joined(separator: ","),
                    "ioRegistryProperty": "Temperature",
                    "readerError": "temperatureUnavailable",
                    "sourcePriority": "\(TemperatureSource.batteryIORegistry.rawValue),\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
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
            smcReader: smcReader,
            catalog: catalog,
            cacheDuration: 0
        ).readSnapshot()
    }

    private static func sourceSet(from readings: [StatsTemperatureSensorReading]) -> String {
        let sources = Set(readings.map(\.source))
        return [TemperatureSource.hidSensors, .smc]
            .filter(sources.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }
}
