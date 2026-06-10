import XCTest
@testable import MacWatchCore

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsLaunchMainWindowOnStart() {
        XCTAssertTrue(AppSettings.default.launchMainWindowOnStart)
    }
}
