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
    private let snapshotProvider: (any StatsTemperatureSensorSnapshotProviding)?

    public init(
        nvmeReader: any NVMeSMARTTemperatureReadingSource = NVMeSMARTTemperatureReader(),
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        smcReader: any SMCValueReading = SMCReadOnlyClient(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog(),
        snapshotProvider: (any StatsTemperatureSensorSnapshotProviding)? = nil
    ) {
        self.nvmeReader = nvmeReader
        self.hidReader = hidReader
        self.smcReader = smcReader
        self.catalog = catalog
        self.snapshotProvider = snapshotProvider
    }

    public init(
        nvmeReader: any NVMeSMARTTemperatureReadingSource = NVMeSMARTTemperatureReader(),
        snapshotProvider: any StatsTemperatureSensorSnapshotProviding,
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.nvmeReader = nvmeReader
        self.hidReader = AppleSiliconHIDTemperatureReader()
        self.smcReader = SMCReadOnlyClient()
        self.catalog = catalog
        self.snapshotProvider = snapshotProvider
    }

    public func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        let sample = await read(sessionID: sessionID, at: timestamp).first
        let isReadable = sample?.quality == .valid
        let isUnsupported = sample?.quality == .unsupported
        return TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .ssd,
            source: sample?.source ?? .nvmeSMART,
            supported: isReadable || isUnsupported == false,
            readable: isReadable,
            reasonCode: isReadable ? "ok" : sample?.errorCode ?? "noReadableTemperature",
            reasonMessage: ssdReasonMessage(isReadable: isReadable, sample: sample),
            rawKey: sample?.rawKey,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    public func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        let hasInternalSMARTDisk = nvmeReader.hasInternalSMARTCapableDisk()

        if hasInternalSMARTDisk,
           let nvmeReading = nvmeReader.readInternalTemperature(),
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
                    attributes: [
                        "smartField": nvmeReading.smartField,
                        "sourcePriority": sourcePriority,
                    ]
                )
            ]
        }

        let snapshotReadings = readSnapshot().readings(for: .ssd)
        if let hottest = preferredFallbackReading(from: snapshotReadings) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.ssdInternal,
                    domain: .ssd,
                    deviceID: "internal-ssd",
                    displayName: "Internal SSD",
                    valueCelsius: hottest.valueCelsius,
                    source: hottest.source,
                    rawKey: hottest.rawKey,
                    attributes: fallbackAttributes(
                        hasInternalSMARTDisk: hasInternalSMARTDisk,
                        readings: snapshotReadings
                    )
                )
            ]
        }

        let quality: TemperatureQuality = hasInternalSMARTDisk ? .readFailed : .unsupported
        let errorCode = hasInternalSMARTDisk ? "noReadableTemperature" : "internalSMARTDiskUnavailable"
        return [
            try! TemperatureSample.makeInvalid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.ssdInternal,
                domain: .ssd,
                deviceID: "internal-ssd",
                displayName: "Internal SSD",
                quality: quality,
                source: .nvmeSMART,
                errorCode: errorCode,
                attributes: [
                    "attemptedRawKeys": catalog.smcSSDKeys().joined(separator: ","),
                    "readerError": "temperatureUnavailable",
                    "smartField": "temperature",
                    "smartStatus": hasInternalSMARTDisk ? "available" : "internalSMARTDiskUnavailable",
                    "sourcePriority": sourcePriority,
                ]
            )
        ]
    }

    private var sourcePriority: String {
        "\(TemperatureSource.nvmeSMART.rawValue),\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue)"
    }

    private func fallbackAttributes(
        hasInternalSMARTDisk: Bool,
        readings: [StatsTemperatureSensorReading]
    ) -> [String: String] {
        [
            "rawKeys": readings.map(\.rawKey).sorted().joined(separator: ","),
            "smartField": "temperature",
            "smartStatus": hasInternalSMARTDisk ? "readFailed" : "internalSMARTDiskUnavailable",
            "sourceSet": Self.sourceSet(from: readings),
            "sourcePriority": sourcePriority,
        ]
    }

    private func ssdReasonMessage(isReadable: Bool, sample: TemperatureSample?) -> String {
        if isReadable {
            return "ok"
        }
        if sample?.quality == .unsupported {
            return "No internal NVMe SMART-capable disk is available and no NAND HID/SMC temperature fallback was readable."
        }
        return "No readable internal SSD temperature from NVMe SMART, HID Sensors, or SMC."
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

    private func preferredFallbackReading(
        from readings: [StatsTemperatureSensorReading]
    ) -> StatsTemperatureSensorReading? {
        let hidReadings = readings.filter { $0.source == .hidSensors }
        if let hottestHID = hidReadings.max(by: { $0.valueCelsius < $1.valueCelsius }) {
            return hottestHID
        }
        return readings.max(by: { $0.valueCelsius < $1.valueCelsius })
    }

    private static func sourceSet(from readings: [StatsTemperatureSensorReading]) -> String {
        let sources = Set(readings.map(\.source))
        return [TemperatureSource.hidSensors, .smc]
            .filter(sources.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }
}
