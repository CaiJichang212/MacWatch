import Foundation
import XCTest
@testable import MacWatchCore

final class SessionLifecycleServiceTests: XCTestCase {
    func testLaunchCreatesNewSessionAndClearsPreviousHistory() throws {
        let repository = InMemorySessionHistoryRepository()
        let clock = TestClock([
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 20),
        ])
        let service = SessionLifecycleService(repository: repository, clock: clock.next)

        guard let first = try service.handle(.launched) else {
            return XCTFail("Expected launched to create a session")
        }
        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: first.id,
                timestamp: Date(timeIntervalSince1970: 11),
                metricName: "cpu.temperature.hottest",
                domain: .cpu,
                deviceID: "die-0",
                displayName: "CPU Hottest",
                valueCelsius: 42,
                source: .hidSensors
            )
        )

        guard let second = try service.handle(.launched) else {
            return XCTFail("Expected launched to create a new session")
        }

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try repository.currentSession()?.id, second.id)
        XCTAssertTrue(try repository.samples(sessionID: first.id).isEmpty)
        XCTAssertTrue(try repository.samples(sessionID: second.id).isEmpty)
        XCTAssertEqual(
            try repository.timelineEvents(sessionID: second.id).map(\.eventType),
            [TimelineEventType.appStarted]
        )
    }

    func testSleepWakeCreatesGapForTrendQueries() throws {
        let repository = InMemorySessionHistoryRepository()
        let clock = TestClock([
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 20),
            Date(timeIntervalSince1970: 40),
        ])
        let service = SessionLifecycleService(repository: repository, clock: clock.next)

        guard let session = try service.handle(.launched) else {
            return XCTFail("Expected launched to create a session")
        }
        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: 15),
                metricName: "cpu.temperature.hottest",
                domain: .cpu,
                deviceID: "die-0",
                displayName: "CPU Hottest",
                valueCelsius: 41,
                source: .hidSensors
            )
        )

        _ = try service.handle(.willSleep)
        _ = try service.handle(.didWake)

        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: 45),
                metricName: "cpu.temperature.hottest",
                domain: .cpu,
                deviceID: "die-0",
                displayName: "CPU Hottest",
                valueCelsius: 46,
                source: .hidSensors
            )
        )

        let events = try repository.timelineEvents(sessionID: session.id)
        XCTAssertEqual(events.map(\.eventType), [
            TimelineEventType.appStarted,
            .systemSleepStarted,
            .systemSleepEnded,
        ])
        XCTAssertEqual(events[1].startedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(events[1].endedAt, Date(timeIntervalSince1970: 40))
        XCTAssertEqual(events[2].startedAt, Date(timeIntervalSince1970: 40))

        let series = try repository.query(
            TemperatureQuery(
                sessionID: session.id,
                domains: [.cpu],
                metricNames: ["cpu.temperature.hottest"],
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 60),
                maxPoints: 100
            )
        )

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].samples.count, 2)
        XCTAssertEqual(series[0].gaps.map(\.eventType), [TimelineEventType.systemSleepStarted])
        XCTAssertEqual(series[0].gaps[0].endedAt, Date(timeIntervalSince1970: 40))
    }

    func testTerminateEndsCurrentSessionAndRecordsTerminationEvent() throws {
        let repository = InMemorySessionHistoryRepository()
        let clock = TestClock([
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 50),
        ])
        let service = SessionLifecycleService(repository: repository, clock: clock.next)

        guard let session = try service.handle(.launched) else {
            return XCTFail("Expected launched to create a session")
        }
        let terminated = try service.handle(.willTerminate)

        XCTAssertEqual(terminated?.id, session.id)
        XCTAssertEqual(try repository.currentSession()?.endedAt, Date(timeIntervalSince1970: 50))
        XCTAssertEqual(
            try repository.timelineEvents(sessionID: session.id).map(\.eventType),
            [TimelineEventType.appStarted, .appTerminating]
        )
    }

    func testQueryCapsSamplesPerSeriesToMaxPoints() throws {
        let repository = InMemorySessionHistoryRepository()
        let clock = TestClock([Date(timeIntervalSince1970: 10)])
        let service = SessionLifecycleService(repository: repository, clock: clock.next)

        guard let session = try service.handle(.launched) else {
            return XCTFail("Expected launched to create a session")
        }

        for second in 11...15 {
            try repository.insertSample(
                TemperatureSample.makeValid(
                    sessionID: session.id,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(second)),
                    metricName: "cpu.temperature.hottest",
                    domain: .cpu,
                    deviceID: "die-0",
                    displayName: "CPU Hottest",
                    valueCelsius: Double(second),
                    source: .hidSensors
                )
            )
        }

        let series = try repository.query(
            TemperatureQuery(
                sessionID: session.id,
                domains: [.cpu],
                metricNames: ["cpu.temperature.hottest"],
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 30),
                maxPoints: 2
            )
        )

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].samples.count, 2)
        XCTAssertEqual(
            series[0].samples.map(\.timestamp),
            [Date(timeIntervalSince1970: 14), Date(timeIntervalSince1970: 15)]
        )
    }

    func testQueryReturnsGapOnlySeriesWhenMetricIsRequestedWithoutSamples() throws {
        let repository = InMemorySessionHistoryRepository()
        let clock = TestClock([
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 20),
            Date(timeIntervalSince1970: 40),
        ])
        let service = SessionLifecycleService(repository: repository, clock: clock.next)

        guard let session = try service.handle(.launched) else {
            return XCTFail("Expected launched to create a session")
        }

        _ = try service.handle(.willSleep)
        _ = try service.handle(.didWake)

        let series = try repository.query(
            TemperatureQuery(
                sessionID: session.id,
                domains: [.cpu],
                metricNames: ["cpu.temperature.hottest"],
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 60),
                maxPoints: 10
            )
        )

        XCTAssertEqual(series.count, 1)
        guard let firstSeries = series.first else {
            return
        }
        XCTAssertEqual(firstSeries.metricName, "cpu.temperature.hottest")
        XCTAssertEqual(firstSeries.domain, .cpu)
        XCTAssertTrue(firstSeries.samples.isEmpty)
        XCTAssertEqual(firstSeries.gaps.map(\.eventType), [.systemSleepStarted])
        XCTAssertEqual(firstSeries.gaps.first?.endedAt, Date(timeIntervalSince1970: 40))
    }
}

private final class TestClock {
    private var dates: [Date]

    init(_ dates: [Date]) {
        self.dates = dates
    }

    func next() -> Date {
        precondition(dates.isEmpty == false, "Test clock exhausted")
        return dates.removeFirst()
    }
}
