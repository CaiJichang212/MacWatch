import Foundation
import MacWatchCore

public struct BatteryTemperatureProbe: TemperatureProbe {
    public let domain: TemperatureDomain = .battery
    public let source: TemperatureSource = .batteryIORegistry
    public let defaultMetricName: String = TemperatureMetricName.battery

    private let batteryReader: any BatteryTemperatureReadingSource
    private let hidReader: any AppleSiliconTemperatureReading
    private let smcReader: any SMCValueReading
    private let catalog: AppleSiliconSensorCatalog

    public init(
        batteryReader: any BatteryTemperatureReadingSource = BatteryTemperatureIORegistryReader(),
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        smcReader: any SMCValueReading = SMCReadOnlyClient(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.batteryReader = batteryReader
        self.hidReader = hidReader
        self.smcReader = smcReader
        self.catalog = catalog
    }

    public func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        let sample = await read(sessionID: sessionID, at: timestamp).first
        return TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .battery,
            source: sample?.source ?? .batteryIORegistry,
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
        if let batteryReading = batteryReader.readTemperature(), batteryReading.valueCelsius >= 0, batteryReading.valueCelsius < 110 {
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

        let hidValue = hidReader.readTemperatureValues()
            .first { $0.key.localizedCaseInsensitiveContains("gas gauge battery") && $0.value.isNaN == false && $0.value >= 0 && $0.value < 110 }
        if let hidValue {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.battery,
                    domain: .battery,
                    deviceID: "battery-pack",
                    displayName: "Battery",
                    valueCelsius: hidValue.value,
                    source: .hidSensors,
                    rawKey: hidValue.key
                )
            ]
        }

        let smcValues = catalog.smcBatteryKeys().compactMap { rawKey -> (String, Double)? in
            guard let value = smcReader.getValue(rawKey), value.isNaN == false, value >= 0, value < 110 else {
                return nil
            }
            return (rawKey, value)
        }
        if let hottest = smcValues.max(by: { $0.1 < $1.1 }) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.battery,
                    domain: .battery,
                    deviceID: "battery-pack",
                    displayName: "Battery",
                    valueCelsius: hottest.1,
                    source: .smc,
                    rawKey: hottest.0
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
                errorCode: "temperatureUnavailable",
                attributes: [
                    "attemptedRawKeys": catalog.smcBatteryKeys().joined(separator: ","),
                    "ioRegistryProperty": "Temperature",
                    "readerError": "temperatureUnavailable",
                    "sourcePriority": "\(TemperatureSource.batteryIORegistry.rawValue),\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
                ]
            )
        ]
    }
}
