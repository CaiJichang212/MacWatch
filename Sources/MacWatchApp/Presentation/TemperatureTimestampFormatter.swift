import Foundation

enum TemperatureTimestampFormatter {
    static func shortTimeText(_ timestamp: Date?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let timestamp else {
            return "--"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: timestamp)
    }
}
