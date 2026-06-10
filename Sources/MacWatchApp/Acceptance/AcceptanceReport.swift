import Darwin
import Foundation

struct AcceptanceReport: Codable {
    let scenario: String
    let passed: Bool
    let startedAt: String
    let durationMs: Double
    let metrics: [String: String]
    let failures: [String]

    init(
        scenario: AcceptanceScenario,
        passed: Bool,
        startedAt: Date,
        durationMs: Double,
        metrics: [String: String],
        failures: [String]
    ) {
        self.scenario = scenario.rawValue
        self.passed = passed
        self.startedAt = Self.timestampFormatter.string(from: startedAt)
        self.durationMs = durationMs
        self.metrics = metrics
        self.failures = failures
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum AcceptanceReportWriter {
    static func write(_ report: AcceptanceReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(report) else {
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        fflush(stdout)
    }

    static func writeAndExit(_ report: AcceptanceReport) -> Never {
        write(report)
        Darwin.exit(report.passed ? 0 : 1)
    }

    static func writeErrorAndExit(_ message: String, code: Int32 = 64) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        fflush(stderr)
        Darwin.exit(code)
    }
}
