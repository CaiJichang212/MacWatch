import AppKit
import Darwin
import Foundation

@MainActor
final class AcceptanceCoordinator {
    static let shared = AcceptanceCoordinator()

    private(set) var activeScenario: AcceptanceScenario?
    private var startedAt: Date?
    private var lagMonitor: MainThreadLagMonitor?
    private var hasCompletedScenario = false

    private init() {}

    func configure(scenario: AcceptanceScenario?) {
        activeScenario = scenario
        hasCompletedScenario = false
        startedAt = scenario?.requiresApplicationLaunch == true ? Date() : nil
        lagMonitor = nil
    }

    func applicationDidFinishLaunching(appDelegate: AppDelegate) {
        guard let scenario = activeScenario, scenario.requiresApplicationLaunch else {
            return
        }

        let monitor = MainThreadLagMonitor()
        lagMonitor = monitor
        monitor.start()

        switch scenario {
        case .dashboardOpen:
            return
        case .popupOpen:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                appDelegate.showAcceptancePopup()
            }
        case .probeStatus, .trendQuery, .sleepWakeSimulated:
            return
        }
    }

    func recordViewAppeared(_ view: AcceptanceView) {
        guard hasCompletedScenario == false,
              let scenario = activeScenario,
              let startedAt else {
            return
        }

        let expectedView: AcceptanceView
        switch scenario {
        case .dashboardOpen:
            expectedView = .dashboard
        case .popupOpen:
            expectedView = .popup
        case .probeStatus, .trendQuery, .sleepWakeSimulated:
            return
        }

        guard expectedView == view else {
            return
        }

        hasCompletedScenario = true
        let durationMs = Date().timeIntervalSince(startedAt) * 1_000
        let lag = lagMonitor?.stop() ?? 0
        let passed: Bool
        switch scenario {
        case .dashboardOpen:
            passed = durationMs < 1_000 && lag < 100
        case .popupOpen:
            passed = lag < 100
        case .probeStatus, .trendQuery, .sleepWakeSimulated:
            passed = false
        }
        let report = AcceptanceReport(
            scenario: scenario,
            passed: passed,
            startedAt: startedAt,
            durationMs: durationMs,
            metrics: [
                "contentReadyMs": String(format: "%.2f", durationMs),
                "maxMainThreadLagMs": String(format: "%.2f", lag),
                "view": view.rawValue,
            ],
            failures: passed ? [] : failureMessages(durationMs: durationMs, lag: lag)
        )
        AcceptanceReportWriter.write(report)
        Darwin.exit(report.passed ? 0 : 1)
    }

    private func failureMessages(durationMs: Double, lag: Double) -> [String] {
        var failures: [String] = []
        if activeScenario == .dashboardOpen && durationMs >= 1_000 {
            failures.append("contentReadyExceedsThreshold")
        }
        if lag >= 100 {
            failures.append("mainThreadLagExceedsThreshold")
        }
        return failures
    }
}
