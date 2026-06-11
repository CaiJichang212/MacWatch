import Foundation
import XCTest
@testable import StatsAdapter

final class TemperatureSensorSnapshotProviderTests: XCTestCase {
    func testSnapshotProviderReusesHIDReadingsWithinCacheWindowAndInvalidatesOnDemand() {
        let reader = CountingHIDSnapshotReader(values: ["pACC MTR Temp Sensor0": 61])
        let clock = MutableSnapshotClock(now: Date(timeIntervalSince1970: 100))
        let provider = TemperatureSensorSnapshotProvider(
            reader: reader,
            cacheDuration: 5,
            clock: { clock.now }
        )

        XCTAssertEqual(provider.readTemperatureValues()["pACC MTR Temp Sensor0"], 61)
        XCTAssertEqual(provider.readTemperatureValues()["pACC MTR Temp Sensor0"], 61)
        XCTAssertEqual(reader.readCount, 1)

        provider.invalidateSnapshot()
        XCTAssertEqual(provider.readTemperatureValues()["pACC MTR Temp Sensor0"], 61)

        XCTAssertEqual(reader.readCount, 2)
    }
}

private final class CountingHIDSnapshotReader: AppleSiliconTemperatureReading, @unchecked Sendable {
    private let values: [String: Double]
    private let lock = NSLock()
    private var _readCount = 0

    init(values: [String: Double]) {
        self.values = values
    }

    var readCount: Int {
        lock.withLock { _readCount }
    }

    func readTemperatureValues() -> [String: Double] {
        lock.withLock {
            _readCount += 1
        }
        return values
    }
}

private final class MutableSnapshotClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
