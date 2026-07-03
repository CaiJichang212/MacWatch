import XCTest
@testable import MacWatchCore

final class TemperatureReadingValidatorTests: XCTestCase {
    func testTemperatureReadingValidatorHonorsBoundaryRules() {
        XCTAssertFalse(TemperatureReadingValidator.isValidCelsius(0))
        XCTAssertTrue(TemperatureReadingValidator.isValidCelsius(0.1))
        XCTAssertTrue(TemperatureReadingValidator.isValidCelsius(109.9))
        XCTAssertFalse(TemperatureReadingValidator.isValidCelsius(-0.1))
        XCTAssertFalse(TemperatureReadingValidator.isValidCelsius(110))
        XCTAssertFalse(TemperatureReadingValidator.isValidCelsius(110.1))
        XCTAssertFalse(TemperatureReadingValidator.isValidCelsius(.nan))
        XCTAssertFalse(TemperatureReadingValidator.isValidCelsius(.infinity))
    }

    func testDefaultPolicyTargetsMatchStageFourTable() {
        XCTAssertEqual(
            TemperatureSamplingPolicy.default(for: .cpu),
            TemperatureSamplingPolicy(realtimeInterval: 5, historyInterval: 10, minimumInterval: 5)
        )
        XCTAssertEqual(
            TemperatureSamplingPolicy.default(for: .gpu),
            TemperatureSamplingPolicy(realtimeInterval: 5, historyInterval: 10, minimumInterval: 5)
        )
        XCTAssertEqual(
            TemperatureSamplingPolicy.default(for: .ssd),
            TemperatureSamplingPolicy(realtimeInterval: 30, historyInterval: 60, minimumInterval: 30)
        )
        XCTAssertEqual(
            TemperatureSamplingPolicy.default(for: .battery),
            TemperatureSamplingPolicy(realtimeInterval: 30, historyInterval: 60, minimumInterval: 30)
        )
        XCTAssertEqual(
            TemperatureSamplingPolicy.default(for: .system),
            TemperatureSamplingPolicy(realtimeInterval: 10, historyInterval: 30, minimumInterval: 10)
        )
        XCTAssertEqual(
            TemperatureSamplingPolicy.default(for: .sensor),
            TemperatureSamplingPolicy(realtimeInterval: 10, historyInterval: 30, minimumInterval: 10)
        )
    }

    func testUserIntervalIsClampedToMinimumAndHistoryIntervalSkipsSafely() {
        XCTAssertEqual(
            TemperatureSamplingPolicy.default(for: .ssd, userRealtimeInterval: 5),
            TemperatureSamplingPolicy(realtimeInterval: 30, historyInterval: 60, minimumInterval: 30)
        )

        XCTAssertEqual(
            TemperatureSamplingPolicy.default(for: .ssd, userRealtimeInterval: 45),
            TemperatureSamplingPolicy(realtimeInterval: 45, historyInterval: 90, minimumInterval: 30)
        )
    }
}
