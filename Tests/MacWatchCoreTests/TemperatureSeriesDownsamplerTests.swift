import Foundation
import XCTest
@testable import MacWatchCore

final class TemperatureSeriesDownsamplerTests: XCTestCase {
    func testDownsamplerLimitsPointCountAndPreservesPeak() throws {
        let downsampler = TemperatureSeriesDownsampler()
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_000)
        var samples: [TemperatureSample] = []

        for index in 0..<2_500 {
            let value = index == 1_250 ? 99.5 : Double(index % 70) + 20
            samples.append(
                try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: base.addingTimeInterval(TimeInterval(index)),
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu",
                    displayName: "CPU",
                    valueCelsius: value,
                    source: .hidSensors
                )
            )
        }

        let reduced = downsampler.reduce(
            samples: samples,
            gaps: [],
            maxPoints: 2_000
        )

        XCTAssertLessThanOrEqual(reduced.count, 2_000)
        XCTAssertTrue(reduced.contains(where: { $0.valueCelsius == 99.5 }))
        XCTAssertEqual(reduced.first?.timestamp, samples.first?.timestamp)
        XCTAssertEqual(reduced.last?.timestamp, samples.last?.timestamp)
    }

    func testDownsamplerTreatsGapAsSegmentBoundary() throws {
        let downsampler = TemperatureSeriesDownsampler()
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_000)
        let samples = [
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 50,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(10),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 55,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(20),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 60,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(30),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 62,
                source: .hidSensors
            ),
        ]
        let gaps = [
            TimelineEvent(
                id: UUID(),
                sessionID: sessionID,
                eventType: .systemSleepStarted,
                startedAt: base.addingTimeInterval(12),
                endedAt: base.addingTimeInterval(18),
                domain: .cpu,
                metricName: TemperatureMetricName.cpuHottest,
                reasonCode: "sleep",
                message: nil
            )
        ]

        let segments = downsampler.validSegments(
            samples: samples,
            gaps: gaps
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].map(\.timestamp), [base, base.addingTimeInterval(10)])
        XCTAssertEqual(segments[1].map(\.timestamp), [base.addingTimeInterval(20), base.addingTimeInterval(30)])
    }

    func testDownsamplerStartsNewSegmentAtGapEndBoundary() throws {
        let downsampler = TemperatureSeriesDownsampler()
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_000)
        let samples = [
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 50,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(18),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 55,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(25),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 60,
                source: .hidSensors
            ),
        ]
        let gaps = [
            TimelineEvent(
                id: UUID(),
                sessionID: sessionID,
                eventType: .systemSleepStarted,
                startedAt: base.addingTimeInterval(12),
                endedAt: base.addingTimeInterval(18),
                domain: .cpu,
                metricName: TemperatureMetricName.cpuHottest,
                reasonCode: "sleep",
                message: nil
            )
        ]

        let segments = downsampler.validSegments(samples: samples, gaps: gaps)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].map(\.timestamp), [base])
        XCTAssertEqual(segments[1].map(\.timestamp), [base.addingTimeInterval(18), base.addingTimeInterval(25)])
    }

    func testDownsamplerPreservesPeakAcrossLaterSegmentWhenBudgetIsTight() throws {
        let downsampler = TemperatureSeriesDownsampler()
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_000)
        let samples = [
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 10,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(5),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 20,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(10),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 30,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(20),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 40,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(25),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 99,
                source: .hidSensors
            ),
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(30),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 50,
                source: .hidSensors
            ),
        ]
        let gaps = [
            TimelineEvent(
                id: UUID(),
                sessionID: sessionID,
                eventType: .systemSleepStarted,
                startedAt: base.addingTimeInterval(12),
                endedAt: base.addingTimeInterval(18),
                domain: .cpu,
                metricName: TemperatureMetricName.cpuHottest,
                reasonCode: "sleep",
                message: nil
            )
        ]

        let reduced = downsampler.reduce(samples: samples, gaps: gaps, maxPoints: 4)

        XCTAssertLessThanOrEqual(reduced.count, 4)
        XCTAssertTrue(reduced.contains(where: { $0.valueCelsius == 99 }))
        XCTAssertEqual(reduced.first?.timestamp, base)
        XCTAssertEqual(reduced.last?.timestamp, base.addingTimeInterval(30))
    }
}
