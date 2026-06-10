import XCTest
@testable import StatsAdapter

final class StatsAdapterBoundaryTests: XCTestCase {
    func testReadOnlySourcesStayWithinMVPBoundary() {
        XCTAssertEqual(Set(StatsReadOnlySource.allCases), [
            .hidSensors,
            .smcReadOnly,
            .batteryIORegistry,
            .nvmeSMART,
        ])
    }

    func testBoundaryDeclaresForbiddenCapabilities() {
        XCTAssertTrue(StatsAdapterBoundary.stageOne.prohibitedCapabilities.contains("Remote"))
        XCTAssertTrue(StatsAdapterBoundary.stageOne.prohibitedCapabilities.contains("Updater"))
        XCTAssertTrue(StatsAdapterBoundary.stageOne.prohibitedCapabilities.contains("LevelDB"))
        XCTAssertTrue(StatsAdapterBoundary.stageOne.prohibitedCapabilities.contains("Widget"))
        XCTAssertTrue(StatsAdapterBoundary.stageOne.prohibitedCapabilities.contains("Stats.Module lifecycle"))
    }
}
