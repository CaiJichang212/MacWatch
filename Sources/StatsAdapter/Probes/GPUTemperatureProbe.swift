import Foundation
import MacWatchCore

public struct GPUTemperatureProbe: TemperatureProbe {
    public let domain: TemperatureDomain = .gpu
    public let source: TemperatureSource = .hidSensors
    public let defaultMetricName: String = TemperatureMetricName.gpuHottest

    private let platformDetector: any ApplePlatformDetecting
    private let hidReader: any AppleSiliconTemperatureReading
    private let smcReader: any SMCValueReading
    private let ioAcceleratorReader: any IOAcceleratorTemperatureReadingSource
    private let catalog: AppleSiliconSensorCatalog

    public init(
        platformDetector: any ApplePlatformDetecting = ApplePlatformDetector(),
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        smcReader: any SMCValueReading = SMCReadOnlyClient(),
        ioAcceleratorReader: any IOAcceleratorTemperatureReadingSource = IOAcceleratorTemperatureReader(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog()
    ) {
        self.platformDetector = platformDetector
        self.hidReader = hidReader
        self.smcReader = smcReader
        self.ioAcceleratorReader = ioAcceleratorReader
        self.catalog = catalog
    }

    public func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        if let sample = await read(sessionID: sessionID, at: timestamp).first {
            return capability(from: sample, sessionID: sessionID, timestamp: timestamp)
        }

        return fallbackCapability(sessionID: sessionID, timestamp: timestamp)
    }

    public func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        let hidReadings = hidReader.readTemperatureValues()
            .compactMap { rawKey, value -> (String, Double)? in
                guard catalog.isGPUHIDKey(rawKey), isValid(value) else {
                    return nil
                }
                return (rawKey, value)
            }
        if let hottest = hidReadings.max(by: { $0.1 < $1.1 }) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.gpuHottest,
                    domain: .gpu,
                    deviceID: "gpu-die",
                    displayName: "GPU Hottest",
                    valueCelsius: hottest.1,
                    source: .hidSensors,
                    rawKey: hottest.0,
                    attributes: ["rawKeys": hidReadings.map(\.0).joined(separator: ",")]
                )
            ]
        }

        let platform = platformDetector.detect() ?? .intel
        let smcReadings = catalog.smcGPUKeys(for: platform).compactMap { rawKey -> (String, Double)? in
            guard let value = smcReader.getValue(rawKey), isValid(value) else {
                return nil
            }
            return (rawKey, value)
        }
        if let hottest = smcReadings.max(by: { $0.1 < $1.1 }) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.gpuHottest,
                    domain: .gpu,
                    deviceID: "gpu-die",
                    displayName: "GPU Hottest",
                    valueCelsius: hottest.1,
                    source: .smc,
                    rawKey: hottest.0,
                    attributes: ["rawKeys": smcReadings.map(\.0).joined(separator: ",")]
                )
            ]
        }

        if let ioReading = ioAcceleratorReader.readTemperature(), isValid(ioReading.valueCelsius) {
            return [
                try! TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.gpuHottest,
                    domain: .gpu,
                    deviceID: "gpu-die",
                    displayName: "GPU Hottest",
                    valueCelsius: ioReading.valueCelsius,
                    source: .ioReportCandidate,
                    attributes: ["statisticsField": ioReading.statisticsField]
                )
            ]
        }

        return [unavailableSample(sessionID: sessionID, timestamp: timestamp)]
    }

    private func isValid(_ value: Double) -> Bool {
        value.isNaN == false && value >= 0 && value < 110
    }

    private func capability(from sample: TemperatureSample, sessionID: UUID, timestamp: Date) -> TemperatureCapability {
        TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .gpu,
            source: sample.source,
            supported: true,
            readable: sample.quality == .valid,
            reasonCode: sample.quality == .valid ? "ok" : "readFailed",
            reasonMessage: sample.quality.rawValue,
            rawKey: sample.rawKey,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func fallbackCapability(sessionID: UUID, timestamp: Date) -> TemperatureCapability {
        TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .gpu,
            source: .smc,
            supported: false,
            readable: false,
            reasonCode: "readFailed",
            reasonMessage: "readFailed",
            rawKey: nil,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func unavailableSample(sessionID: UUID, timestamp: Date) -> TemperatureSample {
        let platform = platformDetector.detect() ?? .intel
        return try! TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: TemperatureMetricName.gpuHottest,
            domain: .gpu,
            deviceID: "gpu-die",
            displayName: "GPU Hottest",
            quality: .readFailed,
            source: .smc,
            errorCode: "temperatureUnavailable",
            attributes: [
                "attemptedRawKeys": catalog.smcGPUKeys(for: platform).joined(separator: ","),
                "readerError": "temperatureUnavailable",
                "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue),\(TemperatureSource.ioReportCandidate.rawValue)",
                "statisticsField": "Temperature(C)",
            ]
        )
    }
}
