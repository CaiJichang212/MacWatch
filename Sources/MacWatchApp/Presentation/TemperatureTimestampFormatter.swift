import Foundation

enum TemperatureTimestampFormatter {
    static func shortTimeText(_ timestamp: Date?) -> String {
        guard let timestamp else {
            return "--"
        }
        return shortTime.string(from: timestamp)
    }

    private static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
