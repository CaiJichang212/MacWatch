import Foundation

public enum TimelineEventType: String, CaseIterable, Codable, Sendable {
    case appStarted = "app.started"
    case appTerminating = "app.terminating"
    case systemSleepStarted = "system.sleep.started"
    case systemSleepEnded = "system.sleep.ended"
    case probeReadFailed = "probe.read_failed"
    case probeUnsupported = "probe.unsupported"
    case probeStale = "probe.stale"
    case historyWriteFailed = "history.write_failed"
    case historyCleared = "history.cleared"
}

public struct TimelineEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let eventType: TimelineEventType
    public let startedAt: Date
    public let endedAt: Date?
    public let domain: TemperatureDomain?
    public let metricName: String?
    public let reasonCode: String?
    public let message: String?

    public init(
        id: UUID,
        sessionID: UUID,
        eventType: TimelineEventType,
        startedAt: Date,
        endedAt: Date?,
        domain: TemperatureDomain?,
        metricName: String?,
        reasonCode: String?,
        message: String?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.eventType = eventType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.domain = domain
        self.metricName = metricName
        self.reasonCode = reasonCode
        self.message = message
    }
}
