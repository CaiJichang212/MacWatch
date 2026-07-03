import Foundation

public enum TemperatureUnit: String, CaseIterable, Codable, Sendable {
    case celsius
    case fahrenheit
}

public enum RefreshInterval: TimeInterval, CaseIterable, Codable, Sendable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
}

public enum MenuBarDisplayMetric: String, CaseIterable, Codable, Sendable {
    case hottest
    case cpu
    case gpu
    case ssd
    case battery

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "memory" {
            self = .hottest
            return
        }
        guard let value = MenuBarDisplayMetric(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid menu bar display metric: \(rawValue)"
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case zhHans
    case english

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = AppLanguage(rawValue: rawValue) ?? .system
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var launchMainWindowOnStart: Bool
    public var temperatureUnit: TemperatureUnit
    public var refreshInterval: RefreshInterval
    public var defaultTrendRange: TemperatureHistoryRange
    public var menuBarDisplayMetric: MenuBarDisplayMetric
    public var language: AppLanguage

    public init(
        launchMainWindowOnStart: Bool,
        temperatureUnit: TemperatureUnit,
        refreshInterval: RefreshInterval,
        defaultTrendRange: TemperatureHistoryRange,
        menuBarDisplayMetric: MenuBarDisplayMetric,
        language: AppLanguage = .system
    ) {
        self.launchMainWindowOnStart = launchMainWindowOnStart
        self.temperatureUnit = temperatureUnit
        self.refreshInterval = refreshInterval
        self.defaultTrendRange = defaultTrendRange
        self.menuBarDisplayMetric = menuBarDisplayMetric
        self.language = language
    }

    enum CodingKeys: String, CodingKey {
        case launchMainWindowOnStart
        case temperatureUnit
        case refreshInterval
        case defaultTrendRange
        case menuBarDisplayMetric
        case language
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchMainWindowOnStart = try container.decode(Bool.self, forKey: .launchMainWindowOnStart)
        temperatureUnit = try container.decode(TemperatureUnit.self, forKey: .temperatureUnit)
        refreshInterval = try container.decode(RefreshInterval.self, forKey: .refreshInterval)
        defaultTrendRange = try container.decode(TemperatureHistoryRange.self, forKey: .defaultTrendRange)
        menuBarDisplayMetric = try container.decode(MenuBarDisplayMetric.self, forKey: .menuBarDisplayMetric)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
    }
}

public extension AppSettings {
    static let `default` = AppSettings(
        launchMainWindowOnStart: true,
        temperatureUnit: .celsius,
        refreshInterval: .fiveSeconds,
        defaultTrendRange: .oneHour,
        menuBarDisplayMetric: .hottest,
        language: .system
    )
}
