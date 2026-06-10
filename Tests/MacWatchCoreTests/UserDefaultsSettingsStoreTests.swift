import XCTest
@testable import MacWatchCore

final class UserDefaultsSettingsStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let settings = AppSettings(
            launchMainWindowOnStart: false,
            temperatureUnit: .fahrenheit,
            refreshInterval: .tenSeconds,
            defaultTrendRange: .sixHours,
            menuBarDisplayMetric: .battery
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testInvalidStoredPayloadFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(Data("not-json".utf8), forKey: UserDefaultsSettingsStore.storageKey)
        let store = UserDefaultsSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .default)
    }
}
