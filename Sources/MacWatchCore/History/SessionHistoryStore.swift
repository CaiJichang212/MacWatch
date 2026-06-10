import Foundation

public protocol SessionHistoryStore: AnyObject {
    func initialize() throws
    func replaceWithNewSession(_ session: MonitoringSession) throws
    func currentSession() throws -> MonitoringSession?
    func endSession(id: UUID, endedAt: Date) throws
    func insertSample(_ sample: TemperatureSample) throws
    func insertCapability(_ capability: TemperatureCapability) throws
    func insertTimelineEvent(_ event: TimelineEvent) throws
    func updateTimelineEvent(id: UUID, endedAt: Date) throws
    func samples(matching query: TemperatureQuery) throws -> [TemperatureSample]
    func timelineEvents(sessionID: UUID, start: Date, end: Date) throws -> [TimelineEvent]
    func clearHistory(sessionID: UUID, clearedAt: Date) throws
}
