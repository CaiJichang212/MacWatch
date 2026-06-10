import Foundation

public protocol SessionHistoryRepository: AnyObject {
    func beginSession(_ session: MonitoringSession, clearingPreviousHistory: Bool) throws
    func currentSession() throws -> MonitoringSession?
    func endSession(id: UUID, endedAt: Date) throws
    func insertSample(_ sample: TemperatureSample) throws
    func insertCapability(_ capability: TemperatureCapability) throws
    func insertTimelineEvent(_ event: TimelineEvent) throws
    func updateTimelineEvent(id: UUID, endedAt: Date) throws
    func timelineEvents(sessionID: UUID) throws -> [TimelineEvent]
    func query(_ query: TemperatureQuery) throws -> [TemperatureSeries]
}
