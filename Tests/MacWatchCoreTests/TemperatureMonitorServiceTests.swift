import Foundation
import XCTest
@testable import MacWatchCore

final class TemperatureMonitorServiceTests: XCTestCase {
    func testSampleOnceWritesValidSamplesAndTracksHottest() async throws {
        let repository = InMemorySessionHistoryRepository()
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 100)
        let service = TemperatureMonitorService(
            probes: [
                FakeTemperatureProbe(
                    domain: .cpu,
                    source: .hidSensors,
                    defaultMetricName: TemperatureMetricName.cpuHottest,
                    capability: capability(
                        sessionID: sessionID,
                        domain: .cpu,
                        source: .hidSensors,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    ),
                    samples: [
                        try TemperatureSample.makeValid(
                            sessionID: sessionID,
                            timestamp: timestamp,
                            metricName: TemperatureMetricName.cpuHottest,
                            domain: .cpu,
                            deviceID: "cpu-die",
                            displayName: "CPU Hottest",
                            valueCelsius: 72.4,
                            source: .hidSensors,
                            rawKey: "pACC MTR Temp Sensor0"
                        )
                    ]
                ),
                FakeTemperatureProbe(
                    domain: .gpu,
                    source: .smc,
                    defaultMetricName: TemperatureMetricName.gpuHottest,
                    capability: capability(
                        sessionID: sessionID,
                        domain: .gpu,
                        source: .smc,
                        supported: false,
                        readable: false,
                        reasonCode: "unsupported"
                    ),
                    samples: [
                        try TemperatureSample.makeInvalid(
                            sessionID: sessionID,
                            timestamp: timestamp,
                            metricName: TemperatureMetricName.gpuHottest,
                            domain: .gpu,
                            deviceID: "gpu-die",
                            displayName: "GPU Hottest",
                            quality: .unsupported,
                            source: .smc,
                            errorCode: "unsupported"
                        )
                    ]
                ),
            ],
            repository: repository,
            clock: { timestamp }
        )

        let state = await service.sampleOnce(sessionID: sessionID)

        XCTAssertEqual(state.updatedAt, timestamp)
        XCTAssertEqual(state.hottestValidSample?.metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(state.hottestValidSample?.valueCelsius, 72.4)
        XCTAssertEqual(state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.quality, .unsupported)
        XCTAssertNil(state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.valueCelsius)

        let storedSamples = try repository.samples(sessionID: sessionID)
        XCTAssertEqual(storedSamples.count, 2)
        XCTAssertEqual(storedSamples.map(\.metricName).sorted(), [
            TemperatureMetricName.cpuHottest,
            TemperatureMetricName.gpuHottest,
        ])
    }

    func testUnsupportedSamplesDoNotParticipateInHottest() async throws {
        let repository = InMemorySessionHistoryRepository()
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 200)
        let service = TemperatureMonitorService(
            probes: [
                FakeTemperatureProbe(
                    domain: .gpu,
                    source: .smc,
                    defaultMetricName: TemperatureMetricName.gpuHottest,
                    capability: capability(
                        sessionID: sessionID,
                        domain: .gpu,
                        source: .smc,
                        supported: false,
                        readable: false,
                        reasonCode: "unsupported"
                    ),
                    samples: [
                        try TemperatureSample.makeInvalid(
                            sessionID: sessionID,
                            timestamp: timestamp,
                            metricName: TemperatureMetricName.gpuHottest,
                            domain: .gpu,
                            deviceID: "gpu-die",
                            displayName: "GPU Hottest",
                            quality: .unsupported,
                            source: .smc,
                            errorCode: "unsupported"
                        )
                    ]
                )
            ],
            repository: repository,
            clock: { timestamp }
        )

        let state = await service.sampleOnce(sessionID: sessionID)

        XCTAssertNil(state.hottestValidSample)
        XCTAssertEqual(state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.quality, .unsupported)
        XCTAssertNil(state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.valueCelsius)
    }

    func testEmptyProbeReadBecomesReadFailedAndDoesNotBlockOtherProbes() async throws {
        let repository = InMemorySessionHistoryRepository()
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 300)
        let service = TemperatureMonitorService(
            probes: [
                FakeTemperatureProbe(
                    domain: .cpu,
                    source: .hidSensors,
                    defaultMetricName: TemperatureMetricName.cpuHottest,
                    capability: capability(
                        sessionID: sessionID,
                        domain: .cpu,
                        source: .hidSensors,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    ),
                    samples: [
                        try TemperatureSample.makeValid(
                            sessionID: sessionID,
                            timestamp: timestamp,
                            metricName: TemperatureMetricName.cpuHottest,
                            domain: .cpu,
                            deviceID: "cpu-die",
                            displayName: "CPU Hottest",
                            valueCelsius: 63.0,
                            source: .hidSensors,
                            rawKey: "pACC MTR Temp Sensor2"
                        )
                    ]
                ),
                FakeTemperatureProbe(
                    domain: .gpu,
                    source: .smc,
                    defaultMetricName: TemperatureMetricName.gpuHottest,
                    capability: capability(
                        sessionID: sessionID,
                        domain: .gpu,
                        source: .smc,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    ),
                    samples: []
                ),
            ],
            repository: repository,
            clock: { timestamp }
        )

        let state = await service.sampleOnce(sessionID: sessionID)

        XCTAssertEqual(state.hottestValidSample?.metricName, TemperatureMetricName.cpuHottest)
        XCTAssertEqual(state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.quality, .readFailed)
        XCTAssertNil(state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.rawKey)
        XCTAssertEqual(
            state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.attributes["attemptedMetricName"],
            TemperatureMetricName.gpuHottest
        )

        let events = try repository.timelineEvents(sessionID: sessionID)
        XCTAssertEqual(events.map(\.eventType), [.probeReadFailed])
        XCTAssertEqual(events.first?.domain, .gpu)
    }

    func testDetectCapabilitiesWritesCapabilitiesAndBuildsLiveState() async throws {
        let repository = InMemorySessionHistoryRepository()
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 400)
        let cpuCapability = capability(
            sessionID: sessionID,
            domain: .cpu,
            source: .hidSensors,
            supported: true,
            readable: true,
            reasonCode: "ok"
        )
        let gpuCapability = capability(
            sessionID: sessionID,
            domain: .gpu,
            source: .smc,
            supported: false,
            readable: false,
            reasonCode: "unsupported"
        )
        let service = TemperatureMonitorService(
            probes: [
                FakeTemperatureProbe(
                    domain: .cpu,
                    source: .hidSensors,
                    defaultMetricName: TemperatureMetricName.cpuHottest,
                    capability: cpuCapability,
                    samples: []
                ),
                FakeTemperatureProbe(
                    domain: .gpu,
                    source: .smc,
                    defaultMetricName: TemperatureMetricName.gpuHottest,
                    capability: gpuCapability,
                    samples: []
                ),
            ],
            repository: repository,
            clock: { timestamp }
        )

        let state = await service.detectCapabilities(sessionID: sessionID)

        XCTAssertEqual(state.updatedAt, timestamp)
        XCTAssertEqual(state.capabilitiesByDomain[.cpu], cpuCapability)
        XCTAssertEqual(state.capabilitiesByDomain[.gpu], gpuCapability)
        XCTAssertTrue(state.samplesByMetricName.isEmpty)

        let storedCapabilities = try repository.capabilities(sessionID: sessionID)
        XCTAssertEqual(Set(storedCapabilities.map(\.domain)), Set([.cpu, .gpu]))
    }

    func testSampleOnceKeepsLatestSampleWhenMultipleProbesReturnSameMetricName() async throws {
        let repository = InMemorySessionHistoryRepository()
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 500)
        let service = TemperatureMonitorService(
            probes: [
                FakeTemperatureProbe(
                    domain: .cpu,
                    source: .hidSensors,
                    defaultMetricName: TemperatureMetricName.cpuHottest,
                    capability: capability(
                        sessionID: sessionID,
                        domain: .cpu,
                        source: .hidSensors,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    ),
                    samples: [
                        try TemperatureSample.makeValid(
                            sessionID: sessionID,
                            timestamp: timestamp,
                            metricName: TemperatureMetricName.cpuHottest,
                            domain: .cpu,
                            deviceID: "cpu-die-a",
                            displayName: "CPU Hottest",
                            valueCelsius: 60.0,
                            source: .hidSensors,
                            rawKey: "pACC MTR Temp Sensor0"
                        )
                    ]
                ),
                FakeTemperatureProbe(
                    domain: .cpu,
                    source: .smc,
                    defaultMetricName: TemperatureMetricName.cpuHottest,
                    capability: capability(
                        sessionID: sessionID,
                        domain: .cpu,
                        source: .smc,
                        supported: true,
                        readable: true,
                        reasonCode: "ok"
                    ),
                    samples: [
                        try TemperatureSample.makeValid(
                            sessionID: sessionID,
                            timestamp: timestamp.addingTimeInterval(1),
                            metricName: TemperatureMetricName.cpuHottest,
                            domain: .cpu,
                            deviceID: "cpu-die-b",
                            displayName: "CPU Hottest",
                            valueCelsius: 65.0,
                            source: .smc,
                            rawKey: "Tp01"
                        )
                    ]
                ),
            ],
            repository: repository,
            clock: { timestamp }
        )

        let state = await service.sampleOnce(sessionID: sessionID)

        XCTAssertEqual(state.samplesByMetricName[TemperatureMetricName.cpuHottest]?.rawKey, "Tp01")
        XCTAssertEqual(state.samplesByMetricName[TemperatureMetricName.cpuHottest]?.valueCelsius, 65.0)

        let storedSamples = try repository.samples(sessionID: sessionID)
        XCTAssertEqual(storedSamples.count, 2)
    }
}

private struct FakeTemperatureProbe: TemperatureProbe {
    let id: String = UUID().uuidString
    let domain: TemperatureDomain
    let source: TemperatureSource
    let defaultMetricName: String
    let capability: TemperatureCapability
    let samples: [TemperatureSample]

    func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability {
        capability
    }

    func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample] {
        samples
    }
}

private func capability(
    sessionID: UUID,
    domain: TemperatureDomain,
    source: TemperatureSource,
    supported: Bool,
    readable: Bool,
    reasonCode: String
) -> TemperatureCapability {
    let timestamp = Date(timeIntervalSince1970: 1)
    return TemperatureCapability(
        id: UUID(),
        sessionID: sessionID,
        domain: domain,
        source: source,
        supported: supported,
        readable: readable,
        reasonCode: reasonCode,
        reasonMessage: reasonCode,
        rawKey: nil,
        detectedAt: timestamp,
        updatedAt: timestamp
    )
}
