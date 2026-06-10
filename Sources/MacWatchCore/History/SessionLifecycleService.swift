import Foundation

public final class SessionLifecycleService {
    private let repository: SessionHistoryRepository
    private let clock: () -> Date
    private let appVersion: String?
    private let model: String?
    private let chip: String?
    private let osVersion: String?
    private var openSleepEventID: UUID?

    public init(
        repository: SessionHistoryRepository,
        clock: @escaping () -> Date = Date.init,
        appVersion: String? = nil,
        model: String? = nil,
        chip: String? = nil,
        osVersion: String? = nil
    ) {
        self.repository = repository
        self.clock = clock
        self.appVersion = appVersion
        self.model = model
        self.chip = chip
        self.osVersion = osVersion
    }

    @discardableResult
    public func handle(_ event: AppLifecycleEvent) throws -> MonitoringSession? {
        switch event {
        case .launched:
            return try handleLaunch()
        case .willSleep:
            return try handleWillSleep()
        case .didWake:
            return try handleDidWake()
        case .willTerminate:
            return try handleWillTerminate()
        }
    }

    private func handleLaunch() throws -> MonitoringSession {
        let now = clock()
        let session = MonitoringSession(
            id: UUID(),
            startedAt: now,
            appVersion: appVersion,
            model: model,
            chip: chip,
            osVersion: osVersion
        )

        openSleepEventID = nil
        try repository.beginSession(session, clearingPreviousHistory: true)
        try repository.insertTimelineEvent(
            TimelineEvent(
                id: UUID(),
                sessionID: session.id,
                eventType: .appStarted,
                startedAt: now,
                endedAt: nil,
                domain: nil,
                metricName: nil,
                reasonCode: nil,
                message: nil
            )
        )
        return session
    }

    private func handleWillSleep() throws -> MonitoringSession? {
        guard let session = try repository.currentSession(),
              openSleepEventID == nil else {
            return try repository.currentSession()
        }

        let now = clock()
        let event = TimelineEvent(
            id: UUID(),
            sessionID: session.id,
            eventType: .systemSleepStarted,
            startedAt: now,
            endedAt: nil,
            domain: nil,
            metricName: nil,
            reasonCode: "sleep",
            message: "system sleep started"
        )

        openSleepEventID = event.id
        try repository.insertTimelineEvent(event)
        return session
    }

    private func handleDidWake() throws -> MonitoringSession? {
        guard let session = try repository.currentSession() else {
            return nil
        }

        let now = clock()
        if let openSleepEventID {
            try repository.updateTimelineEvent(id: openSleepEventID, endedAt: now)
            self.openSleepEventID = nil
        }

        try repository.insertTimelineEvent(
            TimelineEvent(
                id: UUID(),
                sessionID: session.id,
                eventType: .systemSleepEnded,
                startedAt: now,
                endedAt: nil,
                domain: nil,
                metricName: nil,
                reasonCode: "wake",
                message: "system sleep ended"
            )
        )
        return session
    }

    private func handleWillTerminate() throws -> MonitoringSession? {
        guard let session = try repository.currentSession() else {
            return nil
        }

        let now = clock()
        try repository.endSession(id: session.id, endedAt: now)
        try repository.insertTimelineEvent(
            TimelineEvent(
                id: UUID(),
                sessionID: session.id,
                eventType: .appTerminating,
                startedAt: now,
                endedAt: nil,
                domain: nil,
                metricName: nil,
                reasonCode: nil,
                message: nil
            )
        )

        var endedSession = session
        endedSession.endedAt = now
        openSleepEventID = nil
        return endedSession
    }
}
