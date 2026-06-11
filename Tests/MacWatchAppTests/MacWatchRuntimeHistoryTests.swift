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

    @MainActor
    func testRuntimeLoadsSeriesOffMainThread() async throws {
        let baseRepository = InMemorySessionHistoryRepository()
        let repository = RecordingQueryThreadRepository(base: baseRepository)
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

        let series = await runtime.loadSeries(
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            range: .allSession,
            maxPoints: 2_000
        )

        XCTAssertEqual(series?.samples.count, 1)
        XCTAssertEqual(repository.lastQueryWasOnMainThread, false)
    }

    @MainActor
    func testRuntimeWritesHistorySamplesOffMainThread() async throws {
        let baseRepository = InMemorySessionHistoryRepository()
        let repository = RecordingWriteThreadRepository(base: baseRepository)
        let sessionID = UUID()
        try repository.beginSession(
            MonitoringSession(id: sessionID, startedAt: Date(timeIntervalSince1970: 0)),
            clearingPreviousHistory: true
        )
        let probe = RuntimeHistoryProbe(
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            valueCelsius: 61
        )
        let runtime = MacWatchRuntime(
            sessionHistoryRepository: repository,
            probeProvider: RuntimeHistoryProbeProvider(fastProbes: [probe], slowProbes: []),
            fastSampleInterval: 0.05,
            clock: { Date() }
        )

        runtime.start()
        try await Task.sleep(nanoseconds: 160_000_000)

        XCTAssertEqual(repository.lastInsertSampleWasOnMainThread, false)
    }
}

private struct EmptyRuntimeProbeProvider: MacWatchTemperatureProbeProviding {
    func makeFastProbes() -> [any TemperatureProbe] { [] }
    func makeSlowProbes() -> [any TemperatureProbe] { [] }
}

private final class RecordingQueryThreadRepository: SessionHistoryRepository {
    private let base: SessionHistoryRepository
    private let lock = NSLock()
    private var recordedQueryThread: Bool?

    init(base: SessionHistoryRepository) {
        self.base = base
    }

    var lastQueryWasOnMainThread: Bool? {
        lock.withLock { recordedQueryThread }
    }

    func beginSession(_ session: MonitoringSession, clearingPreviousHistory: Bool) throws {
        try base.beginSession(session, clearingPreviousHistory: clearingPreviousHistory)
    }

    func currentSession() throws -> MonitoringSession? {
        try base.currentSession()
    }

    func endSession(id: UUID, endedAt: Date) throws {
        try base.endSession(id: id, endedAt: endedAt)
    }

    func insertSample(_ sample: TemperatureSample) throws {
        try base.insertSample(sample)
    }

    func insertCapability(_ capability: TemperatureCapability) throws {
        try base.insertCapability(capability)
    }

    func insertTimelineEvent(_ event: TimelineEvent) throws {
        try base.insertTimelineEvent(event)
    }

    func updateTimelineEvent(id: UUID, endedAt: Date) throws {
        try base.updateTimelineEvent(id: id, endedAt: endedAt)
    }

    func timelineEvents(sessionID: UUID) throws -> [TimelineEvent] {
        try base.timelineEvents(sessionID: sessionID)
    }

    func query(_ query: TemperatureQuery) throws -> [TemperatureSeries] {
        try base.query(query)
    }

    func query(
        sessionID: UUID,
        domain: TemperatureDomain,
        metricName: String,
        range: TemperatureHistoryRange,
        now: Date,
        maxPoints: Int
    ) throws -> TemperatureSeries {
        lock.withLock {
            recordedQueryThread = Thread.isMainThread
        }
        return try base.query(
            sessionID: sessionID,
            domain: domain,
            metricName: metricName,
            range: range,
            now: now,
            maxPoints: maxPoints
        )
    }

    func clearCurrentSessionHistory(at clearedAt: Date) throws {
        try base.clearCurrentSessionHistory(at: clearedAt)
    }
}

private final class RecordingWriteThreadRepository: SessionHistoryRepository {
    private let base: SessionHistoryRepository
    private let lock = NSLock()
    private var recordedInsertSampleThread: Bool?

    init(base: SessionHistoryRepository) {
        self.base = base
    }

    var lastInsertSampleWasOnMainThread: Bool? {
        lock.withLock { recordedInsertSampleThread }
    }

    func beginSession(_ session: MonitoringSession, clearingPreviousHistory: Bool) throws {
        try base.beginSession(session, clearingPreviousHistory: clearingPreviousHistory)
    }

    func currentSession() throws -> MonitoringSession? {
        try base.currentSession()
    }

    func endSession(id: UUID, endedAt: Date) throws {
        try base.endSession(id: id, endedAt: endedAt)
    }

    func insertSample(_ sample: TemperatureSample) throws {
        lock.withLock {
            recordedInsertSampleThread = Thread.isMainThread
        }
        try base.insertSample(sample)
    }

    func insertCapability(_ capability: TemperatureCapability) throws {
        try base.insertCapability(capability)
    }

    func insertTimelineEvent(_ event: TimelineEvent) throws {
        try base.insertTimelineEvent(event)
    }

    func updateTimelineEvent(id: UUID, endedAt: Date) throws {
        try base.updateTimelineEvent(id: id, endedAt: endedAt)
    }

    func timelineEvents(sessionID: UUID) throws -> [TimelineEvent] {
        try base.timelineEvents(sessionID: sessionID)
    }

    func query(_ query: TemperatureQuery) throws -> [TemperatureSeries] {
        try base.query(query)
    }

    func query(
        sessionID: UUID,
        domain: TemperatureDomain,
        metricName: String,
        range: TemperatureHistoryRange,
        now: Date,
        maxPoints: Int
    ) throws -> TemperatureSeries {
        try base.query(
            sessionID: sessionID,
            domain: domain,
            metricName: metricName,
            range: range,
            now: now,
            maxPoints: maxPoints
        )
    }

    func clearCurrentSessionHistory(at clearedAt: Date) throws {
        try base.clearCurrentSessionHistory(at: clearedAt)
    }
}

private struct RuntimeHistoryProbeProvider: MacWatchTemperatureProbeProviding {
    let fastProbes: [any TemperatureProbe]
    let slowProbes: [any TemperatureProbe]

    func makeFastProbes() -> [any TemperatureProbe] { fastProbes }
    func makeSlowProbes() -> [any TemperatureProbe] { slowProbes }
}

private final class RuntimeHistoryProbe: TemperatureProbe, @unchecked Sendable {
    let id = UUID().uuidString
    let domain: TemperatureDomain
    let source: TemperatureSource = .hidSensors
    let defaultMetricName: String
    private let valueCelsius: Double

    init(domain: TemperatureDomain, metricName: String, valueCelsius: Double) {
        self.domain = domain
        self.defaultMetricName = metricName
        self.valueCelsius = valueCelsius
    }

    func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        TemperatureCapability(
            id: UUID(),
            sessionID: sessionID,
            domain: domain,
            source: source,
            supported: true,
            readable: true,
            reasonCode: "ok",
            reasonMessage: "ok",
            rawKey: nil,
            detectedAt: timestamp,
            updatedAt: timestamp
        )
    }

    func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        [
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: defaultMetricName,
                domain: domain,
                deviceID: domain.rawValue,
                displayName: defaultMetricName,
                valueCelsius: valueCelsius,
                source: source
            )
        ]
    }
}
