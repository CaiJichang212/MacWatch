import Foundation
import XCTest
@testable import MacWatchCore
@testable import StatsAdapter

final class DomainTemperatureProbeTests: XCTestCase {
    func testGPUProbePrefersHIDButDoesNotPromoteIOAcceleratorCandidateToValidTemperature() async {
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
        XCTAssertEqual(hidSamples.last?.valueCelsius, 57.0)

        let ioProbe = GPUTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            ioAcceleratorReader: FakeIOAcceleratorReader(reading: IOAcceleratorTemperatureReading(valueCelsius: 46.5, statisticsField: "Temperature(C)")),
            catalog: AppleSiliconSensorCatalog()
        )

        let ioSamples = await ioProbe.read(sessionID: sessionID, at: timestamp)
        XCTAssertEqual(ioSamples.first?.quality, .readFailed)
        XCTAssertNil(ioSamples.first?.valueCelsius)
        XCTAssertNotEqual(ioSamples.first?.source, .ioReportCandidate)
        XCTAssertEqual(ioSamples.first?.attributes["candidateSourceDisabled"], "IOAccelerator Temperature(C)")
    }

    func testGPUProbeComputesAverageAcrossStatsRecognizedSensors() async {
        let probe = GPUTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            hidReader: FakeGPUHIDReader(values: [
                "GPU MTR Temp Sensor0": 57.0,
                "GPU MTR Temp Sensor1": 51.0,
                "PMU tdie8": 80.0,
            ]),
            smcReader: FakeGPUSMCReader(values: [:]),
            ioAcceleratorReader: FakeIOAcceleratorReader(reading: nil),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 55))

        XCTAssertEqual(samples.map(\.metricName), [
            TemperatureMetricName.gpuHottest,
            TemperatureMetricName.gpuAverage,
        ])
        XCTAssertEqual(samples[0].valueCelsius, 57.0)
        XCTAssertEqual(samples[1].valueCelsius, 54.0)
        XCTAssertEqual(samples[0].attributes["rawKeys"], "GPU MTR Temp Sensor0,GPU MTR Temp Sensor1")
        XCTAssertEqual(samples[1].attributes["rawKeys"], "GPU MTR Temp Sensor0,GPU MTR Temp Sensor1")
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

        let gpuSample = await gpuProbe.read(sessionID: sessionID, at: timestamp).first
        let ssdSample = await ssdProbe.read(sessionID: sessionID, at: timestamp).first
        let batterySample = await batteryProbe.read(sessionID: sessionID, at: timestamp).first

        XCTAssertEqual(gpuSample?.attributes["sourcePriority"], "HID Sensors,SMC")
        XCTAssertNotNil(gpuSample?.attributes["attemptedRawKeys"])
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
