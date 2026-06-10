import Foundation
import MacWatchCore
import XCTest
@testable import MacWatchApp

final class MacWatchRuntimeHistoryTests: XCTestCase {
    @MainActor
    func testRuntimeQueriesSeriesByHistoryRange() throws {
        let repository = InMemorySessionHistoryRepository()
        let session = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 0))
        try repository.beginSession(session, clearingPreviousHistory: true)
        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: 100),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 62,
                source: .hidSensors
            )
        )
        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: 3_700),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 72,
                source: .hidSensors
            )
        )

        let runtime = MacWatchRuntime(
            sessionHistoryRepository: repository,
            probeProvider: EmptyRuntimeProbeProvider(),
            clock: { Date(timeIntervalSince1970: 4_000) }
        )
        runtime.start()

        let oneHour = runtime.series(
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            range: .oneHour,
            maxPoints: 2_000
        )
        let allSession = runtime.series(
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            range: .allSession,
            maxPoints: 2_000
        )
        let fifteenMinutes = runtime.series(
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            range: .fifteenMinutes,
            maxPoints: 2_000
        )

        XCTAssertEqual(oneHour?.samples.count, 1)
        XCTAssertEqual(allSession?.samples.count, 2)
        XCTAssertEqual(fifteenMinutes?.samples.count, 1)
        XCTAssertEqual(fifteenMinutes?.statistics.maximumCelsius, 72)
    }

    @MainActor
    func testClearCurrentSessionHistoryIncrementsRevisionAndRemovesTrendSamples() throws {
        let repository = InMemorySessionHistoryRepository()
        let session = MonitoringSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 0))
        try repository.beginSession(session, clearingPreviousHistory: true)
        try repository.insertSample(
            TemperatureSample.makeValid(
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: 100),
                metricName: TemperatureMetricName.cpuHottest,
                domain: .cpu,
                deviceID: "cpu",
                displayName: "CPU",
                valueCelsius: 62,
                source: .hidSensors
            )
        )

        let runtime = MacWatchRuntime(
            sessionHistoryRepository: repository,
            probeProvider: EmptyRuntimeProbeProvider(),
            clock: { Date(timeIntervalSince1970: 4_000) }
        )
        runtime.start()

        XCTAssertEqual(runtime.historyRevision, 0)
        XCTAssertEqual(
            runtime.series(
                domain: .cpu,
                metricName: TemperatureMetricName.cpuHottest,
                range: .allSession,
                maxPoints: 2_000
            )?.samples.count,
            1
        )

        runtime.clearCurrentSessionHistory()

        XCTAssertEqual(runtime.historyRevision, 1)
        XCTAssertEqual(
            runtime.series(
                domain: .cpu,
                metricName: TemperatureMetricName.cpuHottest,
                range: .allSession,
                maxPoints: 2_000
            )?.samples.count,
            0
        )
    }
}

private struct EmptyRuntimeProbeProvider: MacWatchTemperatureProbeProviding {
    func makeFastProbes() -> [any TemperatureProbe] { [] }
    func makeSlowProbes() -> [any TemperatureProbe] { [] }
}
