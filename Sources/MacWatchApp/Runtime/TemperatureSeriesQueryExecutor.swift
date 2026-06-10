import Dispatch
import Foundation
import MacWatchCore

final class TemperatureSeriesQueryExecutor {
    private final class RepositoryBox: @unchecked Sendable {
        let repository: SessionHistoryRepository

        init(repository: SessionHistoryRepository) {
            self.repository = repository
        }
    }

    private let repositoryBox: RepositoryBox
    private let queue: DispatchQueue

    init(
        repository: SessionHistoryRepository,
        queue: DispatchQueue = DispatchQueue(
            label: "MacWatch.series-query",
            qos: .userInitiated
        )
    ) {
        self.repositoryBox = RepositoryBox(repository: repository)
        self.queue = queue
    }

    func query(
        sessionID: UUID,
        domain: TemperatureDomain,
        metricName: String,
        range: TemperatureHistoryRange,
        now: Date,
        maxPoints: Int
    ) async throws -> TemperatureSeries {
        let repositoryBox = repositoryBox
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let series = try repositoryBox.repository.query(
                        sessionID: sessionID,
                        domain: domain,
                        metricName: metricName,
                        range: range,
                        now: now,
                        maxPoints: maxPoints
                    )
                    continuation.resume(returning: series)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
