import Foundation

public enum TemperatureHistoryRange: String, CaseIterable, Codable, Sendable {
    case fifteenMinutes
    case oneHour
    case sixHours
    case allSession

    public func resolveStart(sessionStartedAt: Date, now: Date) -> Date {
        switch self {
        case .fifteenMinutes:
            return max(sessionStartedAt, now.addingTimeInterval(-15 * 60))
        case .oneHour:
            return max(sessionStartedAt, now.addingTimeInterval(-60 * 60))
        case .sixHours:
            return max(sessionStartedAt, now.addingTimeInterval(-6 * 60 * 60))
        case .allSession:
            return sessionStartedAt
        }
    }
}
