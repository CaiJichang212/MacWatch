import Foundation
import MacWatchCore
import StatsAdapter

enum AcceptanceImmediateRunner {
    static func runSynchronously(_ scenario: AcceptanceScenario) -> AcceptanceReport {
        switch scenario {
        case .probeStatus:
            return runProbeStatus()
        case .trendQuery:
            return runTrendQuerySynchronously()
        case .sleepWakeSimulated:
            return runSleepWakeSynchronously()
        case .dashboardOpen, .popupOpen, .firstRunGuide,
             .launchMainWindowOnStartEnabled, .launchMainWindowOnStartDisabled,
             .resourcesSteadyState:
            let startedAt = Date()
            return AcceptanceReport(
                scenario: scenario,
                passed: false,
                startedAt: startedAt,
                durationMs: 0,
                metrics: [:],
                failures: ["uiScenarioRequiresApplicationLaunch"]
            )
        }
    }

    private static func runProbeStatus() -> AcceptanceReport {
        let startedAt = Date()
        let output = TemperatureProbeDiagnostics.readOnceJSONLines(
            sessionID: UUID(),
            timestamp: startedAt
        )

        let decoder = JSONDecoder()
        let records = output
            .split(separator: "\n")
            .compactMap { line -> TemperatureProbeDiagnosticRecord? in
                guard let data = line.data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(TemperatureProbeDiagnosticRecord.self, from: data)
            }

        let requiredDomains: [String] = [
            TemperatureDomain.cpu.rawValue,
            TemperatureDomain.gpu.rawValue,
            TemperatureDomain.ssd.rawValue,
            TemperatureDomain.battery.rawValue,
            TemperatureDomain.system.rawValue,
            TemperatureDomain.sensor.rawValue,
        ]

        var metrics: [String: String] = [:]
        let validation = validateProbeStatusRecords(records, requiredDomains: requiredDomains)
        metrics.merge(validation.metrics) { _, new in new }
        let failures = validation.failures

        let durationMs = Date().timeIntervalSince(startedAt) * 1_000
        return AcceptanceReport(
            scenario: .probeStatus,
            passed: failures.isEmpty,
            startedAt: startedAt,
            durationMs: durationMs,
            metrics: metrics,
            failures: failures
        )
    }

    struct ProbeStatusValidationResult {
        let metrics: [String: String]
        let failures: [String]
    }

    static func validateProbeStatusRecords(
        _ records: [TemperatureProbeDiagnosticRecord],
        requiredDomains: [String] = [
            TemperatureDomain.cpu.rawValue,
            TemperatureDomain.gpu.rawValue,
            TemperatureDomain.ssd.rawValue,
            TemperatureDomain.battery.rawValue,
            TemperatureDomain.system.rawValue,
            TemperatureDomain.sensor.rawValue,
        ]
    ) -> ProbeStatusValidationResult {
        var metrics: [String: String] = [:]
        var failures: [String] = []

        let recordsByDomain = Dictionary(grouping: records, by: \.domain)
        let cpuHasValid = recordsByDomain[TemperatureDomain.cpu.rawValue, default: []]
            .contains { $0.quality == TemperatureQuality.valid.rawValue }
        metrics["cpu.hasValidSample"] = cpuHasValid ? "true" : "false"

        let hasMemoryRecord = records.contains { $0.domain == "memory" }
        metrics["memory.absent"] = hasMemoryRecord ? "false" : "true"
        if hasMemoryRecord {
            failures.append("memory.unexpectedDomain")
        }

        for domain in requiredDomains {
            guard let domainRecords = recordsByDomain[domain], domainRecords.isEmpty == false else {
                metrics["\(domain).status"] = "missing"
                failures.append("\(domain).missingStatus")
                continue
            }

            let resolvedQuality = resolvedQualityText(for: domainRecords)
            metrics["\(domain).status"] = resolvedQuality

            let invalidRecordsWithValue = domainRecords.contains { record in
                record.quality != TemperatureQuality.valid.rawValue && record.valueCelsius != nil
            }
            metrics["\(domain).invalidValueIsNil"] = invalidRecordsWithValue ? "false" : "true"
            if invalidRecordsWithValue {
                failures.append("\(domain).invalidStatusHasValue")
            }

            if resolvedQuality != TemperatureQuality.valid.rawValue &&
                resolvedQuality != TemperatureQuality.unsupported.rawValue &&
                resolvedQuality != TemperatureQuality.readFailed.rawValue {
                failures.append("\(domain).unexpectedQuality.\(resolvedQuality)")
            }
        }

        validateCPUAndGPURecords(recordsByDomain: recordsByDomain, metrics: &metrics, failures: &failures)

        return ProbeStatusValidationResult(metrics: metrics, failures: failures)
    }

    private static func validateCPUAndGPURecords(
        recordsByDomain: [String: [TemperatureProbeDiagnosticRecord]],
        metrics: inout [String: String],
        failures: inout [String]
    ) {
        validatePrimaryTemperatureRecords(
            domain: TemperatureDomain.cpu.rawValue,
            hottestMetricName: TemperatureMetricName.cpuHottest,
            averageMetricName: TemperatureMetricName.cpuAverage,
            deniedRawKeyPrefixes: ["PMU ", "PMU2 ", "SOC", "PMGR"],
            recordsByDomain: recordsByDomain,
            metrics: &metrics,
            failures: &failures
        )
        validatePrimaryTemperatureRecords(
            domain: TemperatureDomain.gpu.rawValue,
            hottestMetricName: TemperatureMetricName.gpuHottest,
            averageMetricName: TemperatureMetricName.gpuAverage,
            deniedRawKeyPrefixes: [],
            recordsByDomain: recordsByDomain,
            metrics: &metrics,
            failures: &failures
        )
    }

    private static func validatePrimaryTemperatureRecords(
        domain: String,
        hottestMetricName: String,
        averageMetricName: String,
        deniedRawKeyPrefixes: [String],
        recordsByDomain: [String: [TemperatureProbeDiagnosticRecord]],
        metrics: inout [String: String],
        failures: inout [String]
    ) {
        let domainRecords = recordsByDomain[domain, default: []]
        let validHottestRecords = domainRecords.filter {
            $0.metricName == hottestMetricName && $0.quality == TemperatureQuality.valid.rawValue
        }

        let deniedRawKeys = validHottestRecords.compactMap(\.rawKey).filter { rawKey in
            deniedRawKeyPrefixes.contains { rawKey.hasPrefix($0) }
        }
        metrics["\(domain).rawKeyBoundary"] = deniedRawKeys.isEmpty ? "passed" : "failed"
        failures.append(contentsOf: deniedRawKeys.map { "\(domain).deniedRawKey.\($0)" })

        guard validHottestRecords.isEmpty == false else {
            metrics["\(domain).averagePresentForValidHottest"] = "notApplicable"
            return
        }

        let hasValidAverage = domainRecords.contains {
            $0.metricName == averageMetricName && $0.quality == TemperatureQuality.valid.rawValue
        }
        metrics["\(domain).averagePresentForValidHottest"] = hasValidAverage ? "true" : "false"
        if hasValidAverage == false {
            failures.append("\(domain).averageMissingForValidHottest")
        }
    }

    private static func runTrendQuerySynchronously() -> AcceptanceReport {
        let semaphore = DispatchSemaphore(value: 0)
        var report = AcceptanceReport(
            scenario: .trendQuery,
            passed: false,
            startedAt: Date(),
            durationMs: 0,
            metrics: [:],
            failures: ["trendQueryDidNotStart"]
        )

        Task {
            report = await runTrendQuery()
            semaphore.signal()
        }
        semaphore.wait()
        return report
    }

    private static func runSleepWakeSynchronously() -> AcceptanceReport {
        let semaphore = DispatchSemaphore(value: 0)
        var report = AcceptanceReport(
            scenario: .sleepWakeSimulated,
            passed: false,
            startedAt: Date(),
            durationMs: 0,
            metrics: [:],
            failures: ["sleepWakeScenarioDidNotStart"]
        )

        Task {
            report = await runSleepWakeSimulated()
            semaphore.signal()
        }
        semaphore.wait()
        return report
    }

    private static func resolvedQualityText(for records: [TemperatureProbeDiagnosticRecord]) -> String {
        let order: [String] = [
            TemperatureQuality.valid.rawValue,
            TemperatureQuality.unsupported.rawValue,
            TemperatureQuality.readFailed.rawValue,
            TemperatureQuality.stale.rawValue,
        ]

        for quality in order {
            if records.contains(where: { $0.quality == quality }) {
                return quality
            }
        }

        return records.first?.quality ?? "missing"
    }

    private static func runTrendQuery() async -> AcceptanceReport {
        let startedAt = Date()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macwatch-stage7-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        do {
            let store = SQLiteSessionHistoryStore(databaseURL: fileURL)
            try store.initialize()
            let repository = SQLiteSessionHistoryRepository(store: store)

            let sessionID = UUID()
            let sessionStart = Date(timeIntervalSince1970: 1_000)
            let session = MonitoringSession(id: sessionID, startedAt: sessionStart)
            try repository.beginSession(session, clearingPreviousHistory: true)

            let gapStart = sessionStart.addingTimeInterval(1_200)
            let gapEnd = sessionStart.addingTimeInterval(1_500)

            for second in 0..<3_000 {
                let timestamp = sessionStart.addingTimeInterval(Double(second))
                let sample = try TemperatureSample.makeValid(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    metricName: TemperatureMetricName.cpuHottest,
                    domain: .cpu,
                    deviceID: "cpu-package",
                    displayName: "CPU Hottest",
                    valueCelsius: 40 + Double(second % 20),
                    source: .hidSensors
                )
                try repository.insertSample(sample)
            }

            try repository.insertTimelineEvent(
                TimelineEvent(
                    id: UUID(),
                    sessionID: sessionID,
                    eventType: .systemSleepStarted,
                    startedAt: gapStart,
                    endedAt: gapEnd,
                    domain: .cpu,
                    metricName: TemperatureMetricName.cpuHottest,
                    reasonCode: "sleep",
                    message: "system sleep started"
                )
            )

            let executor = TemperatureSeriesQueryExecutor(repository: repository)
            let queryStart = DispatchTime.now().uptimeNanoseconds
            let series = try await executor.query(
                sessionID: sessionID,
                domain: .cpu,
                metricName: TemperatureMetricName.cpuHottest,
                range: .allSession,
                now: sessionStart.addingTimeInterval(3_600),
                maxPoints: 2_000
            )
            let queryDurationMs = Double(DispatchTime.now().uptimeNanoseconds - queryStart) / 1_000_000

            let passed = queryDurationMs < 1_000 &&
                series.gaps.count == 1 &&
                series.samples.count <= 2_000

            return AcceptanceReport(
                scenario: .trendQuery,
                passed: passed,
                startedAt: startedAt,
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                metrics: [
                    "queryDurationMs": String(format: "%.2f", queryDurationMs),
                    "sampleCount": "\(series.samples.count)",
                    "gapCount": "\(series.gaps.count)",
                    "statisticsValidSampleCount": "\(series.statistics.validSampleCount)",
                ],
                failures: passed ? [] : trendQueryFailures(durationMs: queryDurationMs, series: series)
            )
        } catch {
            return AcceptanceReport(
                scenario: .trendQuery,
                passed: false,
                startedAt: startedAt,
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                metrics: [:],
                failures: ["trendQueryFailed.\(error.localizedDescription)"]
            )
        }
    }

    private static func runSleepWakeSimulated() async -> AcceptanceReport {
        let startedAt = Date()
        let repository = InMemorySessionHistoryRepository()
        let lifecycleService = SessionLifecycleService(repository: repository)

        do {
            let probe = AcceptanceCountingProbe(
                domain: .cpu,
                source: .hidSensors,
                metricName: TemperatureMetricName.cpuHottest,
                valueCelsius: 51
            )
            let bus = SampleBus()
            _ = await bus.subscribe { event in
                switch event {
                case let .samples(samples, context):
                    if context.shouldWriteHistory {
                        for sample in samples {
                            try repository.insertSample(sample)
                        }
                    }
                case let .gap(event):
                    try repository.insertTimelineEvent(event)
                case .capabilities:
                    return
                }
            }
            let capabilityService = TemperatureCapabilityService(
                probes: [probe],
                repository: repository,
                clock: { Date() }
            )
            let scheduler = TemperatureScheduler(
                probes: [probe],
                capabilityService: capabilityService,
                bus: bus,
                clock: { Date() },
                minimumTickInterval: 0.02,
                policyForDomain: { _ in
                    TemperatureSamplingPolicy(
                        realtimeInterval: 0.05,
                        historyInterval: 0.1,
                        minimumInterval: 0.05
                    )
                }
            )

            let session = try lifecycleService.handle(.launched)
            guard let session else {
                throw TemperatureModelError.invalidQuery
            }

            await scheduler.start(sessionID: session.id)
            try? await Task.sleep(nanoseconds: 150_000_000)
            let readsBeforeSleep = probe.readCount

            _ = try lifecycleService.handle(.willSleep)
            await scheduler.pause(reason: .systemSleep, at: Date())
            try? await Task.sleep(nanoseconds: 60_000_000)

            _ = try lifecycleService.handle(.didWake)
            await scheduler.resume(reason: .systemWake, at: Date())
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await scheduler.stop(at: Date())

            let readsAfterWake = probe.readCount
            let events = try repository.timelineEvents(sessionID: session.id)
            let sleepGapEnded = events.contains {
                $0.eventType == .systemSleepStarted && $0.endedAt != nil
            }
            let sleepEndedCount = events.filter { $0.eventType == .systemSleepEnded }.count
            let passed = readsAfterWake > readsBeforeSleep &&
                sleepGapEnded &&
                sleepEndedCount == 1

            return AcceptanceReport(
                scenario: .sleepWakeSimulated,
                passed: passed,
                startedAt: startedAt,
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                metrics: [
                    "readsBeforeSleep": "\(readsBeforeSleep)",
                    "readsAfterWake": "\(readsAfterWake)",
                    "sleepGapEnded": sleepGapEnded ? "true" : "false",
                    "sleepEndedEventCount": "\(sleepEndedCount)",
                ],
                failures: passed ? [] : sleepWakeFailures(
                    readsBeforeSleep: readsBeforeSleep,
                    readsAfterWake: readsAfterWake,
                    sleepGapEnded: sleepGapEnded,
                    sleepEndedCount: sleepEndedCount
                )
            )
        } catch {
            return AcceptanceReport(
                scenario: .sleepWakeSimulated,
                passed: false,
                startedAt: startedAt,
                durationMs: Date().timeIntervalSince(startedAt) * 1_000,
                metrics: [:],
                failures: ["sleepWakeScenarioFailed.\(error.localizedDescription)"]
            )
        }
    }

    private static func trendQueryFailures(durationMs: Double, series: TemperatureSeries) -> [String] {
        var failures: [String] = []
        if durationMs >= 1_000 {
            failures.append("trendQueryExceedsThreshold")
        }
        if series.gaps.count != 1 {
            failures.append("trendQueryMissingGap")
        }
        if series.samples.count > 2_000 {
            failures.append("trendQueryExceedsPointBudget")
        }
        return failures
    }

    private static func sleepWakeFailures(
        readsBeforeSleep: Int,
        readsAfterWake: Int,
        sleepGapEnded: Bool,
        sleepEndedCount: Int
    ) -> [String] {
        var failures: [String] = []
        if readsAfterWake <= readsBeforeSleep {
            failures.append("samplingDidNotResumeAfterWake")
        }
        if sleepGapEnded == false {
            failures.append("sleepGapDidNotEnd")
        }
        if sleepEndedCount == 0 {
            failures.append("missingSleepEndedEvent")
        } else if sleepEndedCount > 1 {
            failures.append("duplicateSleepEndedEvent")
        }
        return failures
    }
}

private final class AcceptanceCountingProbe: TemperatureProbe, @unchecked Sendable {
    let id: String
    let domain: TemperatureDomain
    let source: TemperatureSource
    let defaultMetricName: String

    private let valueCelsius: Double
    private let lock = NSLock()
    private var _readCount = 0

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
                source: source
            )
        ]
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
