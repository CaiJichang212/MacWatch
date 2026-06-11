import Foundation

public final class TemperatureMonitorService {
    private let probes: [any TemperatureProbe]
    private let repository: any SessionHistoryRepository
    private let clock: @Sendable () -> Date
    private var cachedCapabilitiesByDomain: [TemperatureDomain: TemperatureCapability] = [:]

    public init(
        probes: [any TemperatureProbe],
        repository: any SessionHistoryRepository,
        clock: @escaping @Sendable () -> Date
    ) {
        self.probes = probes
        self.repository = repository
        self.clock = clock
    }

    public func detectCapabilities(sessionID: UUID) async -> LiveTemperatureState {
        let timestamp = clock()
        let capabilities = await resolvedCapabilities(
            sessionID: sessionID,
            timestamp: timestamp,
            persistToHistory: true
        )

        return LiveTemperatureState(
            sessionID: sessionID,
            updatedAt: timestamp,
            samplesByMetricName: [:],
            capabilitiesByDomain: capabilities,
            hottestValidSample: nil
        )
    }

    public func sampleOnce(sessionID: UUID) async -> LiveTemperatureState {
        let timestamp = clock()
        let capabilities = await resolvedCapabilities(
            sessionID: sessionID,
            timestamp: timestamp,
            persistToHistory: false
        )

        var collectedSamples: [TemperatureSample] = []
        for probe in probes {
            let samples = await probe.read(sessionID: sessionID, at: timestamp)
            let resolvedSamples = samples.isEmpty
                ? [makeReadFailedSample(for: probe, sessionID: sessionID, timestamp: timestamp)]
                : samples
            let validatedSamples = resolvedSamples.map { validatedSample($0) }

            for sample in validatedSamples {
                collectedSamples.append(sample)
                do {
                    try repository.insertSample(sample)
                } catch {
                    await recordHistoryWriteFailure(
                        sessionID: sessionID,
                        timestamp: timestamp,
                        domain: sample.domain,
                        metricName: sample.metricName,
                        message: error.localizedDescription
                    )
                }
            }

            if samples.isEmpty {
                await recordProbeReadFailure(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    domain: probe.domain,
                    metricName: probe.defaultMetricName,
                    message: "Probe returned no samples."
                )
            }
        }

        let samplesByMetricName = Dictionary(
            uniqueKeysWithValues: collectedSamples.map { ($0.metricName, $0) }
        )

        return LiveTemperatureState(
            sessionID: sessionID,
            updatedAt: timestamp,
            samplesByMetricName: samplesByMetricName,
            capabilitiesByDomain: capabilities,
            hottestValidSample: hottestValidSample(from: collectedSamples)
        )
    }

    private func resolvedCapabilities(
        sessionID: UUID,
        timestamp: Date,
        persistToHistory: Bool
    ) async -> [TemperatureDomain: TemperatureCapability] {
        var capabilitiesByDomain = cachedCapabilitiesByDomain

        for probe in probes {
            if persistToHistory == false, capabilitiesByDomain[probe.domain] != nil {
                continue
            }

            let capability = await probe.detect(sessionID: sessionID, at: timestamp)
            capabilitiesByDomain[probe.domain] = capability
            cachedCapabilitiesByDomain[probe.domain] = capability

            guard persistToHistory else {
                continue
            }

            do {
                try repository.insertCapability(capability)
            } catch {
                await recordHistoryWriteFailure(
                    sessionID: sessionID,
                    timestamp: timestamp,
                    domain: capability.domain,
                    metricName: nil,
                    message: error.localizedDescription
                )
            }
        }

        return capabilitiesByDomain
    }

    private func hottestValidSample(from samples: [TemperatureSample]) -> TemperatureSample? {
        samples
            .filter { $0.quality == .valid && TemperatureMetricName.participatesInGlobalHottest($0.metricName) }
            .max { lhs, rhs in
                (lhs.valueCelsius ?? -.infinity) < (rhs.valueCelsius ?? -.infinity)
            }
    }

    private func makeReadFailedSample(
        for probe: any TemperatureProbe,
        sessionID: UUID,
        timestamp: Date
    ) -> TemperatureSample {
        let displayName = probe.defaultMetricName
            .split(separator: ".")
            .map(String.init)
            .joined(separator: " ")

        return try! TemperatureSample.makeInvalid(
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: probe.defaultMetricName,
            domain: probe.domain,
            deviceID: "\(probe.domain.rawValue)-unavailable",
            displayName: displayName,
            quality: .readFailed,
            source: probe.source,
            errorCode: "probeReturnedNoSamples",
            attributes: [
                "attemptedMetricName": probe.defaultMetricName,
                "sourcePriority": probe.source.rawValue,
            ]
        )
    }

    private func validatedSample(_ sample: TemperatureSample) -> TemperatureSample {
        guard sample.quality == .valid else {
            return sample
        }
        guard let valueCelsius = sample.valueCelsius,
              TemperatureReadingValidator.isValidCelsius(valueCelsius) else {
            return invalidSample(from: sample)
        }

        return sample
    }

    private func invalidSample(from sample: TemperatureSample) -> TemperatureSample {
        return try! TemperatureSample.makeInvalid(
            id: UUID(),
            sessionID: sample.sessionID,
            timestamp: sample.timestamp,
            metricName: sample.metricName,
            domain: sample.domain,
            deviceID: sample.deviceID,
            displayName: sample.displayName,
            quality: .readFailed,
            source: sample.source,
            errorCode: "invalidTemperature",
            attributes: [
                "reason": "invalidTemperature",
                "source": sample.source.rawValue,
            ]
        )
    }

    private func recordProbeReadFailure(
        sessionID: UUID,
        timestamp: Date,
        domain: TemperatureDomain,
        metricName: String,
        message: String
    ) async {
        do {
            try repository.insertTimelineEvent(
                TimelineEvent(
                    id: UUID(),
                    sessionID: sessionID,
                    eventType: .probeReadFailed,
                    startedAt: timestamp,
                    endedAt: timestamp,
                    domain: domain,
                    metricName: metricName,
                    reasonCode: "probeReturnedNoSamples",
                    message: message
                )
            )
        } catch {}
    }

    private func recordHistoryWriteFailure(
        sessionID: UUID,
        timestamp: Date,
        domain: TemperatureDomain?,
        metricName: String?,
        message: String
    ) async {
        do {
            try repository.insertTimelineEvent(
                TimelineEvent(
                    id: UUID(),
                    sessionID: sessionID,
                    eventType: .historyWriteFailed,
                    startedAt: timestamp,
                    endedAt: timestamp,
                    domain: domain,
                    metricName: metricName,
                    reasonCode: "historyWriteFailed",
                    message: message
                )
            )
        } catch {}
    }
}
