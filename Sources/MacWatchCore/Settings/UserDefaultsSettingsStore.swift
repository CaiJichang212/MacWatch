import Foundation

public final class UserDefaultsSettingsStore: SettingsStore {
    static let storageKey = "MacWatch.settings.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.storageKey),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }

        defaults.set(data, forKey: Self.storageKey)
    }
}
