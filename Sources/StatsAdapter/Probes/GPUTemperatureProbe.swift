import Foundation
import MacWatchCore

public struct GPUTemperatureProbe: TemperatureProbe {
    public let id: String = "gpu.primary"
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
            .sorted { $0.0 < $1.0 }

        let platform = platformDetector.detect() ?? .intel
        let smcReadings = catalog.smcGPUKeys(for: platform).compactMap { rawKey -> (String, Double)? in
            guard let value = smcReader.getValue(rawKey), isValid(value) else {
                return nil
            }
            return (rawKey, value)
        }

        let statsSensorReadings = hidReadings + smcReadings
        if let hottest = statsSensorReadings.max(by: { $0.1 < $1.1 }) {
            return makeValidSamples(
                sessionID: sessionID,
                timestamp: timestamp,
                readings: statsSensorReadings,
                hottest: hottest,
                source: hidReadings.contains(where: { $0.0 == hottest.0 }) ? .hidSensors : .smc
            )
        }

        if let ioAcceleratorReading = ioAcceleratorReader.readTemperature(),
           isValid(ioAcceleratorReading.valueCelsius) {
            return makeIOAcceleratorSamples(
                sessionID: sessionID,
                timestamp: timestamp,
                reading: ioAcceleratorReading
            )
        }

        return unavailableSamples(
            sessionID: sessionID,
            timestamp: timestamp,
            ioAcceleratorCandidate: nil
        )
    }

    private func isValid(_ value: Double) -> Bool {
        TemperatureSample.isValidTemperatureValue(value)
    }

    private func makeValidSamples(
        sessionID: UUID,
        timestamp: Date,
        readings: [(String, Double)],
        hottest: (String, Double),
        source: TemperatureSource
    ) -> [TemperatureSample] {
        let rawKeys = readings.map(\.0).sorted().joined(separator: ",")
        let average = readings.map(\.1).reduce(0, +) / Double(readings.count)
        return [
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.gpuHottest,
                domain: .gpu,
                deviceID: "gpu-die",
                displayName: "GPU Hottest",
                valueCelsius: hottest.1,
                source: source,
                rawKey: hottest.0,
                attributes: ["rawKeys": rawKeys]
            ),
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.gpuAverage,
                domain: .gpu,
                deviceID: "gpu-die",
                displayName: "GPU Average",
                valueCelsius: average,
                source: source,
                attributes: ["rawKeys": rawKeys]
            ),
        ]
    }

    private func makeIOAcceleratorSamples(
        sessionID: UUID,
        timestamp: Date,
        reading: IOAcceleratorTemperatureReading
    ) -> [TemperatureSample] {
        let attributes = [
            "rawKeys": reading.statisticsField,
            "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue),\(TemperatureSource.ioReportCandidate.rawValue)",
        ]

        return [
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.gpuHottest,
                domain: .gpu,
                deviceID: "gpu-die",
                displayName: "GPU Hottest",
                valueCelsius: reading.valueCelsius,
                source: .ioReportCandidate,
                rawKey: reading.statisticsField,
                attributes: attributes
            ),
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.gpuAverage,
                domain: .gpu,
                deviceID: "gpu-die",
                displayName: "GPU Average",
                valueCelsius: reading.valueCelsius,
                source: .ioReportCandidate,
                rawKey: reading.statisticsField,
                attributes: attributes
            ),
        ]
    }

    private func capability(from sample: TemperatureSample, sessionID: UUID, timestamp: Date) -> TemperatureCapability {
        let isReadable = sample.quality == .valid
        return TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: .gpu,
            source: sample.source,
            supported: true,
            readable: isReadable,
            reasonCode: isReadable ? "ok" : sample.errorCode ?? "readFailed",
            reasonMessage: isReadable ? "ok" : "No readable GPU temperature from HID Sensors or SMC.",
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

    private func unavailableSamples(
        sessionID: UUID,
        timestamp: Date,
        ioAcceleratorCandidate: IOAcceleratorTemperatureReading?
    ) -> [TemperatureSample] {
        let platform = platformDetector.detect() ?? .intel
        var attributes = [
            "attemptedRawKeys": catalog.smcGPUKeys(for: platform).joined(separator: ","),
            "readerError": "temperatureUnavailable",
            "sourcePriority": "\(TemperatureSource.hidSensors.rawValue),\(TemperatureSource.smc.rawValue),\(TemperatureSource.ioReportCandidate.rawValue)",
        ]

        if let ioAcceleratorCandidate {
            attributes["candidateSourceDisabled"] = "IOAccelerator \(ioAcceleratorCandidate.statisticsField)"
        }

        return [
            unavailableSample(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.gpuHottest,
                displayName: "GPU Hottest",
                attributes: attributes
            ),
            unavailableSample(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: TemperatureMetricName.gpuAverage,
                displayName: "GPU Average",
                attributes: attributes
            ),
        ]
    }

    private func unavailableSample(
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
            domain: .gpu,
            deviceID: "gpu-die",
            displayName: displayName,
            quality: .readFailed,
            source: .smc,
            errorCode: "noReadableTemperature",
            attributes: attributes
        )
    }
}
