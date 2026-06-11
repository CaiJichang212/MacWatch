import Foundation
import XCTest
@testable import MacWatchCore
@testable import StatsAdapter

final class CPUTemperatureProbeTests: XCTestCase {
    func testProbePrefersValidHIDSensorsOverSMCFallback() async throws {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 10)
        let probe = CPUTemperatureProbe(
            platformDetector: FakeApplePlatformDetector(platform: .m4),
            hidReader: FakeAppleSiliconTemperatureReader(values: [
                "pACC MTR Temp Sensor0": 61.0,
                "eACC MTR Temp Sensor1": 54.0,
            ]),
            smcReader: FakeSMCReader(values: [
                "Te05": 48.0,
                "Tp01": 49.0,
            ]),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: sessionID, at: timestamp)

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(samples[0].source, .hidSensors)
        XCTAssertEqual(samples[0].rawKey, "pACC MTR Temp Sensor0")
        XCTAssertEqual(samples[0].valueCelsius, 61.0)
        XCTAssertEqual(samples[0].attributes["rawKeys"], "pACC MTR Temp Sensor0,eACC MTR Temp Sensor1")
        XCTAssertEqual(samples[1].metricName, TemperatureMetricName.cpuAverage)
        XCTAssertEqual(samples[1].valueCelsius, 57.5)
    }

    func testProbeFallsBackToSMCWhenHIDHasNoValidValues() async {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 20)
        let probe = CPUTemperatureProbe(
            platformDetector: FakeApplePlatformDetector(platform: .m4),
            hidReader: FakeAppleSiliconTemperatureReader(values: [
                "pACC MTR Temp Sensor0": .nan,
                "eACC MTR Temp Sensor1": -1.0,
            ]),
            smcReader: FakeSMCReader(values: [
                "Te05": 50.0,
                "Tp01": 58.0,
                "Tp05": 55.0,
            ]),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: sessionID, at: timestamp)

        XCTAssertEqual(samples.first?.metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(samples.first?.source, .smc)
        XCTAssertEqual(samples.first?.rawKey, "Tp01")
        XCTAssertEqual(samples.first?.valueCelsius, 58.0)
    }

    func testProbeDoesNotTreatPMUHIDSensorsAsCPUTemperature() async {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 25)
        let probe = CPUTemperatureProbe(
            platformDetector: FakeApplePlatformDetector(platform: .m4),
            hidReader: FakeAppleSiliconTemperatureReader(values: [
                "PMU tdie8": 61.0,
                "PMU2 tdie8": 58.0,
            ]),
            smcReader: FakeSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: sessionID, at: timestamp)

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(samples[0].quality, .readFailed)
        XCTAssertNil(samples[0].valueCelsius)
        XCTAssertNil(samples[0].rawKey)
        XCTAssertEqual(samples[1].metricName, TemperatureMetricName.cpuAverage)
        XCTAssertEqual(samples[1].quality, .readFailed)
        XCTAssertNil(samples[1].valueCelsius)
        XCTAssertNil(samples[1].rawKey)
    }

    func testProbeReturnsReadFailedWhenAllSourcesAreUnavailable() async {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 30)
        let probe = CPUTemperatureProbe(
            platformDetector: FakeApplePlatformDetector(platform: .m4),
            hidReader: FakeAppleSiliconTemperatureReader(values: [:]),
            smcReader: FakeSMCReader(values: [:]),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: sessionID, at: timestamp)

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(samples[0].quality, .readFailed)
        XCTAssertNil(samples[0].rawKey)
        XCTAssertNotNil(samples[0].attributes["attemptedRawKeys"])
        XCTAssertFalse(samples[0].attributes["attemptedRawKeys"]?.isEmpty ?? true)
        XCTAssertEqual(samples[1].metricName, TemperatureMetricName.cpuAverage)
        XCTAssertEqual(samples[1].quality, .readFailed)
        XCTAssertNil(samples[1].rawKey)
        XCTAssertEqual(samples[1].attributes["attemptedRawKeys"], samples[0].attributes["attemptedRawKeys"])
    }

    func testProbeRejectsOutOfRangeTemperatureValues() async {
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 40)
        let probe = CPUTemperatureProbe(
            platformDetector: FakeApplePlatformDetector(platform: .m4),
            hidReader: FakeAppleSiliconTemperatureReader(values: [
                "pACC MTR Temp Sensor0": 110.0,
                "eACC MTR Temp Sensor1": -1.0,
            ]),
            smcReader: FakeSMCReader(values: [
                "Te05": .nan,
                "Tp01": 109.9,
            ]),
            catalog: AppleSiliconSensorCatalog()
        )

        let samples = await probe.read(sessionID: sessionID, at: timestamp)

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(samples[0].quality, .valid)
        XCTAssertEqual(samples[0].source, .smc)
        XCTAssertEqual(samples[0].rawKey, "Tp01")
        XCTAssertEqual(samples[0].valueCelsius, 109.9)
        XCTAssertEqual(samples[1].metricName, TemperatureMetricName.cpuAverage)
        XCTAssertEqual(samples[1].valueCelsius, 109.9)
    }
}

private struct FakeApplePlatformDetector: ApplePlatformDetecting {
    let platform: ApplePlatform?

    func detect() -> ApplePlatform? {
        platform
    }
}

private struct FakeAppleSiliconTemperatureReader: AppleSiliconTemperatureReading {
    let values: [String: Double]

    func readTemperatureValues() -> [String: Double] {
        values
    }
}

private struct FakeSMCReader: SMCValueReading {
    let values: [String: Double]

    func getAllKeys() -> [String] {
        Array(values.keys)
    }

    func getValue(_ key: String) -> Double? {
        values[key]
    }
}
