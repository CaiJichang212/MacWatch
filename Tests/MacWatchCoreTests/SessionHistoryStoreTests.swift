import Foundation
import XCTest
@testable import MacWatchCore

final class SessionHistoryStoreTests: XCTestCase {
    func testInitializeIsIdempotentForExistingDatabase() throws {
        let databaseURL = makeDatabaseURL()
        let firstStore = SQLiteSessionHistoryStore(databaseURL: databaseURL)
        try firstStore.initialize()

        let secondStore = SQLiteSessionHistoryStore(databaseURL: databaseURL)
        XCTAssertNoThrow(try secondStore.initialize())
    }

    func testInitializeAndPersistSessionAndSamples() throws {
        let databaseURL = makeDatabaseURL()
        let store = SQLiteSessionHistoryStore(databaseURL: databaseURL)
        try store.initialize()

        let session = MonitoringSession(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 10),
            appVersion: "1.0",
            model: "MacBookAir",
            chip: "M4",
            osVersion: "14.0"
        )
        try store.replaceWithNewSession(session)
        try store.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: 11),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 55,
                source: .hidSensors,
                attributes: ["sensor": "die0"]
            )
        )

        XCTAssertEqual(try store.currentSession()?.id, session.id)

        let samples = try store.samples(
            matching: TemperatureQuery(
                sessionID: session.id,
                domains: [.cpu],
                metricNames: [TemperatureMetricName.cpuHottest],
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 20),
                maxPoints: 50
            )
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.valueCelsius, 55)
        XCTAssertEqual(samples.first?.attributes["sensor"], "die0")
    }

    func testReplaceWithNewSessionClearsPreviousHistory() throws {
        let databaseURL = makeDatabaseURL()
        let store = SQLiteSessionHistoryStore(databaseURL: databaseURL)
        try store.initialize()

        let first = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 10))
        try store.replaceWithNewSession(first)
        try store.insertSample(
            TemperatureSample.makeValid(
                sessionID: first.id,
                timestamp: Date(timeIntervalSince1970: 11),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 55,
                source: .hidSensors
            )
        )

        let second = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 20))
        try store.replaceWithNewSession(second)

        XCTAssertEqual(try store.currentSession()?.id, second.id)
        XCTAssertTrue(
            try store.samples(
                matching: TemperatureQuery(
                    sessionID: first.id,
                    domains: [.cpu],
                    metricNames: [TemperatureMetricName.cpuHottest],
                    start: Date(timeIntervalSince1970: 0),
                    end: Date(timeIntervalSince1970: 30),
                    maxPoints: 50
                )
            ).isEmpty
        )
    }

    func testInvalidSamplesRoundTripWithNilValueAndTimelineUpdate() throws {
        let databaseURL = makeDatabaseURL()
        let store = SQLiteSessionHistoryStore(databaseURL: databaseURL)
        try store.initialize()

        let session = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 10))
        try store.replaceWithNewSession(session)

        try store.insertSample(
            TemperatureSample.makeInvalid(
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: 11),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                quality: .readFailed,
                source: .hidSensors,
                errorCode: "readFailed"
            )
        )

        let eventID = UUID()
        try store.insertTimelineEvent(
            TimelineEvent(
                id: eventID,
                sessionID: session.id,
                eventType: .systemSleepStarted,
                startedAt: Date(timeIntervalSince1970: 12),
                endedAt: nil,
                domain: nil,
                metricName: nil,
                reasonCode: "sleep",
                message: "sleep"
            )
        )
        try store.updateTimelineEvent(id: eventID, endedAt: Date(timeIntervalSince1970: 20))

        let samples = try store.samples(
            matching: TemperatureQuery(
                sessionID: session.id,
                domains: [.cpu],
                metricNames: [TemperatureMetricName.cpuHottest],
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 30),
                maxPoints: 50
            )
        )
        let events = try store.timelineEvents(
            sessionID: session.id,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertNil(samples.first?.valueCelsius)
        XCTAssertEqual(samples.first?.quality, .readFailed)
        XCTAssertEqual(events.map(\.eventType), [TimelineEventType.systemSleepStarted])
        XCTAssertEqual(events.first?.endedAt, Date(timeIntervalSince1970: 20))
    }

    func testClearHistoryKeepsSessionAndWritesHistoryClearedEvent() throws {
        let databaseURL = makeDatabaseURL()
        let store = SQLiteSessionHistoryStore(databaseURL: databaseURL)
        try store.initialize()

        let session = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 10))
        try store.replaceWithNewSession(session)
        try store.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: 11),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 55,
                source: .hidSensors
            )
        )
        try store.insertTimelineEvent(
            TimelineEvent(
                id: UUID(),
                sessionID: session.id,
                eventType: .probeReadFailed,
                startedAt: Date(timeIntervalSince1970: 12),
                endedAt: Date(timeIntervalSince1970: 12),
                domain: .cpu,
                metricName: TemperatureMetricName.cpuHottest,
                reasonCode: "readFailed",
                message: "readFailed"
            )
        )

        try store.clearHistory(sessionID: session.id, clearedAt: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(try store.currentSession()?.id, session.id)
        XCTAssertTrue(
            try store.samples(
                matching: TemperatureQuery(
                    sessionID: session.id,
                    domains: [.cpu],
                    metricNames: [TemperatureMetricName.cpuHottest],
                    start: Date(timeIntervalSince1970: 0),
                    end: Date(timeIntervalSince1970: 30),
                    maxPoints: 50
                )
            ).isEmpty
        )

        let events = try store.timelineEvents(
            sessionID: session.id,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 30)
        )
        XCTAssertEqual(events.map(\.eventType), [TimelineEventType.historyCleared])
    }

    private func makeDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
    }
}
