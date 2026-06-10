import MacWatchCore

public enum StatsReadOnlySource: String, CaseIterable, Sendable {
    case hidSensors
    case smcReadOnly
    case batteryIORegistry
    case nvmeSMART
}

public extension StatsReadOnlySource {
    var temperatureSource: TemperatureSource {
        switch self {
        case .hidSensors:
            return .hidSensors
        case .smcReadOnly:
            return .smc
        case .batteryIORegistry:
            return .batteryIORegistry
        case .nvmeSMART:
            return .nvmeSMART
        }
    }
}
