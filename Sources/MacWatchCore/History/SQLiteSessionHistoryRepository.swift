import Foundation

public final class SQLiteSessionHistoryRepository: SessionHistoryRepository {
    private let store: SessionHistoryStore
    private let queryService: SessionHistoryQueryService

    public init(
        store: SessionHistoryStore,
        queryService: SessionHistoryQueryService = SessionHistoryQueryService()
    ) {
        self.store = store
        self.queryService = queryService
    }

    public func beginSession(_ session: MonitoringSession, clearingPreviousHistory: Bool) throws {
        _ = clearingPreviousHistory
        try store.replaceWithNewSession(session)
    }

    public func currentSession() throws -> MonitoringSession? {
        try store.currentSession()
    }

    public func endSession(id: UUID, endedAt: Date) throws {
        try store.endSession(id: id, endedAt: endedAt)
    }

    public func insertSample(_ sample: TemperatureSample) throws {
        try store.insertSample(sample)
    }

    public func insertCapability(_ capability: TemperatureCapability) throws {
        try store.insertCapability(capability)
    }

    public func insertTimelineEvent(_ event: TimelineEvent) throws {
        try store.insertTimelineEvent(event)
    }

    public func updateTimelineEvent(id: UUID, endedAt: Date) throws {
        try store.updateTimelineEvent(id: id, endedAt: endedAt)
    }

    public func timelineEvents(sessionID: UUID) throws -> [TimelineEvent] {
        try store.timelineEvents(
            sessionID: sessionID,
            start: .distantPast,
            end: .distantFuture
        )
    }

    public func query(_ query: TemperatureQuery) throws -> [TemperatureSeries] {
        let samples = try store.samples(matching: query)
        let events = try store.timelineEvents(
            sessionID: query.sessionID,
            start: query.start,
            end: query.end
        )
        let keys = resolveSeriesKeys(query: query, samples: samples)

        return try keys.map { key in
            try queryService.makeSeries(
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
        .sorted { lhs, rhs in
            if lhs.domain == rhs.domain {
                return lhs.metricName < rhs.metricName
            }
            return lhs.domain.rawValue < rhs.domain.rawValue
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
        guard let session = try currentSession(), session.id == sessionID else {
            return TemperatureSeries(metricName: metricName, domain: domain, samples: [], gaps: [])
        }

        let start = range.resolveStart(sessionStartedAt: session.startedAt, now: now)
        let rawQuery = try TemperatureQuery(
            sessionID: sessionID,
            domains: [domain],
            metricNames: [metricName],
            start: start,
            end: now,
            maxPoints: maxPoints
        )
        let samples = try store.samples(matching: rawQuery)
        let events = try store.timelineEvents(sessionID: sessionID, start: start, end: now)

        return try queryService.makeSeries(
            session: session,
            domain: domain,
            metricName: metricName,
            range: range,
            now: now,
            maxPoints: maxPoints,
            samples: samples,
            timelineEvents: events
        )
    }

    public func clearCurrentSessionHistory(at clearedAt: Date) throws {
        guard let session = try currentSession() else {
            return
        }
        try store.clearHistory(sessionID: session.id, clearedAt: clearedAt)
    }

    private func resolveSeriesKeys(
        query: TemperatureQuery,
        samples: [TemperatureSample]
    ) -> [SeriesKey] {
        var keys = Set(samples.map { SeriesKey(metricName: $0.metricName, domain: $0.domain) })

        if let metricNames = query.metricNames, metricNames.isEmpty == false {
            for metricName in metricNames {
                let domains = inferredDomains(for: metricName, constrainedTo: query.domains)
                for domain in domains {
                    keys.insert(SeriesKey(metricName: metricName, domain: domain))
                }
            }
        } else if keys.isEmpty {
            for domain in query.domains {
                keys.insert(SeriesKey(metricName: defaultMetricName(for: domain), domain: domain))
            }
        }

        return Array(keys)
    }

    private func inferredDomains(
        for metricName: String,
        constrainedTo domains: [TemperatureDomain]
    ) -> [TemperatureDomain] {
        guard let prefix = metricName.split(separator: ".").first,
              let domain = TemperatureDomain(rawValue: String(prefix)),
              domains.contains(domain) else {
            return domains
        }
        return [domain]
    }

    private func defaultMetricName(for domain: TemperatureDomain) -> String {
        switch domain {
        case .cpu:
            return TemperatureMetricName.cpuHottest
        case .gpu:
            return TemperatureMetricName.gpuHottest
        case .memory:
            return TemperatureMetricName.memoryProximity
        case .ssd:
            return TemperatureMetricName.ssdInternal
        case .battery:
            return TemperatureMetricName.battery
        case .system:
            return TemperatureMetricName.systemHottest
        case .sensor:
            return TemperatureMetricName.sensorTemperatureRaw
        }
    }
}

private struct SeriesKey: Hashable {
    let metricName: String
    let domain: TemperatureDomain
}
