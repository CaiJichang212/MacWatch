import Foundation
import XCTest
@testable import MacWatchCore

final class SQLiteSessionHistoryRepositoryTests: XCTestCase {
    func testRangeQueryReturnsSamplesGapsAndStatistics() throws {
        let repository = try makeRepository()
        let session = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 0))
        try repository.beginSession(session, clearingPreviousHistory: true)

        let base = Date(timeIntervalSince1970: 1_000)
        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: base,
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 72,
                source: .hidSensors
            )
        )
        try repository.insertSample(
            TemperatureSample.makeInvalid(
                sessionID: session.id,
                timestamp: base.addingTimeInterval(10),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                quality: .readFailed,
                source: .hidSensors,
                errorCode: "readFailed"
            )
        )
        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: base.addingTimeInterval(20),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 66,
                source: .hidSensors
            )
        )
        try repository.insertTimelineEvent(
            TimelineEvent(
                id: UUID(),
                sessionID: session.id,
                eventType: .probeReadFailed,
                startedAt: base.addingTimeInterval(10),
                endedAt: base.addingTimeInterval(10),
                domain: .cpu,
                metricName: TemperatureMetricName.cpuHottest,
                reasonCode: "readFailed",
                message: "readFailed"
            )
        )

        let series = try repository.query(
            sessionID: session.id,
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            range: .oneHour,
            now: base.addingTimeInterval(30),
            maxPoints: 2_000
        )

        XCTAssertEqual(series.domain, .cpu)
        XCTAssertEqual(series.metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(series.samples.count, 3)
        XCTAssertTrue(series.samples.contains { $0.quality == TemperatureQuality.readFailed })
        XCTAssertEqual(series.gaps.map(\.eventType), [TimelineEventType.probeReadFailed])
        XCTAssertEqual(series.statistics.validSampleCount, 2)
        XCTAssertEqual(series.statistics.maximumCelsius, 72)
        XCTAssertEqual(series.statistics.minimumCelsius, 66)
    }

    func testClearCurrentSessionHistoryRemovesOldSamplesAndLeavesHistoryClearedEvent() throws {
        let repository = try makeRepository()
        let session = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 0))
        try repository.beginSession(session, clearingPreviousHistory: true)
        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: 1_000),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 72,
                source: .hidSensors
            )
        )

        try repository.clearCurrentSessionHistory(at: Date(timeIntervalSince1970: 2_000))

        let series = try repository.query(
            sessionID: session.id,
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            range: .allSession,
            now: Date(timeIntervalSince1970: 2_100),
            maxPoints: 2_000
        )
        let events = try repository.timelineEvents(sessionID: session.id)

        XCTAssertTrue(series.samples.isEmpty)
        XCTAssertEqual(series.statistics.validSampleCount, 0)
        XCTAssertEqual(events.map(\.eventType), [TimelineEventType.historyCleared])
    }

    func testBeginningNewSessionRemovesPreviousSessionQueryVisibility() throws {
        let repository = try makeRepository()
        let first = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 0))
        try repository.beginSession(first, clearingPreviousHistory: true)
        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: first.id,
                timestamp: Date(timeIntervalSince1970: 1_000),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 72,
                source: .hidSensors
            )
        )

        let second = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 2_000))
        try repository.beginSession(second, clearingPreviousHistory: true)

        let firstSeries = try repository.query(
            sessionID: first.id,
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            range: .allSession,
            now: Date(timeIntervalSince1970: 2_100),
            maxPoints: 2_000
        )

        XCTAssertTrue(firstSeries.samples.isEmpty)
        XCTAssertEqual(try repository.currentSession()?.id, second.id)
    }

    private func makeRepository() throws -> SQLiteSessionHistoryRepository {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = SQLiteSessionHistoryStore(databaseURL: databaseURL)
        try store.initialize()
        return SQLiteSessionHistoryRepository(store: store)
    }
}
