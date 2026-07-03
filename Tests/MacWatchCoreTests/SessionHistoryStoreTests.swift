import Foundation
import SQLite3
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

    func testLegacyZeroTemperatureRowsAreSanitizedOnRead() throws {
        let databaseURL = makeDatabaseURL()
        let store = SQLiteSessionHistoryStore(databaseURL: databaseURL)
        try store.initialize()

        let session = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 10))
        try store.replaceWithNewSession(session)
        try insertLegacyZeroTemperatureRow(
            databaseURL: databaseURL,
            sessionID: session.id,
            metricName: TemperatureMetricName.gpuHottest,
            domain: .gpu
        )

        let samples = try store.samples(
            matching: TemperatureQuery(
                sessionID: session.id,
                domains: [.gpu],
                metricNames: [TemperatureMetricName.gpuHottest],
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 30),
                maxPoints: 50
            )
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.quality, .readFailed)
        XCTAssertNil(samples.first?.valueCelsius)
        XCTAssertEqual(samples.first?.errorCode, "invalidPersistedTemperature")
        XCTAssertEqual(samples.first?.attributes["sanitizedPersistedValueCelsius"], "0.0")
        XCTAssertEqual(samples.first?.attributes["sanitizedPersistedQuality"], "valid")
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

private func insertLegacyZeroTemperatureRow(
    databaseURL: URL,
    sessionID: UUID,
    metricName: String,
    domain: TemperatureDomain
) throws {
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
    defer { sqlite3_close(database) }

    let sql = """
    INSERT INTO temperature_sample (
        id, session_id, timestamp_ms, metric_name, domain, device_id, display_name,
        value_celsius, source, quality, raw_key, error_code, attributes_json, created_at_ms
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """

    var statement: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
    defer { sqlite3_finalize(statement) }

    bindText(UUID().uuidString, at: 1, statement: statement)
    bindText(sessionID.uuidString, at: 2, statement: statement)
    sqlite3_bind_int64(statement, 3, 11_000)
    bindText(metricName, at: 4, statement: statement)
    bindText(domain.rawValue, at: 5, statement: statement)
    bindText("gpu", at: 6, statement: statement)
    bindText("GPU Hottest", at: 7, statement: statement)
    sqlite3_bind_double(statement, 8, 0)
    bindText(TemperatureSource.smc.rawValue, at: 9, statement: statement)
    bindText(TemperatureQuality.valid.rawValue, at: 10, statement: statement)
    bindText("Tg0G", at: 11, statement: statement)
    sqlite3_bind_null(statement, 12)
    bindText("{}", at: 13, statement: statement)
    sqlite3_bind_int64(statement, 14, 11_000)

    XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
}

private func bindText(_ text: String, at index: Int32, statement: OpaquePointer?) {
    sqlite3_bind_text(statement, index, (text as NSString).utf8String, -1, SQLITE_TRANSIENT)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
