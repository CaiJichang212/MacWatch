import XCTest
@testable import StatsAdapter

final class NVMeSMARTTemperatureReaderTests: XCTestCase {
    func testSMARTKelvinConversionMatchesStatsIntegerCelsius() {
        XCTAssertEqual(NVMeSMARTTemperatureReader.celsiusFromSMARTKelvin(303), 30.0)
    }

    func testInternalDiskPropertyDetectionAcceptsOnlyInternalDevices() {
        XCTAssertTrue(NVMeSMARTTemperatureReader.isInternalDisk(properties: ["Internal": true]))
        XCTAssertTrue(NVMeSMARTTemperatureReader.isInternalDisk(properties: ["Physical Interconnect Location": "Internal"]))

        XCTAssertFalse(NVMeSMARTTemperatureReader.isInternalDisk(properties: ["Internal": false]))
        XCTAssertFalse(NVMeSMARTTemperatureReader.isInternalDisk(properties: ["Physical Interconnect Location": "External"]))
        XCTAssertFalse(NVMeSMARTTemperatureReader.isInternalDisk(properties: [:]))
    }
}
