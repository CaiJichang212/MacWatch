import Foundation
import XCTest
@testable import MacWatchCore

final class TemperatureSeriesStatisticsTests: XCTestCase {
    func testStatisticsUseOnlyValidSamplesAndKeepEarliestPeakTimestamp() throws {
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 100)
        let samples = [
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 42,
                source: .hidSensors
            ),
            try TemperatureSample.makeInvalid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(5),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                quality: .readFailed,
                source: .hidSensors,
                errorCode: "readFailed"
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(10),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 81,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(15),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 57,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(20),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 81,
                source: .hidSensors
            ),
        ]

        let statistics = TemperatureSeriesStatistics.compute(samples: samples)

        XCTAssertEqual(statistics.validSampleCount, 4)
        XCTAssertEqual(statistics.minimumCelsius, 42)
        XCTAssertEqual(statistics.maximumCelsius, 81)
        XCTAssertEqual(statistics.averageCelsius ?? 0, 65.25, accuracy: 0.0001)
        XCTAssertEqual(statistics.peakAt, base.addingTimeInterval(10))
    }

    func testStatisticsAreEmptyWhenThereAreNoValidSamples() throws {
        let sessionID = UUID()
        let sample = try TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: Date(timeIntervalSince1970: 10),
            metricName: TemperatureMetricName.cpuHottest,
            domain: .cpu,
            deviceID: "cpu",
            displayName: "CPU",
            quality: .unsupported,
            source: .hidSensors,
            errorCode: "unsupported"
        )

        let statistics = TemperatureSeriesStatistics.compute(samples: [sample])

        XCTAssertEqual(statistics.validSampleCount, 0)
        XCTAssertNil(statistics.minimumCelsius)
        XCTAssertNil(statistics.maximumCelsius)
        XCTAssertNil(statistics.averageCelsius)
        XCTAssertNil(statistics.peakAt)
    }
}
