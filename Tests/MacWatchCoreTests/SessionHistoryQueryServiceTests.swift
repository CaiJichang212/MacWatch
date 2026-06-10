import Foundation
import XCTest
@testable import MacWatchCore

final class SessionHistoryQueryServiceTests: XCTestCase {
    func testHistoryRangeResolvesExpectedStartDates() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let now = startedAt.addingTimeInterval(7_200)

        XCTAssertEqual(
            TemperatureHistoryRange.fifteenMinutes.resolveStart(sessionStartedAt: startedAt, now: now),
            now.addingTimeInterval(-900)
        )
        XCTAssertEqual(
            TemperatureHistoryRange.oneHour.resolveStart(sessionStartedAt: startedAt, now: now),
            now.addingTimeInterval(-3_600)
        )
        XCTAssertEqual(
            TemperatureHistoryRange.sixHours.resolveStart(sessionStartedAt: startedAt, now: now),
            startedAt
        )
        XCTAssertEqual(
            TemperatureHistoryRange.allSession.resolveStart(sessionStartedAt: startedAt, now: now),
            startedAt
        )
    }

    func testHistoryRangeDoesNotStartBeforeSessionWhenSessionIsShorterThanRequestedWindow() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let now = startedAt.addingTimeInterval(300)

        XCTAssertEqual(
            TemperatureHistoryRange.oneHour.resolveStart(sessionStartedAt: startedAt, now: now),
            startedAt
        )
    }

    func testQueryReturnsEmptySeriesWhenNowIsEarlierThanSessionStart() throws {
        let service = SessionHistoryQueryService()
        let sessionID = UUID()
        let session = MonitoringSession(id: sessionID, startedAt: Date(timeIntervalSince1970: 1_000))

        let series = try service.makeSeries(
            session: session,
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            range: .allSession,
            now: Date(timeIntervalSince1970: 900),
            maxPoints: 2_000,
            samples: [],
            timelineEvents: []
        )

        XCTAssertTrue(series.samples.isEmpty)
        XCTAssertTrue(series.gaps.isEmpty)
        XCTAssertEqual(series.statistics, .empty)
    }

    func testQueryBuildsGapAwareSeriesAndStatistics() throws {
        let service = SessionHistoryQueryService()
        let sessionID = UUID()
        let session = MonitoringSession(id: sessionID, startedAt: Date(timeIntervalSince1970: 0))
        let base = Date(timeIntervalSince1970: 1_000)

        let samples = [
            try TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: base,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 51,
                source: .hidSensors
            ),
            try TemperatureSample.makeInvalid(
                sessionID: sessionID,
                timestamp: base.addingTimeInterval(10),
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
                timestamp: base.addingTimeInterval(20),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 61,
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
                message: "sleep"
            ),
            TimelineEvent(
                id: UUID(),
                sessionID: sessionID,
                eventType: .historyCleared,
                startedAt: base.addingTimeInterval(30),
                endedAt: base.addingTimeInterval(30),
                domain: nil,
                metricName: nil,
                reasonCode: "cleared",
                message: "cleared"
            ),
        ]

        let series = try service.makeSeries(
            session: session,
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            range: .oneHour,
            now: base.addingTimeInterval(40),
            maxPoints: 2_000,
            samples: samples,
            timelineEvents: gaps
        )

        XCTAssertEqual(series.metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(series.domain, .cpu)
        XCTAssertEqual(series.samples.count, 3)
        XCTAssertEqual(series.gaps.map(\.eventType), [.systemSleepStarted])
        XCTAssertEqual(series.statistics.validSampleCount, 2)
        XCTAssertEqual(series.statistics.maximumCelsius, 61)
        XCTAssertEqual(series.statistics.minimumCelsius, 51)
    }
}
