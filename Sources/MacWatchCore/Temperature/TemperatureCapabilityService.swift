import Foundation

public enum CapabilityDetectionReason: String, Sendable {
    case appStart
    case wake
    case manualRefresh
}

public final actor TemperatureCapabilityService {
    private let probes: [any TemperatureProbe]
    private let repository: SessionHistoryRepository
    private let clock: @Sendable () -> Date

    public init(
        probes: [any TemperatureProbe],
        repository: SessionHistoryRepository,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.probes = probes
        self.repository = repository
        self.clock = clock
    }

    public func detectAll(
        sessionID: UUID,
        reason: CapabilityDetectionReason
    ) async -> [TemperatureDomain: TemperatureCapability] {
        let timestamp = clock()
        var capabilitiesByDomain: [TemperatureDomain: TemperatureCapability] = [:]

        for probe in probes {
            let capability = await probe.detect(sessionID: sessionID, at: timestamp)
            let normalizedCapability = normalize(capability)
            if let existing = capabilitiesByDomain[probe.domain] {
                capabilitiesByDomain[probe.domain] = preferredCapability(existing, normalizedCapability)
            } else {
                capabilitiesByDomain[probe.domain] = normalizedCapability
            }

            do {
                try repository.insertCapability(normalizedCapability)
            } catch {
                try? repository.insertTimelineEvent(
                    TimelineEvent(
                        id: UUID(),
                        sessionID: sessionID,
                        eventType: .historyWriteFailed,
                        startedAt: timestamp,
                        endedAt: nil,
                        domain: probe.domain,
                        metricName: nil,
                        reasonCode: "historyWriteFailed",
                        message: error.localizedDescription
                    )
                )
            }
        }

        return capabilitiesByDomain
    }

    private func normalize(_ capability: TemperatureCapability) -> TemperatureCapability {
        if capability.supported == false {
            return TemperatureCapability(
                id: UUID(),
                sessionID: capability.sessionID,
                domain: capability.domain,
                source: capability.source,
                supported: false,
                readable: false,
                reasonCode: capability.reasonCode.isEmpty ? "unsupported" : capability.reasonCode,
                reasonMessage: capability.reasonMessage.isEmpty ? "unsupported" : capability.reasonMessage,
                rawKey: capability.rawKey,
                detectedAt: capability.detectedAt,
                updatedAt: capability.updatedAt
            )
        }

        if capability.readable == false && capability.reasonCode.isEmpty {
            return TemperatureCapability(
                id: capability.id,
                sessionID: capability.sessionID,
                domain: capability.domain,
                source: capability.source,
                supported: capability.supported,
                readable: false,
                reasonCode: "readFailed",
                reasonMessage: capability.reasonMessage.isEmpty ? "readFailed" : capability.reasonMessage,
                rawKey: capability.rawKey,
                detectedAt: capability.detectedAt,
                updatedAt: capability.updatedAt
            )
        }

        return capability
    }

    private func preferredCapability(
        _ lhs: TemperatureCapability,
        _ rhs: TemperatureCapability
    ) -> TemperatureCapability {
        let lhsScore = capabilityScore(lhs)
        let rhsScore = capabilityScore(rhs)

        if lhsScore == rhsScore {
            return lhs.detectedAt <= rhs.detectedAt ? lhs : rhs
        }

        return lhsScore > rhsScore ? lhs : rhs
    }

    private func capabilityScore(_ capability: TemperatureCapability) -> Int {
        if capability.supported && capability.readable {
            return 3
        }
        if capability.supported {
            return 2
        }
        return 1
    }
}
