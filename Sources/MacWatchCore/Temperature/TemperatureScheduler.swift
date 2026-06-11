import Foundation

public enum SchedulerPauseReason: String, Sendable {
    case manual
    case systemSleep
}

public enum SchedulerResumeReason: String, Sendable {
    case manual
    case systemWake
}

public final actor TemperatureScheduler {
    private struct ProbeState {
        let probe: any TemperatureProbe
        let policy: TemperatureSamplingPolicy
        var nextRealtimeAt: Date
        var nextHistoryAt: Date
        var staleDueAt: Date?
        var consecutiveFailures: Int
        var lastValidSample: TemperatureSample?
        var isStalePublished: Bool
        let probeID: String
    }

    private let probes: [any TemperatureProbe]
    private let probeByID: [String: any TemperatureProbe]
    private let orderedProbeIDs: [String]
    private let capabilityService: TemperatureCapabilityService
    private let bus: SampleBus
    private let clock: @Sendable () -> Date
    private let minimumTickInterval: TimeInterval
    private let pausedSleepInterval: TimeInterval
    private let shouldAutoTick: Bool
    private let staleFailureThreshold: Int
    private let policyForDomain: (TemperatureDomain) -> TemperatureSamplingPolicy
    private let sleeper: @Sendable (TimeInterval) async -> Void

    private var statesByProbeID: [String: ProbeState] = [:]
    private var runLoopTask: Task<Void, Never>?
    private var isRunning = false
    private var isPaused = false
    private var sessionID: UUID?

    public init(
        probes: [any TemperatureProbe],
        capabilityService: TemperatureCapabilityService,
        bus: SampleBus,
        clock: @escaping @Sendable () -> Date = Date.init,
        minimumTickInterval: TimeInterval = 0.05,
        pausedSleepInterval: TimeInterval = 1,
        staleFailureThreshold: Int = 3,
        policyForDomain: @escaping (TemperatureDomain) -> TemperatureSamplingPolicy = { TemperatureSamplingPolicy.default(for: $0) },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = TemperatureScheduler.defaultSleep
    ) {
        self.probes = TemperatureScheduler.deduplicated(probes)
        self.capabilityService = capabilityService
        self.bus = bus
        self.clock = clock
        self.minimumTickInterval = max(minimumTickInterval, 0.001)
        self.pausedSleepInterval = max(pausedSleepInterval, self.minimumTickInterval)
        self.shouldAutoTick = minimumTickInterval < 60
        self.staleFailureThreshold = max(staleFailureThreshold, 1)
        self.policyForDomain = policyForDomain
        self.sleeper = sleep

        var byID: [String: any TemperatureProbe] = [:]
        var ordered: [String] = []
        for probe in self.probes {
            if byID[probe.id] == nil {
                ordered.append(probe.id)
            }
            byID[probe.id] = probe
        }
        self.probeByID = byID
        self.orderedProbeIDs = ordered
    }

    public func start(sessionID: UUID) async {
        self.sessionID = sessionID
        isRunning = true
        isPaused = false
        statesByProbeID.removeAll(keepingCapacity: true)

        let timestamp = clock()
        for probe in probes {
            let policy = policyForDomain(probe.domain)
            statesByProbeID[probe.id] = ProbeState(
                probe: probe,
                policy: policy,
                nextRealtimeAt: timestamp,
                nextHistoryAt: timestamp,
                staleDueAt: nil,
                consecutiveFailures: 0,
                lastValidSample: nil,
                isStalePublished: false,
                probeID: probe.id
            )
        }

        let capabilities = await capabilityService.detectAll(sessionID: sessionID, reason: .appStart)
        await bus.publish(.capabilities(capabilities, reason: .appStart))

        if shouldAutoTick {
            runLoopTask?.cancel()
            runLoopTask = Task { [weak self] in
                await self?.runLoop()
            }
        }
    }

    public func pause(reason: SchedulerPauseReason, at timestamp: Date) async {
        guard isRunning, !isPaused else {
            return
        }

        isPaused = true
        let currentSessionID = sessionID
        if reason == .manual {
            await publishGap(
                eventType: .systemSleepStarted,
                sessionID: currentSessionID,
                at: timestamp,
                reasonCode: reason.rawValue,
                message: "paused",
                domain: nil,
                metricName: nil
            )
        }
    }

    public func resume(reason: SchedulerResumeReason, at timestamp: Date) async {
        guard isRunning else {
            return
        }

        isPaused = false
        let currentSessionID = sessionID

        if reason == .systemWake, let currentSessionID {
            let capabilities = await capabilityService.detectAll(sessionID: currentSessionID, reason: .wake)
            await bus.publish(.capabilities(capabilities, reason: .wake))
        }

        if reason == .manual {
            await publishGap(
                eventType: .systemSleepEnded,
                sessionID: currentSessionID,
                at: timestamp,
                reasonCode: reason.rawValue,
                message: "resumed",
                domain: nil,
                metricName: nil
            )
        }

        let now = clock()
        for probeID in orderedProbeIDs {
            guard var state = statesByProbeID[probeID] else {
                continue
            }

            state.nextRealtimeAt = now
            state.nextHistoryAt = min(state.nextHistoryAt, now)
            state.isStalePublished = false
            if let lastValidSample = state.lastValidSample {
                state.staleDueAt = lastValidSample.timestamp
                    .addingTimeInterval(state.policy.realtimeInterval * state.policy.staleMultiplier)
            }

            statesByProbeID[probeID] = state
        }

        if shouldAutoTick && runLoopTask == nil {
            runLoopTask = Task { [weak self] in
                await self?.runLoop()
            }
        }
    }

    public func stop(at _: Date) async {
        guard isRunning else {
            return
        }

        isRunning = false
        isPaused = true
        runLoopTask?.cancel()
        runLoopTask = nil

        sessionID = nil
        statesByProbeID = [:]
    }

    public func tick(at timestamp: Date) async {
        guard isRunning, !isPaused else {
            return
        }

        guard let sessionID else {
            return
        }

        await processTick(sessionID: sessionID, at: timestamp)
    }

    private func runLoop() async {
        while isRunning && !Task.isCancelled {
            if isPaused {
                await sleeper(pausedSleepInterval)
                continue
            }

            let now = clock()
            guard let sessionID else {
                return
            }
            await processTick(sessionID: sessionID, at: now)
            guard isRunning, !Task.isCancelled else {
                return
            }
            await sleeper(nextWakeInterval(after: clock()))
        }
    }

    private func processTick(sessionID: UUID, at now: Date) async {
        for probeID in orderedProbeIDs {
            guard var state = statesByProbeID[probeID] else {
                continue
            }
            guard let probe = probeByID[probeID] else {
                continue
            }

            if now >= state.nextRealtimeAt {
                state.nextRealtimeAt = now.addingTimeInterval(state.policy.realtimeInterval)
                let shouldWriteHistory = now >= state.nextHistoryAt
                if shouldWriteHistory {
                    state.nextHistoryAt = now.addingTimeInterval(state.policy.historyInterval)
                }

                let samples = await readSamples(
                    probe: probe,
                    sessionID: sessionID,
                    at: now
                )
                let sanitizedSamples = samples.map { sanitizeSample($0, sessionID: sessionID) }
                let hasValidSamples = sanitizedSamples.contains { $0.quality == .valid }
                let defaultMetricValidSample = sanitizedSamples
                    .filter { $0.metricName == probe.defaultMetricName }
                    .max(by: { lhs, rhs in
                        (lhs.valueCelsius ?? -.infinity) < (rhs.valueCelsius ?? -.infinity)
                    })
                let representativeValidSample = defaultMetricValidSample
                    ?? sanitizedSamples.first(where: { $0.quality == .valid })

                if hasValidSamples {
                    state.consecutiveFailures = 0
                    state.lastValidSample = representativeValidSample
                    state.isStalePublished = false
                    if let fallbackValid = representativeValidSample {
                        state.staleDueAt = fallbackValid.timestamp
                            .addingTimeInterval(state.policy.realtimeInterval * state.policy.staleMultiplier)
                    }
                } else {
                    state.consecutiveFailures += 1
                }

                await bus.publish(.samples(
                    sanitizedSamples,
                    context: SampleContext(
                        sessionID: sessionID,
                        probeID: state.probeID,
                        sampledAt: now,
                        shouldWriteHistory: shouldWriteHistory
                    )
                ))

                if shouldWriteHistory, hasValidSamples == false {
                    await publishReadFailureGap(
                        for: state,
                        samples: sanitizedSamples,
                        at: now,
                        sessionID: sessionID
                    )
                }

                if shouldPublishStale(state: state, at: now) {
                    await publishStaleSample(for: probe.domain, state: &state, at: now, sessionID: sessionID)
                }
            } else if shouldPublishStale(state: state, at: now) {
                await publishStaleSample(for: probe.domain, state: &state, at: now, sessionID: sessionID)
            }

            statesByProbeID[probeID] = state
        }
    }

    private func readSamples(
        probe: any TemperatureProbe,
        sessionID: UUID,
        at timestamp: Date
    ) async -> [TemperatureSample] {
        let samples = await probe.read(sessionID: sessionID, at: timestamp)
        if samples.isEmpty {
            return [
                makeReadFailedSample(for: probe, sessionID: sessionID, timestamp: timestamp)
            ]
        }

        return samples
    }

    private func sanitizeSample(_ sample: TemperatureSample, sessionID _: UUID) -> TemperatureSample {
        guard sample.quality == .valid else {
            return sample
        }

        guard let valueCelsius = sample.valueCelsius,
              TemperatureReadingValidator.isValidCelsius(valueCelsius) else {
            return invalidSample(from: sample, reason: "invalidTemperature")
        }

        return sample
    }

    private func shouldPublishStale(state: ProbeState, at now: Date) -> Bool {
        guard state.isStalePublished == false else {
            return false
        }
        guard state.lastValidSample != nil else {
            return false
        }
        guard let staleDueAt = state.staleDueAt else {
            return false
        }
        if state.consecutiveFailures >= staleFailureThreshold {
            return true
        }
        return now >= staleDueAt
    }

    private func publishStaleSample(
        for domain: TemperatureDomain,
        state: inout ProbeState,
        at now: Date,
        sessionID: UUID
    ) async {
        guard let lastValidSample = state.lastValidSample else {
            return
        }

        let staleSample = makeStaleSample(from: lastValidSample, sessionID: sessionID, at: now)
        state.isStalePublished = true
        state.staleDueAt = nil
        await bus.publish(.samples(
            [staleSample],
            context: SampleContext(
                sessionID: sessionID,
                probeID: state.probeID,
                sampledAt: now,
                shouldWriteHistory: false
            )
        ))

        await publishGap(
            eventType: .probeStale,
            sessionID: sessionID,
            at: now,
            reasonCode: "stale",
            message: "\(domain.rawValue) sample stale",
            domain: domain,
            metricName: lastValidSample.metricName
        )
    }

    private func publishGap(
        eventType: TimelineEventType,
        sessionID: UUID?,
        at timestamp: Date,
        reasonCode: String,
        message: String,
        domain: TemperatureDomain?,
        metricName: String?
    ) async {
        guard let sessionID else {
            return
        }

        await bus.publish(
            .gap(
                TimelineEvent(
                    id: UUID(),
                    sessionID: sessionID,
                    eventType: eventType,
                    startedAt: timestamp,
                    endedAt: nil,
                    domain: domain,
                    metricName: metricName,
                    reasonCode: reasonCode,
                    message: message
                )
            )
        )
    }

    private func publishReadFailureGap(
        for state: ProbeState,
        samples: [TemperatureSample],
        at timestamp: Date,
        sessionID: UUID
    ) async {
        let representativeSample = samples.first
        await publishGap(
            eventType: .probeReadFailed,
            sessionID: sessionID,
            at: timestamp,
            reasonCode: representativeSample?.errorCode ?? "readFailed",
            message: "\(state.probeID) read failed",
            domain: state.probe.domain,
            metricName: representativeSample?.metricName ?? state.probe.defaultMetricName
        )
    }

    private func invalidSample(
        from sample: TemperatureSample,
        reason: String
    ) -> TemperatureSample {
        try! TemperatureSample.makeInvalid(
            id: UUID(),
            sessionID: sample.sessionID,
            timestamp: sample.timestamp,
            metricName: sample.metricName,
            domain: sample.domain,
            deviceID: sample.deviceID,
            displayName: sample.displayName,
            quality: .readFailed,
            source: sample.source,
            errorCode: reason,
            attributes: [
                "reason": reason,
                "originalSource": sample.source.rawValue,
            ]
        )
    }

    private func makeReadFailedSample(
        for probe: any TemperatureProbe,
        sessionID: UUID,
        timestamp: Date
    ) -> TemperatureSample {
        try! TemperatureSample.makeInvalid(
            id: UUID(),
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: probe.defaultMetricName,
            domain: probe.domain,
            deviceID: "\(probe.domain.rawValue)-unavailable",
            displayName: probe.defaultMetricName.split(separator: ".").joined(separator: " "),
            quality: .readFailed,
            source: probe.source,
            errorCode: "probeReturnedNoSamples",
            attributes: [
                "attemptedMetricName": probe.defaultMetricName,
                "sourcePriority": probe.source.rawValue,
            ]
        )
    }

    private func makeStaleSample(
        from sample: TemperatureSample,
        sessionID: UUID,
        at timestamp: Date
    ) -> TemperatureSample {
        try! TemperatureSample.makeInvalid(
            id: UUID(),
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: sample.metricName,
            domain: sample.domain,
            deviceID: sample.deviceID,
            displayName: sample.displayName,
            quality: .stale,
            valueCelsius: nil,
            source: sample.source,
            rawKey: sample.rawKey,
            errorCode: "stale",
            attributes: [
                "reason": "stale",
            ]
        )
    }

    private func nextWakeInterval(after now: Date) -> TimeInterval {
        let nextDates = statesByProbeID.values.flatMap { state -> [Date] in
            var dates = [state.nextRealtimeAt]
            if state.isStalePublished == false, let staleDueAt = state.staleDueAt {
                dates.append(staleDueAt)
            }
            return dates
        }

        guard let nextDeadline = nextDates.min() else {
            return minimumTickInterval
        }

        return max(minimumTickInterval, nextDeadline.timeIntervalSince(now))
    }

    public static func defaultSleep(_ interval: TimeInterval) async {
        let nanos = UInt64(max(interval, 0.001) * 1_000_000_000)
        do {
            try await Task.sleep(nanoseconds: nanos)
        } catch {
            // ignore
        }
    }

    private static func deduplicated(_ probes: [any TemperatureProbe]) -> [any TemperatureProbe] {
        var seen = Set<String>()
        return probes.compactMap { probe in
            if seen.insert(probe.id).inserted {
                return probe
            }
            return nil
        }
    }
}
