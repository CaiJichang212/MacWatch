import Foundation
import MacWatchCore
import XCTest
@testable import MacWatchApp

final class MacWatchRuntimeTests: XCTestCase {
    @MainActor
    func testRuntimeSamplesSlowProbesLessFrequentlyThanFastProbes() async throws {
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
            fastSampleInterval: 0.01,
            slowSampleInterval: 60
        )

        runtime.start()
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertGreaterThanOrEqual(fastProbe.readCount, 2)
        XCTAssertEqual(slowProbe.readCount, 1)
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
    let domain: TemperatureDomain
    let source: TemperatureSource
    let defaultMetricName: String
    private let valueCelsius: Double
    private let lock = NSLock()
    private var _readCount = 0

    init(
        domain: TemperatureDomain,
        source: TemperatureSource,
        metricName: String,
        valueCelsius: Double
    ) {
        self.domain = domain
        self.source = source
        self.defaultMetricName = metricName
        self.valueCelsius = valueCelsius
    }

    var readCount: Int {
        lock.withLock { _readCount }
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
