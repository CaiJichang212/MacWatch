import Foundation

enum AcceptanceScenario: String, CaseIterable, Codable {
    case probeStatus = "probe-status"
    case dashboardOpen = "dashboard-open"
    case popupOpen = "popup-open"
    case trendQuery = "trend-query"
    case sleepWakeSimulated = "sleep-wake-simulated"

    var requiresApplicationLaunch: Bool {
        switch self {
        case .dashboardOpen, .popupOpen:
            return true
        case .probeStatus, .trendQuery, .sleepWakeSimulated:
            return false
        }
    }
}

enum AcceptanceView: String {
    case dashboard
    case popup
}

enum MacWatchCLIArgumentError: Error, LocalizedError {
    case missingAcceptanceScenario
    case unsupportedAcceptanceScenario(String)

    var errorDescription: String? {
        switch self {
        case .missingAcceptanceScenario:
            return "Missing value for --acceptance-run."
        case let .unsupportedAcceptanceScenario(value):
            return "Unsupported acceptance scenario: \(value)"
        }
    }
}

struct MacWatchCLIArguments {
    let shouldProbeTemperatureOnce: Bool
    let acceptanceScenario: AcceptanceScenario?

    init(arguments: [String]) throws {
        shouldProbeTemperatureOnce = arguments.contains("--probe-temperature-once")

        if let index = arguments.firstIndex(of: "--acceptance-run") {
            let nextIndex = arguments.index(after: index)
            guard nextIndex < arguments.endIndex else {
                throw MacWatchCLIArgumentError.missingAcceptanceScenario
            }

            let rawValue = arguments[nextIndex]
            guard let scenario = AcceptanceScenario(rawValue: rawValue) else {
                throw MacWatchCLIArgumentError.unsupportedAcceptanceScenario(rawValue)
            }
            acceptanceScenario = scenario
        } else {
            acceptanceScenario = nil
        }
    }
}
