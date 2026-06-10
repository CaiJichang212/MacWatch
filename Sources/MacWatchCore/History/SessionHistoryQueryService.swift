import Foundation

public struct SessionHistoryQueryService: Sendable {
    private let downsampler: TemperatureSeriesDownsampler

    public init(
        downsampler: TemperatureSeriesDownsampler = TemperatureSeriesDownsampler()
    ) {
        self.downsampler = downsampler
    }

    public func makeSeries(
        session: MonitoringSession,
        domain: TemperatureDomain,
        metricName: String,
        range: TemperatureHistoryRange,
        now: Date,
        maxPoints: Int,
        samples: [TemperatureSample],
        timelineEvents: [TimelineEvent]
    ) throws -> TemperatureSeries {
        guard maxPoints > 0 else {
            throw TemperatureModelError.invalidQuery
        }
        guard now >= session.startedAt else {
            return TemperatureSeries(
                metricName: metricName,
                domain: domain,
                samples: [],
                gaps: [],
                statistics: .empty
            )
        }

        let start = range.resolveStart(sessionStartedAt: session.startedAt, now: now)
        return try makeSeries(
            sessionID: session.id,
            domain: domain,
            metricName: metricName,
            start: start,
            end: now,
            maxPoints: maxPoints,
            samples: samples,
            timelineEvents: timelineEvents
        )
    }

    public func makeSeries(
        sessionID: UUID,
        domain: TemperatureDomain,
        metricName: String,
        start: Date,
        end: Date,
        maxPoints: Int,
        samples: [TemperatureSample],
        timelineEvents: [TimelineEvent]
    ) throws -> TemperatureSeries {
        guard maxPoints > 0, start <= end else {
            throw TemperatureModelError.invalidQuery
        }

        let filteredSamples = samples
            .filter { sample in
                sample.sessionID == sessionID &&
                sample.domain == domain &&
                sample.metricName == metricName &&
                sample.timestamp >= start &&
                sample.timestamp <= end
            }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.timestamp < rhs.timestamp
            }

        let filteredGaps = timelineEvents
            .filter { event in
                event.sessionID == sessionID &&
                event.eventType != .historyCleared &&
                overlaps(event: event, start: start, end: end) &&
                (event.domain == nil || event.domain == domain) &&
                (event.metricName == nil || event.metricName == metricName) &&
                isGapEvent(event)
            }
            .sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.startedAt < rhs.startedAt
            }

        let statistics = TemperatureSeriesStatistics.compute(samples: filteredSamples)
        let reducedSamples = downsampler.reduce(samples: filteredSamples, gaps: filteredGaps, maxPoints: maxPoints)

        return TemperatureSeries(
            metricName: metricName,
            domain: domain,
            samples: reducedSamples,
            gaps: filteredGaps,
            statistics: statistics
        )
    }

    private func overlaps(event: TimelineEvent, start: Date, end: Date) -> Bool {
        let eventEnd = event.endedAt ?? event.startedAt
        return event.startedAt <= end && eventEnd >= start
    }

    private func isGapEvent(_ event: TimelineEvent) -> Bool {
        switch event.eventType {
        case .appStarted,
             .appTerminating,
             .systemSleepEnded,
             .historyCleared:
            return false
        case .systemSleepStarted,
             .probeReadFailed,
             .probeUnsupported,
             .probeStale,
             .historyWriteFailed:
            return true
        }
    }
}
