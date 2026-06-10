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
}
