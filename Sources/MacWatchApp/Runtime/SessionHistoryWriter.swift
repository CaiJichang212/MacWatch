import Foundation
import MacWatchCore

struct SessionHistoryWriteResult: Sendable {
    let didWriteHistory: Bool
    let errorMessage: String?

    static let noWrite = SessionHistoryWriteResult(didWriteHistory: false, errorMessage: nil)
    static let wrote = SessionHistoryWriteResult(didWriteHistory: true, errorMessage: nil)
}

actor SessionHistoryWriter {
    private final class RepositoryBox: @unchecked Sendable {
        let repository: SessionHistoryRepository

        init(repository: SessionHistoryRepository) {
            self.repository = repository
        }
    }

    private let repositoryBox: RepositoryBox

    init(repository: SessionHistoryRepository) {
        self.repositoryBox = RepositoryBox(repository: repository)
    }

    func writeSamples(
        _ samples: [TemperatureSample],
        context: SampleContext
    ) -> SessionHistoryWriteResult {
        guard context.shouldWriteHistory else {
            return .noWrite
        }

        var wroteHistory = false
        var lastErrorMessage: String?

        for sample in samples {
            do {
                try repositoryBox.repository.insertSample(sample)
                wroteHistory = true
            } catch {
                lastErrorMessage = error.localizedDescription
                recordHistoryWriteFailure(
                    sessionID: context.sessionID,
                    timestamp: context.sampledAt,
                    domain: sample.domain,
                    metricName: sample.metricName,
                    message: error.localizedDescription
                )
            }
        }

        return SessionHistoryWriteResult(
            didWriteHistory: wroteHistory,
            errorMessage: lastErrorMessage
        )
    }

    func writeTimelineEvent(_ event: TimelineEvent) -> SessionHistoryWriteResult {
        do {
            try repositoryBox.repository.insertTimelineEvent(event)
            return .wrote
        } catch {
            recordHistoryWriteFailure(
                sessionID: event.sessionID,
                timestamp: event.startedAt,
                domain: event.domain,
                metricName: event.metricName,
                message: error.localizedDescription
            )
            return SessionHistoryWriteResult(
                didWriteHistory: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func recordHistoryWriteFailure(
        sessionID: UUID,
        timestamp: Date,
        domain: TemperatureDomain?,
        metricName: String?,
        message: String
    ) {
        try? repositoryBox.repository.insertTimelineEvent(
            TimelineEvent(
                id: UUID(),
                sessionID: sessionID,
                eventType: .historyWriteFailed,
                startedAt: timestamp,
                endedAt: nil,
                domain: domain,
                metricName: metricName,
                reasonCode: "historyWriteFailed",
                message: message
            )
        )
    }
}
