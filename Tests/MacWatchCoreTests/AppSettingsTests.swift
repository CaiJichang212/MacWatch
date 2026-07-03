import XCTest
@testable import MacWatchCore

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsLaunchMainWindowOnStart() {
        XCTAssertTrue(AppSettings.default.launchMainWindowOnStart)
        XCTAssertEqual(AppSettings.default.temperatureUnit, .celsius)
        XCTAssertEqual(AppSettings.default.refreshInterval, .fiveSeconds)
        XCTAssertEqual(AppSettings.default.defaultTrendRange, .oneHour)
        XCTAssertEqual(AppSettings.default.menuBarDisplayMetric, .hottest)
        XCTAssertEqual(AppSettings.default.language, .system)
    }

    func testCodableRoundTripPreservesLanguage() throws {
        let settings = AppSettings(
            launchMainWindowOnStart: false,
            temperatureUnit: .fahrenheit,
            refreshInterval: .tenSeconds,
            defaultTrendRange: .sixHours,
            menuBarDisplayMetric: .gpu,
            language: .english
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testLegacyPayloadWithoutLanguageMigratesToSystem() throws {
        let payload = """
        {
          "launchMainWindowOnStart": false,
          "temperatureUnit": "fahrenheit",
          "refreshInterval": 10,
          "defaultTrendRange": "sixHours",
          "menuBarDisplayMetric": "battery"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: payload)

        XCTAssertEqual(
            decoded,
            AppSettings(
                launchMainWindowOnStart: false,
                temperatureUnit: .fahrenheit,
                refreshInterval: .tenSeconds,
                defaultTrendRange: .sixHours,
                menuBarDisplayMetric: .battery,
                language: .system
            )
        )
    }

    func testUnknownLanguageFallsBackToSystem() throws {
        let payload = """
        {
          "launchMainWindowOnStart": true,
          "temperatureUnit": "celsius",
          "refreshInterval": 5,
          "defaultTrendRange": "oneHour",
          "menuBarDisplayMetric": "hottest",
          "language": "klingon"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: payload)

        XCTAssertEqual(decoded.language, .system)
    }
}
