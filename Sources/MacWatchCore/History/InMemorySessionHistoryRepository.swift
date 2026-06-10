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
        let filteredSamples = storedSamples(sessionID: query.sessionID)
            .filter { sample in
                query.domains.contains(sample.domain) &&
                (query.metricNames?.contains(sample.metricName) ?? true) &&
                sample.timestamp >= query.start &&
                sample.timestamp <= query.end
            }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.timestamp < rhs.timestamp
            }

        let groupedSamples = Dictionary(
            grouping: filteredSamples,
            by: { SeriesKey(metricName: $0.metricName, domain: $0.domain) }
        )

        let requestedKeys = resolveSeriesKeys(
            for: query,
            sampleKeys: Set(groupedSamples.keys)
        )

        return requestedKeys
            .sorted { lhs, rhs in
                if lhs.domain == rhs.domain {
                    return lhs.metricName < rhs.metricName
                }
                return lhs.domain.rawValue < rhs.domain.rawValue
            }
            .map { key in
                let gaps = timelineEventsBySession[query.sessionID, default: []]
                    .filter { event in
                        isGapEvent(event) &&
                        overlaps(query: query, event: event) &&
                        (event.domain == nil || event.domain == key.domain) &&
                        (event.metricName == nil || event.metricName == key.metricName)
                    }
                    .sorted { $0.startedAt < $1.startedAt }
                let samples = limitedSamples(
                    groupedSamples[key, default: []],
                    maxPoints: query.maxPoints
                )

                return TemperatureSeries(
                    metricName: key.metricName,
                    domain: key.domain,
                    samples: samples,
                    gaps: gaps
                )
            }
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

    private func overlaps(query: TemperatureQuery, event: TimelineEvent) -> Bool {
        let eventEnd = event.endedAt ?? event.startedAt
        return event.startedAt <= query.end && eventEnd >= query.start
    }

    private func resolveSeriesKeys(
        for query: TemperatureQuery,
        sampleKeys: Set<SeriesKey>
    ) -> Set<SeriesKey> {
        var keys = sampleKeys

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
            return "sensor.temperature.raw"
        }
    }

    private func limitedSamples(
        _ samples: [TemperatureSample],
        maxPoints: Int
    ) -> [TemperatureSample] {
        guard samples.count > maxPoints else {
            return samples
        }

        return Array(samples.suffix(maxPoints))
    }

    private func isGapEvent(_ event: TimelineEvent) -> Bool {
        switch event.eventType {
        case .systemSleepStarted,
             .probeReadFailed,
             .probeUnsupported,
             .probeStale,
             .historyWriteFailed:
            return true
        case .appStarted,
             .appTerminating,
             .systemSleepEnded,
             .historyCleared:
            return false
        }
    }
}
