import Foundation
import XCTest
@testable import MacWatchCore
@testable import StatsAdapter

final class DomainTemperatureProbeTests: XCTestCase {
    func testGPUProbePrefersHIDThenFallsBackToIOAccelerator() async {
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
        XCTAssertEqual(hidSamples.first?.metricName, TemperatureMetricName.gpuHottest)
        XCTAssertEqual(hidSamples.first?.source, .hidSensors)
        XCTAssertEqual(hidSamples.first?.rawKey, "GPU MTR Temp Sensor0")

        let ioProbe = GPUTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            hidReader: FakeGPUHIDReader(values: [:]),
            smcReader: FakeGPUSMCReader(values: [:]),
            ioAcceleratorReader: FakeIOAcceleratorReader(reading: IOAcceleratorTemperatureReading(valueCelsius: 46.5, statisticsField: "Temperature(C)")),
            catalog: AppleSiliconSensorCatalog()
        )

        let ioSamples = await ioProbe.read(sessionID: sessionID, at: timestamp)
        XCTAssertEqual(ioSamples.first?.source, .ioReportCandidate)
        XCTAssertEqual(ioSamples.first?.valueCelsius, 46.5)
    }

    func testMemoryProbeReadsSMCProximityTemperature() async {
        let probe = MemoryTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            smcReader: FakeGPUSMCReader(values: ["Tm0p": 42.0, "Tm1p": 45.0]),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 60))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.metricName, TemperatureMetricName.memoryProximity)
        XCTAssertEqual(samples.first?.valueCelsius, 45.0)
        XCTAssertEqual(samples.first?.rawKey, "Tm1p")
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
        let memoryProbe = MemoryTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            smcReader: FakeGPUSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let batterySamples = await batteryProbe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 90))
        let memorySamples = await memoryProbe.read(sessionID: UUID(), at: Date(timeIntervalSince1970: 90))

        XCTAssertEqual(batterySamples.first?.quality, .readFailed)
        XCTAssertEqual(memorySamples.first?.quality, .readFailed)
        XCTAssertEqual(batterySamples.first?.metricName, TemperatureMetricName.battery)
        XCTAssertEqual(memorySamples.first?.metricName, TemperatureMetricName.memoryProximity)
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
        let memoryProbe = MemoryTemperatureProbe(
            platformDetector: FakeGPUPlatformDetector(platform: .m4),
            smcReader: FakeGPUSMCReader(values: [:]),
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
        let memorySample = await memoryProbe.read(sessionID: sessionID, at: timestamp).first
        let ssdSample = await ssdProbe.read(sessionID: sessionID, at: timestamp).first
        let batterySample = await batteryProbe.read(sessionID: sessionID, at: timestamp).first

        XCTAssertEqual(gpuSample?.attributes["sourcePriority"], "HID Sensors,SMC,IOReport Candidate")
        XCTAssertNotNil(gpuSample?.attributes["attemptedRawKeys"])
        XCTAssertEqual(memorySample?.attributes["sourcePriority"], "SMC")
        XCTAssertEqual(memorySample?.attributes["attemptedRawKeys"], "Tm0p,Tm1p,Tm2p")
        XCTAssertEqual(ssdSample?.attributes["sourcePriority"], "NVMe SMART,HID Sensors,SMC")
        XCTAssertEqual(ssdSample?.attributes["smartField"], "temperature")
        XCTAssertEqual(batterySample?.attributes["sourcePriority"], "Battery IORegistry,HID Sensors,SMC")
        XCTAssertEqual(batterySample?.attributes["ioRegistryProperty"], "Temperature")
    }

    func testDetectMarksSupportedButUnreadableWhenDomainProbeCannotReadCurrentValue() async {
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
        XCTAssertEqual(capability.reasonCode, "readFailed")
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

    func readInternalTemperature() -> NVMeSMARTTemperatureReading? {
        reading
    }
}

private struct FakeBatteryReader: BatteryTemperatureReadingSource {
    let reading: BatteryTemperatureReading?

    func readTemperature() -> BatteryTemperatureReading? {
        reading
    }
}
