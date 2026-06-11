import Foundation
import XCTest
@testable import MacWatchCore

final class TemperatureSchedulerTests: XCTestCase {
    func testAutoRunLoopSleepsUntilNearestDeadlineInsteadOfPolling() async {
        let sessionID = UUID()
        let probe = ManualTickProbe(
            id: "cpu-primary",
            domain: .cpu,
            source: .hidSensors,
            defaultMetricName: TemperatureMetricName.cpuHottest
        )
        let repository = InMemorySessionHistoryRepository()
        let capabilityService = TemperatureCapabilityService(
            probes: [probe],
            repository: repository,
            clock: { Date() }
        )
        let bus = SampleBus()
        let clock = DeterministicClock(initial: Date(timeIntervalSince1970: 100))
        let sleepExpectation = expectation(description: "scheduler records sleep interval")
        let recorder = SleepIntervalRecorder(expectation: sleepExpectation)
        let schedulerBox = SchedulerBox()

        var scheduler: TemperatureScheduler!
        scheduler = TemperatureScheduler(
            probes: [probe],
            capabilityService: capabilityService,
            bus: bus,
            clock: { clock.now() },
            minimumTickInterval: 0.05,
            sleep: { interval in
                await recorder.record(interval)
                await schedulerBox.stop(at: clock.now())
            }
        )
        await schedulerBox.set(scheduler)

        await scheduler.start(sessionID: sessionID)
        await fulfillment(of: [sleepExpectation], timeout: 1)

        let interval = await recorder.firstInterval
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval ?? 0, 5, accuracy: 0.1)
        XCTAssertEqual(probe.readCount, 1)
    }

    func testManualTickSeparatesRealtimeAndHistoryWritePaths() async {
        let sessionID = UUID()
        let probe = ManualTickProbe(
            id: "cpu-primary",
            domain: .cpu,
            source: .hidSensors,
            defaultMetricName: TemperatureMetricName.cpuHottest
        )
        let repository = InMemorySessionHistoryRepository()
        let capabilityService = TemperatureCapabilityService(
            probes: [probe],
            repository: repository,
            clock: { Date() }
        )

        let bus = SampleBus()
        let collector = SchedulerTestCollector()
        _ = await bus.subscribe { event in
            await collector.record(event)
        }

        let clock = DeterministicClock(initial: Date(timeIntervalSince1970: 100))
        let scheduler = TemperatureScheduler(
            probes: [probe],
            capabilityService: capabilityService,
            bus: bus,
            clock: { clock.now() },
            minimumTickInterval: 9999,
            policyForDomain: { _ in
                TemperatureSamplingPolicy(realtimeInterval: 5, historyInterval: 10, minimumInterval: 5)
            }
        )

        await scheduler.start(sessionID: sessionID)

        let eventKindsAfterStart = await collector.kinds()
        XCTAssertEqual(eventKindsAfterStart.first, "capabilities")

        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))

        let events = await collector.snapshot()
        XCTAssertTrue(events.sampleContexts.count >= 2)
        XCTAssertTrue(events.sampleContexts.contains { $0.shouldWriteHistory })
        XCTAssertTrue(events.sampleContexts.contains { !$0.shouldWriteHistory })
        XCTAssertEqual(probe.readCount, events.sampleContexts.count)
    }

    func testMultiDomainPoliciesUseExpectedCadence() async {
        let sessionID = UUID()
        let cpuProbe = ManualTickProbe(
            id: "cpu-primary",
            domain: .cpu,
            source: .hidSensors,
            defaultMetricName: TemperatureMetricName.cpuHottest
        )
        let gpuProbe = ManualTickProbe(
            id: "gpu-primary",
            domain: .gpu,
            source: .smc,
            defaultMetricName: TemperatureMetricName.gpuHottest
        )
        let memoryProbe = ManualTickProbe(
            id: "memory-primary",
            domain: .memory,
            source: .smc,
            defaultMetricName: TemperatureMetricName.memoryProximity
        )
        let ssdProbe = ManualTickProbe(
            id: "ssd-primary",
            domain: .ssd,
            source: .nvmeSMART,
            defaultMetricName: TemperatureMetricName.ssdInternal
        )
        let batteryProbe = ManualTickProbe(
            id: "battery-primary",
            domain: .battery,
            source: .batteryIORegistry,
            defaultMetricName: TemperatureMetricName.battery
        )
        let systemProbe = ManualTickProbe(
            id: "system-primary",
            domain: .system,
            source: .ioReportCandidate,
            defaultMetricName: TemperatureMetricName.systemHottest
        )
        let sensorProbe = ManualTickProbe(
            id: "sensor-primary",
            domain: .sensor,
            source: .hidSensors,
            defaultMetricName: "sensor.temperature.raw"
        )

        let probes: [any TemperatureProbe] = [
            cpuProbe,
            gpuProbe,
            memoryProbe,
            ssdProbe,
            batteryProbe,
            systemProbe,
            sensorProbe,
        ]

        let repository = InMemorySessionHistoryRepository()
        let capabilityService = TemperatureCapabilityService(
            probes: probes,
            repository: repository,
            clock: { Date() }
        )

        let bus = SampleBus()
        let collector = SchedulerTestCollector()
        _ = await bus.subscribe { event in
            await collector.record(event)
        }

        let clock = DeterministicClock(initial: Date(timeIntervalSince1970: 100))
        let scheduler = TemperatureScheduler(
            probes: probes,
            capabilityService: capabilityService,
            bus: bus,
            clock: { clock.now() },
            minimumTickInterval: 9999,
            policyForDomain: { domain in
                switch domain {
                case .cpu:
                    return TemperatureSamplingPolicy.default(for: .cpu, userRealtimeInterval: 5)
                case .gpu:
                    return TemperatureSamplingPolicy.default(for: .gpu, userRealtimeInterval: 5)
                case .memory:
                    return TemperatureSamplingPolicy.default(for: .memory)
                case .ssd:
                    return TemperatureSamplingPolicy.default(for: .ssd, userRealtimeInterval: 5)
                case .battery:
                    return TemperatureSamplingPolicy.default(for: .battery, userRealtimeInterval: 5)
                case .system:
                    return TemperatureSamplingPolicy.default(for: .system)
                case .sensor:
                    return TemperatureSamplingPolicy.default(for: .sensor)
                }
            }
        )

        await scheduler.start(sessionID: sessionID)

        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))

        let events = await collector.snapshot()
        let cpuContexts = events.sampleContextsByProbeID["cpu-primary"] ?? []
        let gpuContexts = events.sampleContextsByProbeID["gpu-primary"] ?? []
        let memoryContexts = events.sampleContextsByProbeID["memory-primary"] ?? []
        let ssdContexts = events.sampleContextsByProbeID["ssd-primary"] ?? []
        let batteryContexts = events.sampleContextsByProbeID["battery-primary"] ?? []
        let systemContexts = events.sampleContextsByProbeID["system-primary"] ?? []
        let sensorContexts = events.sampleContextsByProbeID["sensor-primary"] ?? []

        XCTAssertEqual(cpuContexts.count, 5)
        XCTAssertEqual(gpuContexts.count, 5)
        XCTAssertEqual(memoryContexts.count, 1)
        XCTAssertEqual(ssdContexts.count, 1)
        XCTAssertEqual(batteryContexts.count, 1)
        XCTAssertEqual(systemContexts.count, 3)
        XCTAssertEqual(sensorContexts.count, 3)

        XCTAssertEqual(cpuContexts.filter(\.shouldWriteHistory).count, 3)
        XCTAssertEqual(gpuContexts.filter(\.shouldWriteHistory).count, 3)
        XCTAssertEqual(memoryContexts.filter(\.shouldWriteHistory).count, 1)
        XCTAssertEqual(ssdContexts.filter(\.shouldWriteHistory).count, 1)
        XCTAssertEqual(batteryContexts.filter(\.shouldWriteHistory).count, 1)
        XCTAssertEqual(systemContexts.filter(\.shouldWriteHistory).count, 1)
        XCTAssertEqual(sensorContexts.filter(\.shouldWriteHistory).count, 1)

        XCTAssertEqual(cpuProbe.readCount, 5)
        XCTAssertEqual(gpuProbe.readCount, 5)
        XCTAssertEqual(memoryProbe.readCount, 1)
        XCTAssertEqual(ssdProbe.readCount, 1)
        XCTAssertEqual(batteryProbe.readCount, 1)
        XCTAssertEqual(systemProbe.readCount, 3)
        XCTAssertEqual(sensorProbe.readCount, 3)
    }

    func testSleepAndWakePauseAndResumeSequenceDoesNotPublishSystemGapsAndRedetectsCapabilities() async {
        let sessionID = UUID()
        let probe = ManualTickProbe(
            id: "cpu-primary",
            domain: .cpu,
            source: .hidSensors,
            defaultMetricName: TemperatureMetricName.cpuHottest
        )
        let repository = InMemorySessionHistoryRepository()
        let capabilityService = TemperatureCapabilityService(
            probes: [probe],
            repository: repository,
            clock: { Date() }
        )

        let bus = SampleBus()
        let collector = SchedulerTestCollector()
        _ = await bus.subscribe { event in
            await collector.record(event)
        }

        let clock = DeterministicClock(initial: Date(timeIntervalSince1970: 200))
        let scheduler = TemperatureScheduler(
            probes: [probe],
            capabilityService: capabilityService,
            bus: bus,
            clock: { clock.now() },
            minimumTickInterval: 9999
        )

        await scheduler.start(sessionID: sessionID)

        await scheduler.tick(at: clock.advance(by: 5))
        let afterFirstTick = await collector.snapshot()
        XCTAssertEqual(afterFirstTick.capabilityReasons, [.appStart])
        XCTAssertEqual(afterFirstTick.eventKinds.last, "samples")

        await scheduler.pause(reason: .systemSleep, at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))
        XCTAssertEqual(probe.readCount, 1)

        await scheduler.resume(reason: .systemWake, at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))

        let events = await collector.snapshot()
        XCTAssertEqual(events.capabilityReasons, [.appStart, .wake])
        XCTAssertEqual(events.gapTypes, [])
        XCTAssertEqual(probe.detectCount, 2)
        XCTAssertGreaterThanOrEqual(probe.readCount, 2)
    }

    func testManualPauseAndResumeStillPublishManualGaps() async {
        let sessionID = UUID()
        let probe = ManualTickProbe(
            id: "cpu-primary",
            domain: .cpu,
            source: .hidSensors,
            defaultMetricName: TemperatureMetricName.cpuHottest
        )
        let repository = InMemorySessionHistoryRepository()
        let capabilityService = TemperatureCapabilityService(
            probes: [probe],
            repository: repository,
            clock: { Date() }
        )

        let bus = SampleBus()
        let collector = SchedulerTestCollector()
        _ = await bus.subscribe { event in
            await collector.record(event)
        }

        let clock = DeterministicClock(initial: Date(timeIntervalSince1970: 250))
        let scheduler = TemperatureScheduler(
            probes: [probe],
            capabilityService: capabilityService,
            bus: bus,
            clock: { clock.now() },
            minimumTickInterval: 9999
        )

        await scheduler.start(sessionID: sessionID)
        await scheduler.pause(reason: .manual, at: clock.advance(by: 1))
        await scheduler.resume(reason: .manual, at: clock.advance(by: 1))

        let events = await collector.snapshot()
        XCTAssertEqual(
            events.gapTypes,
            [.systemSleepStarted, .systemSleepEnded]
        )
        XCTAssertEqual(events.capabilityReasons, [.appStart])
    }

    func testConsecutiveReadFailuresPublishStaleAndProbeStaleGap() async {
        let sessionID = UUID()
        let probe = SequenceTemperatureProbe(
            id: "cpu-primary",
            domain: .cpu,
            source: .hidSensors,
            defaultMetricName: TemperatureMetricName.cpuHottest,
            sampleSequences: [
                [
                    sample(validAt: Date(timeIntervalSince1970: 10), domain: .cpu)
                ],
                [
                    invalidSample(at: Date(timeIntervalSince1970: 15), domain: .cpu)
                ],
                [
                    invalidSample(at: Date(timeIntervalSince1970: 20), domain: .cpu)
                ],
            ]
        )
        let repository = InMemorySessionHistoryRepository()
        let capabilityService = TemperatureCapabilityService(
            probes: [probe],
            repository: repository,
            clock: { Date() }
        )

        let bus = SampleBus()
        let collector = SchedulerTestCollector()
        _ = await bus.subscribe { event in
            await collector.record(event)
        }

        let clock = DeterministicClock(initial: Date(timeIntervalSince1970: 10))
        let scheduler = TemperatureScheduler(
            probes: [probe],
            capabilityService: capabilityService,
            bus: bus,
            clock: { clock.now() },
            minimumTickInterval: 9999,
            staleFailureThreshold: 1,
            policyForDomain: { _ in
                TemperatureSamplingPolicy(realtimeInterval: 5, historyInterval: 10, minimumInterval: 5)
            }
        )

        await scheduler.start(sessionID: sessionID)
        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))

        let events = await collector.snapshot()
        XCTAssertEqual(events.staleSamplesCount, 1)
        XCTAssertEqual(Set(events.gapTypes), Set([.probeReadFailed, .probeStale]))
        XCTAssertEqual(probe.readCount, 3)
    }

    func testUnsupportedAndReadFailedSamplesAreStillPublished() async {
        let sessionID = UUID()
        let probe = SequenceTemperatureProbe(
            id: "gpu-primary",
            domain: .gpu,
            source: .hidSensors,
            defaultMetricName: TemperatureMetricName.gpuHottest,
            sampleSequences: [
                [
                    invalidSample(
                        at: Date(timeIntervalSince1970: 10),
                        domain: .gpu,
                        metricName: TemperatureMetricName.gpuHottest,
                        quality: .unsupported
                    )
                ],
                [
                    invalidSample(
                        at: Date(timeIntervalSince1970: 20),
                        domain: .gpu,
                        metricName: TemperatureMetricName.gpuHottest,
                        source: .hidSensors,
                        quality: .readFailed
                    )
                ],
            ]
        )

        let repository = InMemorySessionHistoryRepository()
        let capabilityService = TemperatureCapabilityService(
            probes: [probe],
            repository: repository,
            clock: { Date() }
        )

        let bus = SampleBus()
        let collector = SchedulerTestCollector()
        _ = await bus.subscribe { event in
            await collector.record(event)
        }

        let clock = DeterministicClock(initial: Date(timeIntervalSince1970: 100))
        let scheduler = TemperatureScheduler(
            probes: [probe],
            capabilityService: capabilityService,
            bus: bus,
            clock: { clock.now() },
            minimumTickInterval: 9999,
            policyForDomain: { _ in
                TemperatureSamplingPolicy(realtimeInterval: 10, historyInterval: 30, minimumInterval: 10)
            }
        )

        await scheduler.start(sessionID: sessionID)
        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 10))

        let events = await collector.snapshot()
        XCTAssertEqual(events.sampleQualitiesByProbeID["gpu-primary"], [.unsupported, .readFailed])
        XCTAssertEqual(probe.readCount, 2)
    }

    func testReadFailedHistoryCyclePublishesProbeReadFailedGap() async {
        let sessionID = UUID()
        let probe = SequenceTemperatureProbe(
            id: "cpu-primary",
            domain: .cpu,
            source: .hidSensors,
            defaultMetricName: TemperatureMetricName.cpuHottest,
            sampleSequences: [
                [
                    sample(validAt: Date(timeIntervalSince1970: 10), domain: .cpu)
                ],
                [],
            ]
        )

        let repository = InMemorySessionHistoryRepository()
        let capabilityService = TemperatureCapabilityService(
            probes: [probe],
            repository: repository,
            clock: { Date() }
        )

        let bus = SampleBus()
        let collector = SchedulerTestCollector()
        _ = await bus.subscribe { event in
            await collector.record(event)
        }

        let clock = DeterministicClock(initial: Date(timeIntervalSince1970: 10))
        let scheduler = TemperatureScheduler(
            probes: [probe],
            capabilityService: capabilityService,
            bus: bus,
            clock: { clock.now() },
            minimumTickInterval: 9999,
            staleFailureThreshold: 99,
            policyForDomain: { _ in
                TemperatureSamplingPolicy(realtimeInterval: 5, historyInterval: 10, minimumInterval: 5)
            }
        )

        await scheduler.start(sessionID: sessionID)
        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))
        await scheduler.tick(at: clock.advance(by: 5))

        let events = await collector.snapshot()
        XCTAssertEqual(events.gapTypes, [.probeReadFailed])
    }

    func testSchedulerKeepsDistinctProbesWithinSameDomain() async {
        let sessionID = UUID()
        let ambientProbe = ManualTickProbe(
            id: "sensor-ambient",
            domain: .sensor,
            source: .hidSensors,
            defaultMetricName: "sensor.temperature.ambient"
        )
        let enclosureProbe = ManualTickProbe(
            id: "sensor-enclosure",
            domain: .sensor,
            source: .hidSensors,
            defaultMetricName: "sensor.temperature.enclosure"
        )
        let repository = InMemorySessionHistoryRepository()
        let capabilityService = TemperatureCapabilityService(
            probes: [ambientProbe, enclosureProbe],
            repository: repository,
            clock: { Date() }
        )
        let bus = SampleBus()
        let collector = SchedulerTestCollector()
        _ = await bus.subscribe { event in
            await collector.record(event)
        }

        let clock = DeterministicClock(initial: Date(timeIntervalSince1970: 300))
        let scheduler = TemperatureScheduler(
            probes: [ambientProbe, enclosureProbe],
            capabilityService: capabilityService,
            bus: bus,
            clock: { clock.now() },
            minimumTickInterval: 9999,
            policyForDomain: { _ in
                TemperatureSamplingPolicy(realtimeInterval: 10, historyInterval: 30, minimumInterval: 10)
            }
        )

        await scheduler.start(sessionID: sessionID)
        await scheduler.tick(at: clock.advance(by: 10))

        let events = await collector.snapshot()
        XCTAssertEqual(ambientProbe.readCount, 1)
        XCTAssertEqual(enclosureProbe.readCount, 1)
        XCTAssertEqual(events.sampleContextsByProbeID["sensor-ambient"]?.count, 1)
        XCTAssertEqual(events.sampleContextsByProbeID["sensor-enclosure"]?.count, 1)
    }
}

private final class ManualTickProbe: @unchecked Sendable, TemperatureProbe {
    let id: String
    let domain: TemperatureDomain
    let source: TemperatureSource
    let defaultMetricName: String
    private let lock = NSLock()
    private var _readCount = 0
    private var _detectCount = 0

    init(id: String, domain: TemperatureDomain, source: TemperatureSource, defaultMetricName: String) {
        self.id = id
        self.domain = domain
        self.source = source
        self.defaultMetricName = defaultMetricName
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

        return [try! TemperatureSample.makeValid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: defaultMetricName,
            domain: domain,
            deviceID: "cpu",
            displayName: "cpu.temperature",
            valueCelsius: 60,
            source: source
        )]
    }
}

private final class SequenceTemperatureProbe: @unchecked Sendable, TemperatureProbe {
    let id: String
    let domain: TemperatureDomain
    let source: TemperatureSource
    let defaultMetricName: String
    private let sampleSequences: [[TemperatureSample]]
    private let lock = NSLock()
    private var _readCount = 0
    private var readIndex: Int = 0

    init(
        id: String,
        domain: TemperatureDomain,
        source: TemperatureSource,
        defaultMetricName: String,
        sampleSequences: [[TemperatureSample]]
    ) {
        self.id = id
        self.domain = domain
        self.source = source
        self.defaultMetricName = defaultMetricName
        self.sampleSequences = sampleSequences
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
        let sampleSequence: [TemperatureSample] = lock.withLock {
            let nextSamples = sampleSequences.isEmpty ? [] : sampleSequences[min(readIndex, sampleSequences.count - 1)]
            _readCount += 1
            if sampleSequences.isEmpty == false {
                readIndex += 1
            }
            return nextSamples
        }

        if sampleSequence.isEmpty {
            return []
        }

        let samples = sampleSequence
        return samples.map { sample in
            try! TemperatureSample(
                id: UUID(),
                sessionID: sessionID,
                timestamp: timestamp,
                metricName: sample.metricName,
                domain: sample.domain,
                deviceID: sample.deviceID,
                displayName: sample.displayName,
                valueCelsius: sample.valueCelsius,
                source: sample.source,
                quality: sample.quality,
                rawKey: sample.rawKey,
                errorCode: sample.errorCode,
                attributes: sample.attributes
            )
        }
    }
}

private func sample(validAt time: Date, domain: TemperatureDomain) -> TemperatureSample {
    try! TemperatureSample.makeValid(
        sessionID: UUID(),
        timestamp: time,
        metricName: TemperatureMetricName.cpuHottest,
        domain: domain,
        deviceID: "\(domain.rawValue)-device",
        displayName: "\(domain.rawValue) temperature",
        valueCelsius: 60,
        source: .hidSensors
    )
}

private func invalidSample(
    at time: Date,
    domain: TemperatureDomain,
    metricName: String,
    source: TemperatureSource = .hidSensors,
    quality: TemperatureQuality = .readFailed
) -> TemperatureSample {
    try! TemperatureSample.makeInvalid(
        sessionID: UUID(),
        timestamp: time,
        metricName: metricName,
        domain: domain,
        deviceID: "\(domain.rawValue)-device",
        displayName: "\(domain.rawValue) temperature",
        quality: quality,
        source: source,
        errorCode: quality.rawValue
    )
}

private actor SleepIntervalRecorder {
    private(set) var intervals: [TimeInterval] = []
    private let expectation: XCTestExpectation

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func record(_ interval: TimeInterval) {
        intervals.append(interval)
        expectation.fulfill()
    }

    var firstInterval: TimeInterval? {
        intervals.first
    }
}

private actor SchedulerBox {
    private var scheduler: TemperatureScheduler?

    func set(_ scheduler: TemperatureScheduler) {
        self.scheduler = scheduler
    }

    func stop(at timestamp: Date) async {
        await scheduler?.stop(at: timestamp)
    }
}

private func invalidSample(at time: Date, domain: TemperatureDomain) -> TemperatureSample {
    invalidSample(
        at: time,
        domain: domain,
        metricName: TemperatureMetricName.cpuHottest
    )
}

private final class DeterministicClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(initial: Date) {
        self.value = initial
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) -> Date {
        lock.lock()
        value = value.addingTimeInterval(interval)
        let current = value
        lock.unlock()
        return current
    }
}

private actor SchedulerTestCollector {
    struct Snapshot {
        let eventKinds: [String]
        let sampleContexts: [SampleContext]
        let sampleContextsByProbeID: [String: [SampleContext]]
        let sampleQualitiesByProbeID: [String: [TemperatureQuality]]
        let capabilityReasons: [CapabilityDetectionReason]
        let gapTypes: [TimelineEventType]
        let staleSamplesCount: Int
    }

    private var eventKinds: [String] = []
    private var sampleContexts: [SampleContext] = []
    private var sampleContextsByProbeID: [String: [SampleContext]] = [:]
    private var sampleQualitiesByProbeID: [String: [TemperatureQuality]] = [:]
    private var capabilityReasons: [CapabilityDetectionReason] = []
    private var gapEventTypes: [TimelineEventType] = []
    private var staleSamplesCount: Int = 0

    func record(_ event: TemperatureSampleEvent) {
        switch event {
        case .samples(let samples, let context):
            eventKinds.append("samples")
            sampleContexts.append(context)
            sampleContextsByProbeID[context.probeID, default: []].append(context)
            sampleQualitiesByProbeID[context.probeID, default: []].append(
                contentsOf: samples.map(\.quality)
            )
            staleSamplesCount += samples.filter { $0.quality == .stale }.count
        case .capabilities(_, let reason):
            eventKinds.append("capabilities")
            capabilityReasons.append(reason)
        case .gap(let event):
            eventKinds.append("gap")
            gapEventTypes.append(event.eventType)
        }
    }

    func kinds() -> [String] {
        eventKinds
    }

    func snapshot() -> Snapshot {
        Snapshot(
            eventKinds: eventKinds,
            sampleContexts: sampleContexts,
            sampleContextsByProbeID: sampleContextsByProbeID,
            sampleQualitiesByProbeID: sampleQualitiesByProbeID,
            capabilityReasons: capabilityReasons,
            gapTypes: gapEventTypes,
            staleSamplesCount: staleSamplesCount
        )
    }
}
