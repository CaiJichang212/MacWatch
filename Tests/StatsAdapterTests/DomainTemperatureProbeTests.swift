import Foundation
import XCTest
@testable import MacWatchCore
@testable import StatsAdapter

final class DomainTemperatureProbeTests: XCTestCase {
    func testGPUProbePrefersStatsSensorsThenUsesIOAcceleratorFallback() async {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 50)
        let hidProbe = GPUTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            hidReader: FakeGPUHIDReader(values: ["GPU MTR Temp Sensor0": 57.0]),
            smcReader: FakeGPUSMCReader(values: ["Tg0G": 49.0]),
            ioAcceleratorReader: FakeIOAcceleratorReader(reading: IOAcceleratorTemperatureReading(valueCelsius: 44.0, statisticsField: "Temperature(C)")),
            catalog: AppleSiliconSensorCatalog()
        )

        let hidSamples = await hidProbe.read(sessionID: sessionID, at: timestamp)
        XCTAssertEqual(hidSamples.map(\.metricName), [
            TemperatureMetricName.gpuHottest,
            TemperatureMetricName.gpuAverage,
        ])
        XCTAssertEqual(hidSamples.first?.source, .hidSensors)
        XCTAssertEqual(hidSamples.first?.rawKey, "GPU MTR Temp Sensor0")
        XCTAssertEqual(hidSamples.last?.valueCelsius, 53.0)
        XCTAssertEqual(hidSamples.first?.attributes["sourceSet"], "HID Sensors,SMC")
        XCTAssertEqual(hidSamples.last?.attributes["sourceSet"], "HID Sensors,SMC")

        let ioProbe = GPUTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            ioAcceleratorReader: FakeIOAcceleratorReader(reading: IOAcceleratorTemperatureReading(valueCelsius: 46.5, statisticsField: "Temperature(C)")),
            catalog: AppleSiliconSensorCatalog()
        )

        let ioSamples = await ioProbe.read(sessionID: sessionID, at: timestamp)
        XCTAssertEqual(ioSamples.map(\.metricName), [
            TemperatureMetricName.gpuHottest,
            TemperatureMetricName.gpuAverage,
        ])
        XCTAssertEqual(ioSamples.map(\.quality), [.valid, .valid])
        XCTAssertEqual(ioSamples.map(\.source), [.ioReportCandidate, .ioReportCandidate])
        XCTAssertEqual(ioSamples[0].rawKey, "Temperature(C)")
        XCTAssertEqual(ioSamples[0].valueCelsius, 46.5)
        XCTAssertEqual(ioSamples[1].valueCelsius, 46.5)
        XCTAssertEqual(ioSamples[0].attributes["sourcePriority"], "HID Sensors,SMC,IOReport Candidate")
    }

    func testGPUProbeComputesAverageAcrossStatsRecognizedSensors() async {
        let probe = GPUTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            hidReader: FakeGPUHIDReader(values: [
                "GPU MTR Temp Sensor0": 57.0,
                "GPU MTR Temp Sensor1": 51.0,
                "PMU tdie8": 80.0,
            ]),
            smcReader: FakeGPUSMCReader(values: [
                "Tg0G": 52.0,
            ]),
            ioAcceleratorReader: FakeIOAcceleratorReader(reading: nil),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 55))

        XCTAssertEqual(samples.map(\.metricName), [
            TemperatureMetricName.gpuHottest,
            TemperatureMetricName.gpuAverage,
        ])
        XCTAssertEqual(samples[0].valueCelsius, 57.0)
        XCTAssertEqual(samples[1].valueCelsius, 160.0 / 3.0)
        XCTAssertEqual(samples[0].attributes["rawKeys"], "GPU MTR Temp Sensor0,GPU MTR Temp Sensor1,Tg0G")
        XCTAssertEqual(samples[1].attributes["rawKeys"], "GPU MTR Temp Sensor0,GPU MTR Temp Sensor1,Tg0G")
        XCTAssertEqual(samples[0].attributes["sourceSet"], "HID Sensors,SMC")
        XCTAssertEqual(samples[1].attributes["sourceSet"], "HID Sensors,SMC")
    }

    func testSSDProbeUsesNVMeSMARTWhenAvailable() async {
        let probe = SSDTemperatureProbe(
            nvmeReader: FakeNVMeReader(reading: NVMeSMARTTemperatureReading(valueCelsius: 39.5, smartField: "temperature")),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 70))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.metricName, TemperatureMetricName.ssdInternal)
        XCTAssertEqual(samples.first?.source, .nvmeSMART)
        XCTAssertEqual(samples.first?.valueCelsius, 39.5)
    }

    func testSSDProbeFallsBackToNANDHIDWhenInternalSMARTDiskIsAbsent() async {
        let probe = SSDTemperatureProbe(
            nvmeReader: FakeNVMeReader(reading: nil, isPresent: false),
            snapshotProvider: FakeStatsSnapshotProvider(snapshot: makeSnapshot([
                ("NAND CH0 temp", 38.0, .hidSensors, .ssd, false),
                ("TH0x", 41.0, .smc, .ssd, false),
                ("PMU tdie8", 90.0, .hidSensors, .sensor, false),
            ]))
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 75))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.quality, .valid)
        XCTAssertEqual(samples.first?.source, .hidSensors)
        XCTAssertEqual(samples.first?.rawKey, "NAND CH0 temp")
        XCTAssertEqual(samples.first?.valueCelsius, 38.0)
        XCTAssertEqual(samples.first?.attributes["sourcePriority"], "NVMe SMART,HID Sensors,SMC")
        XCTAssertEqual(samples.first?.attributes["smartStatus"], "internalSMARTDiskUnavailable")
    }

    func testBatteryProbeUsesBatteryIORegistryReading() async {
        let probe = BatteryTemperatureProbe(
            batteryReader: FakeBatteryReader(reading: BatteryTemperatureReading(valueCelsius: 31.5, ioRegistryProperty: "Temperature")),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 80))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.metricName, TemperatureMetricName.battery)
        XCTAssertEqual(samples.first?.source, .batteryIORegistry)
        XCTAssertEqual(samples.first?.valueCelsius, 31.5)
    }

    func testBatteryProbeFallsBackToSnapshotBatteryReadingWhenIORegistryIsUnreadable() async {
        let probe = BatteryTemperatureProbe(
            batteryReader: FakeBatteryReader(reading: nil),
            snapshotProvider: FakeStatsSnapshotProvider(snapshot: makeSnapshot([
                ("gas gauge battery", 32.0, .hidSensors, .battery, false),
                ("TB1T", 34.0, .smc, .battery, false),
                ("PMU2 tcal", 52.0, .hidSensors, .sensor, false),
            ]))
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 82))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.quality, .valid)
        XCTAssertEqual(samples.first?.source, .smc)
        XCTAssertEqual(samples.first?.rawKey, "TB1T")
        XCTAssertEqual(samples.first?.valueCelsius, 34.0)
        XCTAssertEqual(samples.first?.attributes["sourceSet"], "HID Sensors,SMC")
    }

    func testSystemProbeUsesStatsSystemSMCCatalogKeys() async {
        let probe = SystemTemperatureProbe(
            snapshotProvider: FakeStatsSnapshotProvider(snapshot: makeSnapshot([
                ("TW0P", 42.0, .smc, .system, false),
                ("TL0P", 37.0, .smc, .system, false),
                ("PMU2 tcal", 52.0, .hidSensors, .sensor, false),
            ]))
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 85))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.quality, .valid)
        XCTAssertEqual(samples.first?.source, .smc)
        XCTAssertEqual(samples.first?.rawKey, "TW0P")
        XCTAssertEqual(samples.first?.valueCelsius, 42.0)
        XCTAssertEqual(samples.first?.attributes["rawKeys"], "TL0P,TW0P")
    }

    func testSystemProbeDoesNotTreatPMUOrUnknownSensorsAsSystemTemperature() async {
        let probe = SystemTemperatureProbe(
            snapshotProvider: FakeStatsSnapshotProvider(snapshot: makeSnapshot([
                ("PMU2 tcal", 52.0, .hidSensors, .sensor, false),
                ("TZZZ", 45.0, .smc, .sensor, false),
            ]))
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 86))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.quality, .readFailed)
        XCTAssertNil(samples.first?.rawKey)
        XCTAssertEqual(samples.first?.attributes["availableRawKeys"], "PMU2 tcal,TZZZ")
    }

    func testSensorProbeUsesPMUAndUnknownSMCReadingsFromSnapshot() async {
        let probe = SensorTemperatureProbe(
            snapshotProvider: FakeStatsSnapshotProvider(snapshot: makeSnapshot([
                ("PMU2 tcal", 52.0, .hidSensors, .sensor, false),
                ("TZZZ", 45.0, .smc, .sensor, false),
                ("TW0P", 42.0, .smc, .system, false),
            ]))
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 87))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.quality, .valid)
        XCTAssertEqual(samples.first?.source, .hidSensors)
        XCTAssertEqual(samples.first?.rawKey, "PMU2 tcal")
        XCTAssertEqual(samples.first?.valueCelsius, 52.0)
        XCTAssertEqual(samples.first?.attributes["rawKeys"], "PMU2 tcal,TZZZ")
        XCTAssertEqual(samples.first?.attributes["sourceSet"], "HID Sensors,SMC")
    }

    func testSensorProbeKeepsSourceFromHottestReading() async {
        let probe = SensorTemperatureProbe(
            snapshotProvider: FakeStatsSnapshotProvider(snapshot: makeSnapshot([
                ("PMU2 tcal", 52.0, .hidSensors, .sensor, false),
                ("TA0P", 60.0, .smc, .sensor, false),
            ]))
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 88))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.quality, .valid)
        XCTAssertEqual(samples.first?.source, .smc)
        XCTAssertEqual(samples.first?.rawKey, "TA0P")
        XCTAssertEqual(samples.first?.valueCelsius, 60.0)
    }

    func testProbesReturnStatusSamplesWhenSourceIsUnavailable() async {
        let batteryProbe = BatteryTemperatureProbe(
            batteryReader: FakeBatteryReader(reading: nil),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let batterySamples = await batteryProbe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 90))

        XCTAssertEqual(batterySamples.first?.quality, .readFailed)
        XCTAssertEqual(batterySamples.first?.metricName, TemperatureMetricName.battery)
    }

    func testUnavailableSamplesCarrySourceSpecificAttributes() async {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 95)
        let gpuProbe = GPUTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            ioAcceleratorReader: FakeIOAcceleratorReader(reading: nil),
            catalog: AppleSiliconSensorCatalog()
        )
        let ssdProbe = SSDTemperatureProbe(
            nvmeReader: FakeNVMeReader(reading: nil),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )
        let batteryProbe = BatteryTemperatureProbe(
            batteryReader: FakeBatteryReader(reading: nil),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let gpuSamples = await gpuProbe.read(sessionID: sessionID, at: timestamp)
        let ssdSample = await ssdProbe.read(sessionID: sessionID, at: timestamp).first
        let batterySample = await batteryProbe.read(sessionID: sessionID, at: timestamp).first

        XCTAssertEqual(gpuSamples.map(\.metricName), [
            TemperatureMetricName.gpuHottest,
            TemperatureMetricName.gpuAverage,
        ])
        XCTAssertTrue(gpuSamples.allSatisfy { $0.attributes["sourcePriority"] == "HID Sensors,SMC,IOReport Candidate" })
        XCTAssertTrue(gpuSamples.allSatisfy { $0.attributes["attemptedRawKeys"] != nil })
        XCTAssertEqual(ssdSample?.attributes["sourcePriority"], "NVMe SMART,HID Sensors,SMC")
        XCTAssertEqual(ssdSample?.attributes["smartField"], "temperature")
        XCTAssertEqual(batterySample?.attributes["sourcePriority"], "Battery IORegistry,HID Sensors,SMC")
        XCTAssertEqual(batterySample?.attributes["ioRegistryProperty"], "Temperature")
    }

    func testDetectMarksSupportedButUnreadableWithSpecificReasonWhenDomainProbeCannotReadCurrentValue() async {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 96)
        let batteryProbe = BatteryTemperatureProbe(
            batteryReader: FakeBatteryReader(reading: nil),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let capability = await batteryProbe.detect(sessionID: sessionID, at: timestamp)

        XCTAssertTrue(capability.supported)
        XCTAssertFalse(capability.readable)
        XCTAssertEqual(capability.reasonCode, "noReadableTemperature")
        XCTAssertEqual(capability.reasonMessage, "No readable battery temperature from Battery IORegistry, HID Sensors, or SMC.")
    }

    func testBatteryCapabilityMarksUnsupportedWhenBatteryServiceIsAbsent() async {
        let probe = BatteryTemperatureProbe(
            batteryReader: FakeBatteryReader(reading: nil, isPresent: false),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let capability = await probe.detect(sessionID: UUID(), at: Date(timeIntervalSince1970: 96.5))

        XCTAssertFalse(capability.supported)
        XCTAssertFalse(capability.readable)
        XCTAssertEqual(capability.reasonCode, "batteryServiceUnavailable")
    }

    func testUnavailableDomainCapabilitiesExposeSpecificNoReadableTemperatureReason() async {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 97)
        let ssdProbe = SSDTemperatureProbe(
            nvmeReader: FakeNVMeReader(reading: nil),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let ssd = await ssdProbe.detect(sessionID: sessionID, at: timestamp)

        XCTAssertTrue(ssd.supported)
        XCTAssertFalse(ssd.readable)
        XCTAssertEqual(ssd.reasonCode, "noReadableTemperature")
        XCTAssertEqual(ssd.reasonMessage, "No readable internal SSD temperature from NVMe SMART, HID Sensors, or SMC.")
    }

    func testGPUCapabilityFailureMentionsIOReportCandidateFallback() async {
        let probe = GPUTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            snapshotProvider: FakeStatsSnapshotProvider(snapshot: makeSnapshot([])),
            ioAcceleratorReader: FakeIOAcceleratorReader(reading: nil)
        )

        let capability = await probe.detect(sessionID: UUID(), at: Date(timeIntervalSince1970: 97.5))

        XCTAssertFalse(capability.readable)
        XCTAssertEqual(capability.reasonCode, "noReadableTemperature")
        XCTAssertEqual(capability.reasonMessage, "No readable GPU temperature from HID Sensors, SMC, or IOReport Candidate.")
    }

    func testSSDCapabilityMarksUnsupportedWhenInternalSMARTDiskIsAbsent() async {
        let probe = SSDTemperatureProbe(
            nvmeReader: FakeNVMeReader(reading: nil, isPresent: false),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let capability = await probe.detect(sessionID: UUID(), at: Date(timeIntervalSince1970: 98))

        XCTAssertFalse(capability.supported)
        XCTAssertFalse(capability.readable)
        XCTAssertEqual(capability.reasonCode, "internalSMARTDiskUnavailable")
    }

}

private func makeSnapshot(
    _ readings: [(String, Double, TemperatureSource, TemperatureDomain, Bool)],
    platform: ApplePlatform? = .m4
) -> StatsTemperatureSensorSnapshot {
    StatsTemperatureSensorSnapshot(
        readings: readings.map { rawKey, value, source, domain, averageCandidate in
            StatsTemperatureSensorReading(
                rawKey: rawKey,
                displayName: rawKey,
                valueCelsius: value,
                source: source,
                domain: domain,
                averageCandidate: averageCandidate
            )
        },
        availableHIDKeys: readings.filter { $0.2 == .hidSensors }.map(\.0).sorted(),
        availableSMCKeys: readings.filter { $0.2 == .smc }.map(\.0).sorted(),
        detectedPlatform: platform
    )
}

private struct FakeStatsSnapshotProvider: StatsTemperatureSensorSnapshotProviding {
    let snapshot: StatsTemperatureSensorSnapshot

    func readSnapshot() -> StatsTemperatureSensorSnapshot {
        snapshot
    }
}

private struct FakeGPUPlatformDetector: ApplePlatformDetecting {
    let platform: ApplePlatform?

    func detect() -> ApplePlatform? {
        platform
    }
}

private struct FakeGPUHIDReader: AppleSiliconTemperatureReading {
    let values: [String: Double]

    func readTemperatureValues() -> [String: Double] {
        values
    }
}

private struct FakeGPUSMCReader: SMCValueReading {
    let values: [String: Double]

    func getAllKeys() -> [String] {
        Array(values.keys)
    }

    func getValue(_ key: String) -> Double? {
        values[key]
    }
}

private struct FakeIOAcceleratorReader: IOAcceleratorTemperatureReadingSource {
    let reading: IOAcceleratorTemperatureReading?

    func readTemperature() -> IOAcceleratorTemperatureReading? {
        reading
    }
}

private struct FakeNVMeReader: NVMeSMARTTemperatureReadingSource {
    let reading: NVMeSMARTTemperatureReading?
    var isPresent = true

    func readInternalTemperature() -> NVMeSMARTTemperatureReading? {
        reading
    }

    func hasInternalSMARTCapableDisk() -> Bool {
        isPresent
    }
}

private struct FakeBatteryReader: BatteryTemperatureReadingSource {
    let reading: BatteryTemperatureReading?
    var isPresent = true

    func readTemperature() -> BatteryTemperatureReading? {
        reading
    }

    func hasBatteryService() -> Bool {
        isPresent
    }
}
