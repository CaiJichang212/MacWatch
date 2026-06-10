import Foundation
import MacWatchCore
import XCTest
@testable import MacWatchApp

final class MacWatchRuntimeSchedulerTests: XCTestCase {
    @MainActor
    func testRuntimeStartsAndPublishesSchedulerSamplesAndCapabilities() async throws {
        let repository = InMemorySessionHistoryRepository()
        let sessionID = UUID()
        try repository.beginSession(
            MonitoringSession(id: sessionID, startedAt: Date(timeIntervalSince1970: 10)),
            clearingPreviousHistory: true
        )

        let fastProbe = CountingTemperatureProbe(
            domain: .cpu,
            source: .hidSensors,
            metricName: TemperatureMetricName.cpuHottest,
            valueCelsius: 51
        )
        let slowProbe = CountingTemperatureProbe(
            domain: .ssd,
            source: .nvmeSMART,
            metricName: TemperatureMetricName.ssdInternal,
            valueCelsius: 33
        )
        let runtime = MacWatchRuntime(
            sessionHistoryRepository: repository,
            probeProvider: FakeRuntimeProbeProvider(fastProbes: [fastProbe], slowProbes: [slowProbe]),
            fastSampleInterval: 0.05,
            slowSampleInterval: 0.1
        )

        runtime.start()
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertGreaterThan(fastProbe.readCount, 0)
        XCTAssertGreaterThan(slowProbe.readCount, 0)
        XCTAssertGreaterThanOrEqual(fastProbe.detectCount, 1)
        XCTAssertEqual(fastProbe.detectCount, 1)
        XCTAssertEqual(slowProbe.detectCount, 1)

        XCTAssertEqual(runtime.liveState?.capabilitiesByDomain.keys.contains(.cpu), true)
        XCTAssertEqual(runtime.liveState?.capabilitiesByDomain.keys.contains(.ssd), true)
        XCTAssertNotNil(runtime.liveState?.samplesByMetricName[TemperatureMetricName.cpuHottest])
        XCTAssertNotNil(runtime.currentSession)
    }
}

private struct FakeRuntimeProbeProvider: MacWatchTemperatureProbeProviding {
    let fastProbes: [any TemperatureProbe]
    let slowProbes: [any TemperatureProbe]

    func makeFastProbes() -> [any TemperatureProbe] {
        fastProbes
    }

    func makeSlowProbes() -> [any TemperatureProbe] {
        slowProbes
    }
}

private final class CountingTemperatureProbe: TemperatureProbe, @unchecked Sendable {
    let id: String
    let domain: TemperatureDomain
    let source: TemperatureSource
    let defaultMetricName: String
    private let valueCelsius: Double
    private let lock = NSLock()
    private var _readCount = 0
    private var _detectCount = 0

    init(
        id: String = UUID().uuidString,
        domain: TemperatureDomain,
        source: TemperatureSource,
        metricName: String,
        valueCelsius: Double
    ) {
        self.id = id
        self.domain = domain
        self.source = source
        self.defaultMetricName = metricName
        self.valueCelsius = valueCelsius
    }

    var readCount: Int {
        lock.withLock { _readCount }
    }

    var detectCount: Int {
        lock.withLock { _detectCount }
    }

    func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        lock.withLock {
            _detectCount += 1
        }

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
        lock.withLock {
            _readCount += 1
        }
        return [
            try! TemperatureSample.makeValid(
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: defaultMetricName,
                domain: domain,
                deviceID: domain.rawValue,
                displayName: defaultMetricName,
                valueCelsius: valueCelsius,
                source: source,
                attributes: ["test": "true"]
            )
        ]
    }
}
