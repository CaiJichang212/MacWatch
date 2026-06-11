import Foundation
import XCTest
@testable import MacWatchCore

final class TemperatureCapabilityServiceTests: XCTestCase {
    func testDetectAllRunsAllProbesAndNormalizesCapabilityState() async {
        let repository = TestSessionHistoryRepository()
        let clock = SequenceClock([Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)])
        let service = TemperatureCapabilityService(
            probes: [
                StubTemperatureProbe(
                    domain: .cpu,
                    source: .hidSensors,
                    capability: makeCapability(
                        sessionID: UUID(),
                        domain: .cpu,
                        source: .hidSensors,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    )
                ),
                StubTemperatureProbe(
                    domain: .gpu,
                    source: .smc,
                    capability: makeCapability(
                        sessionID: UUID(),
                        domain: .gpu,
                        source: .smc,
                        supported: false,
                        readable: false,
                        reasonCode: ""
                    )
                ),
                StubTemperatureProbe(
                    domain: .memory,
                    source: .smc,
                    capability: makeCapability(
                        sessionID: UUID(),
                        domain: .memory,
                        source: .smc,
                        supported: true,
                        readable: false,
                        reasonCode: ""
                    )
                ),
                StubTemperatureProbe(
                    domain: .ssd,
                    source: .nvmeSMART,
                    capability: makeCapability(
                        sessionID: UUID(),
                        domain: .ssd,
                        source: .nvmeSMART,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    )
                ),
                StubTemperatureProbe(
                    domain: .battery,
                    source: .batteryIORegistry,
                    capability: makeCapability(
                        sessionID: UUID(),
                        domain: .battery,
                        source: .batteryIORegistry,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    )
                ),
            ],
            repository: repository,
            clock: { clock.now() }
        )

        let sessionID = UUID()
        let capabilities = await service.detectAll(sessionID: sessionID, reason: .appStart)

        XCTAssertEqual(Set(capabilities.keys), Set(TemperatureDomain.allCases))
        XCTAssertEqual(capabilities[.gpu]?.supported, false)
        XCTAssertEqual(capabilities[.gpu]?.readable, false)
        XCTAssertEqual(capabilities[.gpu]?.reasonCode, "unsupported")
        XCTAssertEqual(capabilities[.memory]?.supported, true)
        XCTAssertEqual(capabilities[.memory]?.readable, false)
        XCTAssertEqual(capabilities[.memory]?.reasonCode, "readFailed")
        XCTAssertEqual(capabilities[.system]?.supported, false)
        XCTAssertEqual(capabilities[.system]?.readable, false)
        XCTAssertEqual(capabilities[.system]?.reasonCode, "unsupported")
        XCTAssertEqual(capabilities[.system]?.source, .hidSensors)
        XCTAssertEqual(capabilities[.sensor]?.supported, false)
        XCTAssertEqual(capabilities[.sensor]?.readable, false)
        XCTAssertEqual(capabilities[.sensor]?.reasonCode, "unsupported")
        XCTAssertEqual(capabilities[.sensor]?.source, .hidSensors)
        XCTAssertEqual(repository.capabilities.count, 5)
        XCTAssertEqual(repository.timelineEvents.filter { $0.eventType == .historyWriteFailed }.count, 0)
    }

    func testHistoryWriteFailuresAreRecordedButNotBlocking() async {
        let repository = FailingCapabilityInsertRepository()
        let service = TemperatureCapabilityService(
            probes: [
                StubTemperatureProbe(
                    domain: .cpu,
                    source: .hidSensors,
                    capability: makeCapability(
                        sessionID: UUID(),
                        domain: .cpu,
                        source: .hidSensors,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    )
                )
            ],
            repository: repository,
            clock: { Date(timeIntervalSince1970: 1000) }
        )

        let capability = await service.detectAll(sessionID: UUID(), reason: .appStart)

        XCTAssertNotNil(capability[.cpu])
        XCTAssertEqual(repository.timelineEvents.count, 1)
        XCTAssertEqual(repository.timelineEvents.first?.eventType, .historyWriteFailed)
    }

    func testReDetectionAfterWakeUsesFreshTimestamp() async {
        let timestamps: [Date] = [Date(timeIntervalSince1970: 500), Date(timeIntervalSince1970: 501)]
        let clock = SequenceClock(timestamps)
        let probe = TimestampingTemperatureProbe(id: "cpu-primary", domain: .cpu, source: .hidSensors)
        let repository = TestSessionHistoryRepository()
        let service = TemperatureCapabilityService(
            probes: [probe],
            repository: repository,
            clock: { clock.now() }
        )

        let sessionID = UUID()

        _ = await service.detectAll(sessionID: sessionID, reason: .appStart)
        let secondBatch = await service.detectAll(sessionID: sessionID, reason: .wake)

        XCTAssertEqual(secondBatch[.cpu]?.updatedAt, Date(timeIntervalSince1970: 501))
        XCTAssertEqual(probe.detectedAtSamples, timestamps)

        let historyWriteFailedCount = repository.timelineEvents.filter { $0.eventType == .historyWriteFailed }.count
        XCTAssertEqual(historyWriteFailedCount, 0)
    }

    func testDetectAllSummarizesMultipleProbesWithinSameDomainWithoutLastWriteWins() async {
        let repository = TestSessionHistoryRepository()
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 700)
        let service = TemperatureCapabilityService(
            probes: [
                StubTemperatureProbe(
                    id: "sensor-readable",
                    domain: .sensor,
                    source: .hidSensors,
                    capability: makeCapability(
                        sessionID: sessionID,
                        domain: .sensor,
                        source: .hidSensors,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    )
                ),
                StubTemperatureProbe(
                    id: "sensor-unreadable",
                    domain: .sensor,
                    source: .hidSensors,
                    capability: makeCapability(
                        sessionID: sessionID,
                        domain: .sensor,
                        source: .hidSensors,
                        supported: true,
                        readable: false,
                        reasonCode: "detectFailed"
                    )
                ),
            ],
            repository: repository,
            clock: { timestamp }
        )

        let capabilities = await service.detectAll(sessionID: sessionID, reason: .appStart)

        XCTAssertEqual(repository.capabilities.count, 2)
        XCTAssertEqual(capabilities[.sensor]?.readable, true)
        XCTAssertEqual(capabilities[.sensor]?.reasonCode, "ok")
    }
}

private final class SequenceClock: @unchecked Sendable {
    private let dates: [Date]
    private var index: Int = 0

    init(_ dates: [Date]) {
        self.dates = dates
    }

    func now() -> Date {
        let current = dates[index % dates.count]
        index += 1
        return current
    }
}

private func makeCapability(
    sessionID: UUID,
    domain: TemperatureDomain,
    source: TemperatureSource,
    supported: Bool,
    readable: Bool,
    reasonCode: String
) -> TemperatureCapability {
    TemperatureCapability(
        id: UUID(),
        sessionID: sessionID,
        domain: domain,
        source: source,
        supported: supported,
        readable: readable,
        reasonCode: reasonCode,
        reasonMessage: reasonCode,
        rawKey: nil,
        detectedAt: Date(),
        updatedAt: Date()
    )
}

private final class StubTemperatureProbe: @unchecked Sendable, TemperatureProbe {
    let id: String
    let domain: TemperatureDomain
    let source: TemperatureSource
    let defaultMetricName: String
    private let configured: TemperatureCapability

    init(id: String = UUID().uuidString, domain: TemperatureDomain, source: TemperatureSource, capability: TemperatureCapability) {
        self.id = id
        self.domain = domain
        self.source = source
        self.configured = capability
        self.defaultMetricName = metricName(for: domain)
    }

    func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        configured
    }

    func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        []
    }
}

private final class TimestampingTemperatureProbe: @unchecked Sendable, TemperatureProbe {
    let id: String
    let domain: TemperatureDomain
    let source: TemperatureSource
    let defaultMetricName: String
    private(set) var detectedAtSamples: [Date] = []

    init(id: String, domain: TemperatureDomain, source: TemperatureSource) {
        self.id = id
        self.domain = domain
        self.source = source
        self.defaultMetricName = metricName(for: domain)
    }

    func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        detectedAtSamples.append(timestamp)

        return TemperatureCapability(
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
        []
    }
}

private func metricName(for domain: TemperatureDomain) -> String {
    switch domain {
    case .cpu:
        return TemperatureMetricName.cpuHottest
    case .gpu:
        return TemperatureMetricName.gpuHottest
    case .memory:
        return TemperatureMetricName.memoryProximity
    case .ssd:
        return TemperatureMetricName.ssdInternal
    case .battery:
        return TemperatureMetricName.battery
    case .system:
        return TemperatureMetricName.systemHottest
    case .sensor:
        return "sensor.temperature"
    }
}

private final class TestSessionHistoryRepository: SessionHistoryRepository {
    private(set) var capabilities: [TemperatureCapability] = []
    private(set) var timelineEvents: [TimelineEvent] = []

    func beginSession(_ session: MonitoringSession, clearingPreviousHistory: Bool) throws {}
    func currentSession() throws -> MonitoringSession? { nil }
    func endSession(id: UUID, endedAt: Date) throws {}
    func insertSample(_ sample: TemperatureSample) throws {}
    func insertCapability(_ capability: TemperatureCapability) throws { capabilities.append(capability) }
    func insertTimelineEvent(_ event: TimelineEvent) throws { timelineEvents.append(event) }
    func updateTimelineEvent(id: UUID, endedAt: Date) throws {}
    func timelineEvents(sessionID: UUID) throws -> [TimelineEvent] { timelineEvents }
    func query(_ query: TemperatureQuery) throws -> [TemperatureSeries] { [] }
    func query(
        sessionID: UUID,
        domain: TemperatureDomain,
        metricName: String,
        range: TemperatureHistoryRange,
        now: Date,
        maxPoints: Int
    ) throws -> TemperatureSeries {
        TemperatureSeries(metricName: metricName, domain: domain, samples: [], gaps: [])
    }
    func clearCurrentSessionHistory(at clearedAt: Date) throws {}
}

private final class FailingCapabilityInsertRepository: SessionHistoryRepository {
    private(set) var timelineEvents: [TimelineEvent] = []

    func beginSession(_ session: MonitoringSession, clearingPreviousHistory: Bool) throws {}
    func currentSession() throws -> MonitoringSession? { nil }
    func endSession(id: UUID, endedAt: Date) throws {}
    func insertSample(_ sample: TemperatureSample) throws {}
    func insertCapability(_ capability: TemperatureCapability) throws {
        throw NSError(domain: "Test", code: 1)
    }
    func insertTimelineEvent(_ event: TimelineEvent) throws { timelineEvents.append(event) }
    func updateTimelineEvent(id: UUID, endedAt: Date) throws {}
    func timelineEvents(sessionID: UUID) throws -> [TimelineEvent] { timelineEvents }
    func query(_ query: TemperatureQuery) throws -> [TemperatureSeries] { [] }
    func query(
        sessionID: UUID,
        domain: TemperatureDomain,
        metricName: String,
        range: TemperatureHistoryRange,
        now: Date,
        maxPoints: Int
    ) throws -> TemperatureSeries {
        TemperatureSeries(metricName: metricName, domain: domain, samples: [], gaps: [])
    }
    func clearCurrentSessionHistory(at clearedAt: Date) throws {}
}
