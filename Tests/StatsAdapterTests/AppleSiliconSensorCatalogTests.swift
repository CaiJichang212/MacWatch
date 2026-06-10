import XCTest
@testable import StatsAdapter

final class AppleSiliconSensorCatalogTests: XCTestCase {
    func testCatalogMapsCPUHIDSensorsToCPU() {
        let catalog = AppleSiliconSensorCatalog()

        XCTAssertEqual(catalog.domain(forRawKey: "pACC MTR Temp Sensor0"), .cpu)
        XCTAssertEqual(catalog.domain(forRawKey: "eACC MTR Temp Sensor1"), .cpu)
        XCTAssertEqual(catalog.displayName(forRawKey: "pACC MTR Temp Sensor0"), "CPU performance core 1")
        XCTAssertEqual(catalog.displayName(forRawKey: "eACC MTR Temp Sensor1"), "CPU efficiency core 2")
    }

    func testCatalogExposesM4CPUFallbackKeys() {
        let catalog = AppleSiliconSensorCatalog()
        let keys = catalog.smcCPUKeys(for: .m4)

        XCTAssertTrue(keys.contains("Te05"))
        XCTAssertTrue(keys.contains("Te09"))
        XCTAssertTrue(keys.contains("Te0H"))
        XCTAssertTrue(keys.contains("Te0S"))
        XCTAssertTrue(keys.contains("Tp01"))
        XCTAssertTrue(keys.contains("Tp05"))
        XCTAssertTrue(keys.contains("Tp09"))
        XCTAssertTrue(keys.contains("Tp0D"))
        XCTAssertTrue(keys.contains("Tp0V"))
        XCTAssertTrue(keys.contains("Tp0Y"))
        XCTAssertTrue(keys.contains("Tp0b"))
        XCTAssertTrue(keys.contains("Tp0e"))
    }
}
