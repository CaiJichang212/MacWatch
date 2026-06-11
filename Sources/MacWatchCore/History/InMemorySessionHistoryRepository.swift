import Foundation

public final class InMemorySessionHistoryRepository: SessionHistoryRepository {
    private struct SeriesKey: Hashable {
        let metricName: String
        let domain: TemperatureDomain
    }

    private var sessions: [UUID: MonitoringSession] = [:]
    private var currentSessionID: UUID?
    private var samplesBySession: [UUID: [TemperatureSample]] = [:]
    private var capabilitiesBySession: [UUID: [TemperatureCapability]] = [:]
    private var timelineEventsBySession: [UUID: [TimelineEvent]] = [:]
    private let queryService = SessionHistoryQueryService()

    public init() {}

    public func beginSession(
        _ session: MonitoringSession,
        clearingPreviousHistory: Bool
    ) throws {
        if clearingPreviousHistory {
            samplesBySession.removeAll()
            capabilitiesBySession.removeAll()
            timelineEventsBySession.removeAll()
        }

        sessions[session.id] = session
        currentSessionID = session.id
    }

    public func currentSession() throws -> MonitoringSession? {
        guard let currentSessionID else {
            return nil
        }

        return sessions[currentSessionID]
    }

    public func endSession(id: UUID, endedAt: Date) throws {
        guard var session = sessions[id] else {
            return
        }

        session.endedAt = endedAt
        sessions[id] = session
    }

    public func insertSample(_ sample: TemperatureSample) throws {
        samplesBySession[sample.sessionID, default: []].append(sample)
    }

    public func insertCapability(_ capability: TemperatureCapability) throws {
        capabilitiesBySession[capability.sessionID, default: []].append(capability)
    }

    public func insertTimelineEvent(_ event: TimelineEvent) throws {
        timelineEventsBySession[event.sessionID, default: []].append(event)
        timelineEventsBySession[event.sessionID]?.sort { $0.startedAt < $1.startedAt }
    }

    public func updateTimelineEvent(id: UUID, endedAt: Date) throws {
        for sessionID in timelineEventsBySession.keys {
            guard var events = timelineEventsBySession[sessionID],
                  let index = events.firstIndex(where: { $0.id == id }) else {
                continue
            }

            let existing = events[index]
            events[index] = TimelineEvent(
                id: existing.id,
                sessionID: existing.sessionID,
                eventType: existing.eventType,
                startedAt: existing.startedAt,
                endedAt: endedAt,
                domain: existing.domain,
                metricName: existing.metricName,
                reasonCode: existing.reasonCode,
                message: existing.message
            )
            timelineEventsBySession[sessionID] = events
            return
        }
    }

    public func timelineEvents(sessionID: UUID) throws -> [TimelineEvent] {
        timelineEventsBySession[sessionID, default: []]
            .sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.startedAt < rhs.startedAt
            }
    }

    public func query(_ query: TemperatureQuery) throws -> [TemperatureSeries] {
        let samples = storedSamples(sessionID: query.sessionID)
        let events = timelineEventsBySession[query.sessionID, default: []]
        let requestedKeys = resolveSeriesKeys(for: query, samples: samples)

        return requestedKeys
            .sorted { lhs, rhs in
                if lhs.domain == rhs.domain {
                    return lhs.metricName < rhs.metricName
                }
                return lhs.domain.rawValue < rhs.domain.rawValue
            }
            .map { key in
                try! queryService.makeSeries(
                    sessionID: query.sessionID,
                    domain: key.domain,
                    metricName: key.metricName,
                    start: query.start,
                    end: query.end,
                    maxPoints: query.maxPoints,
                    samples: samples,
                    timelineEvents: events
                )
            }
    }

    public func query(
        sessionID: UUID,
        domain: TemperatureDomain,
        metricName: String,
        range: TemperatureHistoryRange,
        now: Date,
        maxPoints: Int
    ) throws -> TemperatureSeries {
        guard let session = sessions[sessionID] else {
            return TemperatureSeries(metricName: metricName, domain: domain, samples: [], gaps: [])
        }

        return try queryService.makeSeries(
            session: session,
            domain: domain,
            metricName: metricName,
            range: range,
            now: now,
            maxPoints: maxPoints,
            samples: storedSamples(sessionID: sessionID),
            timelineEvents: timelineEventsBySession[sessionID, default: []]
        )
    }

    public func clearCurrentSessionHistory(at clearedAt: Date) throws {
        guard let currentSessionID else {
            return
        }
        samplesBySession[currentSessionID] = []
        capabilitiesBySession[currentSessionID] = []
        timelineEventsBySession[currentSessionID] = [
            TimelineEvent(
                id: UUID(),
                sessionID: currentSessionID,
                eventType: .historyCleared,
                startedAt: clearedAt,
                endedAt: clearedAt,
                domain: nil,
                metricName: nil,
                reasonCode: "historyCleared",
                message: "history cleared"
            )
        ]
    }

    public func samples(sessionID: UUID) throws -> [TemperatureSample] {
        storedSamples(sessionID: sessionID)
    }

    public func capabilities(sessionID: UUID) throws -> [TemperatureCapability] {
        capabilitiesBySession[sessionID, default: []]
    }

    private func storedSamples(sessionID: UUID) -> [TemperatureSample] {
        samplesBySession[sessionID, default: []]
    }

    private func resolveSeriesKeys(
        for query: TemperatureQuery,
        samples: [TemperatureSample]
    ) -> Set<SeriesKey> {
        var keys = Set(samples.map { SeriesKey(metricName: $0.metricName, domain: $0.domain) })

        if let metricNames = query.metricNames, metricNames.isEmpty == false {
            for metricName in metricNames {
                for domain in inferredDomains(for: metricName, constrainedTo: query.domains) {
                    keys.insert(SeriesKey(metricName: metricName, domain: domain))
                }
            }
        } else if keys.isEmpty {
            // Gap-only queries still need a series shell so the UI can render a break.
            for domain in query.domains {
                keys.insert(SeriesKey(metricName: defaultMetricName(for: domain), domain: domain))
            }
        }

        return keys
    }

    private func inferredDomains(
        for metricName: String,
        constrainedTo domains: [TemperatureDomain]
    ) -> [TemperatureDomain] {
        guard let prefix = metricName.split(separator: ".").first,
              let inferredDomain = TemperatureDomain(rawValue: String(prefix)),
              domains.contains(inferredDomain) else {
            return domains
        }

        return [inferredDomain]
    }

    private func defaultMetricName(for domain: TemperatureDomain) -> String {
        switch domain {
        case .cpu:
            return "cpu.temperature.hottest"
        case .gpu:
            return "gpu.temperature.hottest"
        case .memory:
            return "memory.temperature.proximity"
        case .ssd:
            return "ssd.temperature.internal"
        case .battery:
            return "battery.temperature"
        case .system:
            return "system.temperature.hottest"
        case .sensor:
            return TemperatureMetricName.sensorTemperatureRaw
        }
    }
}
