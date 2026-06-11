import Foundation
import MacWatchCore

public struct SSDTemperatureProbe: TemperatureProbe {
    public let id: String = "ssd.internal.primary"
    public let domain: TemperatureDomain = .ssd
    public let source: TemperatureSource = .nvmeSMART
    public let defaultMetricName: String = TemperatureMetricName.ssdInternal

    private let nvmeReader: any NVMeSMARTTemperatureReadingSource
    private let hidReader: any AppleSiliconTemperatureReading
    private let smcReader: any SMCValueReading
    private let catalog: AppleSiliconSensorCatalog

    public init(
        nvmeReader: any NVMeSMARTTemperatureReadingSource = NVMeSMARTTemperatureReader(),
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        smcReader: any SMCValueReading = SMCReadOnlyClient(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.nvmeReader = nvmeReader
        self.hidReader = hidReader
        self.smcReader = smcReader
        self.catalog = catalog
    }

    public func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        guard nvmeReader.hasInternalSMARTCapableDisk() else {
            return TemperatureCapability(
                id: UUID(),
                sessionID: sessionID,
                domain: .ssd,
                source: .nvmeSMART,
                supported: false,
                readable: false,
                reasonCode: "internalSMARTDiskUnavailable",
                reasonMessage: "No internal NVMe SMART-capable disk is available on this device.",
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
            domain: .ssd,
            source: sample?.source ?? .nvmeSMART,
            supported: true,
            readable: isReadable,
            reasonCode: isReadable ? "ok" : sample?.errorCode ?? "noReadableTemperature",
            reasonMessage: isReadable ? "ok" : "No readable internal SSD temperature from NVMe SMART, HID Sensors, or SMC.",
            rawKey: sample?.rawKey,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    public func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        guard nvmeReader.hasInternalSMARTCapableDisk() else {
            return [
                try! TemperatureSample.makeInvalid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.ssdInternal,
                    domain: .ssd,
                    deviceID: "internal-ssd",
                    displayName: "Internal SSD",
                    quality: .unsupported,
                    source: .nvmeSMART,
                    errorCode: "internalSMARTDiskUnavailable",
                    attributes: [
                        "smartField": "temperature",
                        "sourcePriority": TemperatureSource.nvmeSMART.rawValue,
                    ]
                )
            ]
        }

        if let nvmeReading = nvmeReader.readInternalTemperature(),
           TemperatureSample.isValidTemperatureValue(nvmeReading.valueCelsius) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.ssdInternal,
                    domain: .ssd,
                    deviceID: "internal-ssd",
                    displayName: "Internal SSD",
                    valueCelsius: nvmeReading.valueCelsius,
                    source: .nvmeSMART,
                    attributes: ["smartField": nvmeReading.smartField]
                )
            ]
        }

        let hidValues = hidReader.readTemperatureValues().compactMap { rawKey, value -> (String, Double)? in
            guard catalog.isSSDHIDKey(rawKey), TemperatureSample.isValidTemperatureValue(value) else {
                return nil
            }
            return (rawKey, value)
        }
        if let hottest = hidValues.max(by: { $0.1 < $1.1 }) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.ssdInternal,
                    domain: .ssd,
                    deviceID: "internal-ssd",
                    displayName: "Internal SSD",
                    valueCelsius: hottest.1,
                    source: .hidSensors,
                    rawKey: hottest.0
                )
            ]
        }

        let smcValues = catalog.smcSSDKeys().compactMap { rawKey -> (String, Double)? in
            guard let value = smcReader.getValue(rawKey), TemperatureSample.isValidTemperatureValue(value) else {
                return nil
            }
            return (rawKey, value)
        }
        if let hottest = smcValues.max(by: { $0.1 < $1.1 }) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.ssdInternal,
                    domain: .ssd,
                    deviceID: "internal-ssd",
                    displayName: "Internal SSD",
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
                metricName: TemperatureMetricName.ssdInternal,
                domain: .ssd,
                deviceID: "internal-ssd",
                displayName: "Internal SSD",
                quality: .readFailed,
                source: .nvmeSMART,
                errorCode: "noReadableTemperature",
                attributes: [
                    "attemptedRawKeys": catalog.smcSSDKeys().joined(separator: ","),
                    "readerError": "temperatureUnavailable",
                    "smartField": "temperature",
                    "sourcePriority": "\(TemperatureSource.nvmeSMART.rawValue),\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)",
                ]
            )
        ]
    }
}
