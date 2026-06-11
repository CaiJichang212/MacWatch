import AppKit
import Darwin
import Foundation

@MainActor
final class AcceptanceCoordinator {
    static let shared = AcceptanceCoordinator()

    private(set) var activeScenario: AcceptanceScenario?
    private var firstRunGuideContext: FirstRunGuideContext?
    private var startedAt: Date?
    private var lagMonitor: MainThreadLagMonitor?
    private var hasCompletedScenario = false
    private var windowPolicyCheckTask: DispatchWorkItem?

    private init() {}

    func configure(scenario: AcceptanceScenario?) {
        activeScenario = scenario
        firstRunGuideContext = nil
        hasCompletedScenario = false
        startedAt = scenario?.requiresApplicationLaunch == true ? Date() : nil
        lagMonitor = nil
        windowPolicyCheckTask?.cancel()
        windowPolicyCheckTask = nil
    }

    func configure(firstRunGuideContext: FirstRunGuideContext) {
        self.firstRunGuideContext = firstRunGuideContext
    }

    var shouldDeferRuntimeStartForActiveScenario: Bool {
        guard let activeScenario, activeScenario.requiresApplicationLaunch else {
            return false
        }

        switch activeScenario {
        case .dashboardOpen, .popupOpen, .firstRunGuide,
             .launchMainWindowOnStartEnabled, .launchMainWindowOnStartDisabled:
            return true
        case .probeStatus, .trendQuery, .sleepWakeSimulated:
            return false
        }
    }

    func applicationDidFinishLaunching(appDelegate: AppDelegate) {
        guard let scenario = activeScenario, scenario.requiresApplicationLaunch else {
            return
        }

        switch scenario {
        case .dashboardOpen:
            startLagMonitor()
            return
        case .popupOpen:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.startLagMonitor()
                appDelegate.showAcceptancePopup()
            }
        case .firstRunGuide:
            return
        case .launchMainWindowOnStartEnabled, .launchMainWindowOnStartDisabled:
            scheduleWindowPolicyCheck()
        case .probeStatus, .trendQuery, .sleepWakeSimulated:
            return
        }
    }

    private func startLagMonitor() {
        let monitor = MainThreadLagMonitor()
        lagMonitor = monitor
        monitor.start()
    }

    private func scheduleWindowPolicyCheck() {
        guard
            let scenario = activeScenario,
            let expected = scenario.expectsMainWindowToOpenOnStart,
            let startedAt = startedAt
        else {
            return
        }

        let task = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            let windowOpened = WindowCommandCenter.shared.openMainWindowInvocationCount > 0
            let passed = windowOpened == expected
            let durationMs = Date().timeIntervalSince(startedAt) * 1_000
            let report = AcceptanceReport(
                scenario: scenario,
                passed: passed,
                startedAt: startedAt,
                durationMs: durationMs,
                metrics: [
                    "contentReadyMs": String(format: "%.2f", durationMs),
                    "residentMemoryMB": String(format: "%.2f", Self.residentMemoryMB()),
                    "windowOpened": windowOpened ? "true" : "false",
                    "expectedWindowOpened": expected ? "true" : "false",
                ],
                failures: passed ? [] : ["windowOpenMismatch"]
            )
            AcceptanceReportWriter.write(report)
            self.hasCompletedScenario = true
            Darwin.exit(report.passed ? 0 : 1)
        }

        windowPolicyCheckTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    func recordViewAppeared(_ view: AcceptanceView) {
        guard hasCompletedScenario == false,
              let scenario = activeScenario,
              let startedAt = startedAt else {
            return
        }

        let expectedView: AcceptanceView
        switch scenario {
        case .dashboardOpen:
            expectedView = .dashboard
        case .popupOpen:
            expectedView = .popup
        case .firstRunGuide:
            expectedView = .firstRunGuide
        case .launchMainWindowOnStartEnabled, .launchMainWindowOnStartDisabled,
             .probeStatus, .trendQuery, .sleepWakeSimulated:
            return
        }

        guard expectedView == view else {
            return
        }

        if scenario == .firstRunGuide, lagMonitor == nil {
            startLagMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.recordViewAppeared(view)
            }
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
        case .firstRunGuide:
            passed = durationMs < 1_500 && lag < 100
        case .launchMainWindowOnStartEnabled, .launchMainWindowOnStartDisabled,
             .probeStatus, .trendQuery, .sleepWakeSimulated:
            passed = false
        }

        let report = AcceptanceReport(
            scenario: scenario,
            passed: passed && supportsFirstRunGuideMetrics(for: scenario),
            startedAt: startedAt,
            durationMs: durationMs,
            metrics: reportMetrics(
                scenario: scenario,
                view: view,
                durationMs: durationMs,
                lag: lag
            ),
            failures: reportFailures(
                scenario: scenario,
                durationMs: durationMs,
                lag: lag
            )
        )
        AcceptanceReportWriter.write(report)
        Darwin.exit(report.passed ? 0 : 1)
    }

    private func reportMetrics(
        scenario: AcceptanceScenario,
        view: AcceptanceView,
        durationMs: Double,
        lag: Double
    ) -> [String: String] {
        var metrics: [String: String] = [
            "contentReadyMs": String(format: "%.2f", durationMs),
            "maxMainThreadLagMs": String(format: "%.2f", lag),
            "residentMemoryMB": String(format: "%.2f", Self.residentMemoryMB()),
            "view": view.rawValue,
        ]

        if scenario == .firstRunGuide {
            metrics.merge(firstRunMetrics) { _, new in new }
        }

        return metrics
    }

    private func reportFailures(
        scenario: AcceptanceScenario,
        durationMs: Double,
        lag: Double
    ) -> [String] {
        var failures: [String] = []
        if scenario == .dashboardOpen && durationMs >= 1_000 {
            failures.append("contentReadyExceedsThreshold")
        }
        if scenario == .firstRunGuide && durationMs >= 1_500 {
            failures.append("firstRunGuideExceedsThreshold")
        }
        if scenario == .firstRunGuide, firstRunGuideContext == nil {
            failures.append("firstRunGuideContextMissing")
        }
        if lag >= 100 {
            failures.append("mainThreadLagExceedsThreshold")
        }

        return failures
    }

    private func supportsFirstRunGuideMetrics(for scenario: AcceptanceScenario) -> Bool {
        if scenario != .firstRunGuide {
            return true
        }

        return firstRunGuideContext != nil
    }

    private var firstRunMetrics: [String: String] {
        guard let context = firstRunGuideContext else {
            return [
                "firstRunGuideContext": "missing"
            ]
        }

        return [
            "isAppleSilicon": context.isAppleSilicon ? "true" : "false",
            "modelIdentifier": context.displayModel,
            "chipName": context.displayChip,
            "isMacBookAir": context.isMacBookAir ? "true" : "false",
            "isSupportedTargetMachine": context.isSupportedTargetMachine ? "true" : "false",
            "supportMessage": context.supportMessage,
            "privacyStatement": "localOnlyNoNetwork"
        ]
    }

    private static func residentMemoryMB() -> Double {
        var usage = rusage()
        let result = getrusage(RUSAGE_SELF, &usage)
        guard result == 0 else {
            return 0
        }
        return Double(usage.ru_maxrss) / 1_048_576
    }
}
