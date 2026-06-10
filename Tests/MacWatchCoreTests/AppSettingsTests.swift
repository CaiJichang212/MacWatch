import XCTest
@testable import MacWatchCore

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsLaunchMainWindowOnStart() {
        XCTAssertTrue(AppSettings.default.launchMainWindowOnStart)
        XCTAssertEqual(AppSettings.default.temperatureUnit, .celsius)
        XCTAssertEqual(AppSettings.default.refreshInterval, .fiveSeconds)
        XCTAssertEqual(AppSettings.default.defaultTrendRange, .oneHour)
        XCTAssertEqual(AppSettings.default.menuBarDisplayMetric, .hottest)
    }
}
