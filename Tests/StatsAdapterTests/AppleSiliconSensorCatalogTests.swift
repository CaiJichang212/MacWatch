import XCTest
@testable import StatsAdapter

final class AppleSiliconSensorCatalogTests: XCTestCase {
    func testCatalogMapsCPUHIDSensorsToCPU() {
        let catalog = AppleSiliconSensorCatalog()

        XCTAssertEqual(catalog.domain(forRawKey: "pACC MTR Temp Sensor0"), .cpu)
        XCTAssertEqual(catalog.domain(forRawKey: "eACC MTR Temp Sensor1"), .cpu)
        XCTAssertNil(catalog.domain(forRawKey: "PMU tdie8"))
        XCTAssertNil(catalog.domain(forRawKey: "PMU2 tdie8"))
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

    func testCatalogMatchesStatsCPUFallbackKeysAcrossAppleSiliconGenerations() {
        let catalog = AppleSiliconSensorCatalog()

        XCTAssertEqual(catalog.smcCPUKeys(for: .m2), [
            "Tp1h", "Tp1t", "Tp1p", "Tp1l",
            "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j",
        ])
        XCTAssertEqual(catalog.smcCPUKeys(for: .m3), [
            "Te05", "Te0L", "Te0P", "Te0S",
            "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        ])
        XCTAssertEqual(catalog.smcCPUKeys(for: .m5), [
            "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
            "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y",
        ])
    }

    func testCatalogMatchesStatsGPUFallbackKeysAcrossAppleSiliconGenerations() {
        let catalog = AppleSiliconSensorCatalog()

        XCTAssertEqual(catalog.smcGPUKeys(for: .m2), ["Tg0f", "Tg0j"])
        XCTAssertEqual(catalog.smcGPUKeys(for: .m3), ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"])
        XCTAssertEqual(catalog.smcGPUKeys(for: .m5), ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"])
    }
}
