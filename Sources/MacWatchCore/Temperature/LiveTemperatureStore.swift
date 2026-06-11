import Foundation

public final actor LiveTemperatureStore {
    private struct State {
        var sessionID: UUID?
        var updatedAt: Date?
        var samplesByMetricName: [String: TemperatureSample] = [:]
        var capabilitiesByDomain: [TemperatureDomain: TemperatureCapability] = [:]
        var lastValidSamplesByMetricName: [String: TemperatureSample] = [:]
        var lastUpdatedAtByMetricName: [String: Date] = [:]
    }

    private let policyForDomain: (TemperatureDomain) -> TemperatureSamplingPolicy
    private var state = State()

    public init(policyForDomain: @escaping (TemperatureDomain) -> TemperatureSamplingPolicy = { TemperatureSamplingPolicy.default(for: $0) }) {
        self.policyForDomain = policyForDomain
    }

    public func apply(_ event: TemperatureSampleEvent) async -> LiveTemperatureState {
        switch event {
        case let .samples(samples, context):
            applySamples(samples, context: context)
        case let .capabilities(capabilities, reason: _):
            state.capabilitiesByDomain = state.capabilitiesByDomain.merging(capabilities) { _, new in new }
            if state.sessionID == nil {
                state.sessionID = capabilities.values.first?.sessionID
            }
        case let .gap(event):
            if state.sessionID == nil {
                state.sessionID = event.sessionID
            }
            state.updatedAt = event.startedAt
        }

        return await currentState()
    }

    public func markStale(now: Date) async -> LiveTemperatureState {
        for (metricName, lastUpdate) in state.lastUpdatedAtByMetricName {
            guard let sample = state.samplesByMetricName[metricName] else {
                continue
            }
            guard sample.quality == .valid else {
                continue
            }

            let policy = policyForDomain(sample.domain)
            let staleInterval = policy.realtimeInterval * policy.staleMultiplier
            let elapsed = now.timeIntervalSince(lastUpdate)
            if elapsed <= staleInterval {
                continue
            }

            let sessionID = state.sessionID ?? sample.sessionID

            state.samplesByMetricName[metricName] = staleSample(from: sample, at: now, sessionID: sessionID)
            state.updatedAt = now
        }

        return await currentState()
    }

    public func currentState() async -> LiveTemperatureState {
        let sessionID = state.sessionID ?? UUID()
        return LiveTemperatureState(
            sessionID: sessionID,
            updatedAt: state.updatedAt,
            samplesByMetricName: state.samplesByMetricName,
            capabilitiesByDomain: state.capabilitiesByDomain,
            hottestValidSample: hottestValidSample(),
            lastValidSamplesByMetricName: state.lastValidSamplesByMetricName,
            lastUpdatedAtByMetricName: state.lastUpdatedAtByMetricName
        )
    }

    private func applySamples(_ samples: [TemperatureSample], context: SampleContext) {
        state.sessionID = state.sessionID ?? context.sessionID
        state.updatedAt = context.sampledAt
        for raw in samples {
            let sample = validated(raw)
            state.lastUpdatedAtByMetricName[sample.metricName] = sample.timestamp
            state.samplesByMetricName[sample.metricName] = sample

            if sample.quality == .valid {
                state.lastValidSamplesByMetricName[sample.metricName] = sample
            }
        }
    }

    private func validated(_ sample: TemperatureSample) -> TemperatureSample {
        if sample.quality != .valid {
            return sample
        }

        guard let valueCelsius = sample.valueCelsius,
              TemperatureReadingValidator.isValidCelsius(valueCelsius) else {
            return invalidSample(from: sample, reason: "invalidTemperature")
        }

        return sample
    }

    private func invalidSample(from sample: TemperatureSample, reason: String) -> TemperatureSample {
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

    private func staleSample(from sample: TemperatureSample, at timestamp: Date, sessionID: UUID) -> TemperatureSample {
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
            errorCode: "stale",
            attributes: [
                "reason": "stale",
            ]
        )
    }

    private func hottestValidSample() -> TemperatureSample? {
        state.samplesByMetricName.values
            .filter { $0.quality == .valid && TemperatureMetricName.participatesInGlobalHottest($0.metricName) }
            .max { lhs, rhs in
                (lhs.valueCelsius ?? -.infinity) < (rhs.valueCelsius ?? -.infinity)
            }
    }
}
