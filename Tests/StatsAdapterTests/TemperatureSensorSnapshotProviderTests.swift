import Foundation
import XCTest
@testable import MacWatchCore
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

    func testStatsSnapshotProviderClassifiesHIDAndSMCReadingsLikeStatsSensors() {
        let provider = StatsTemperatureSensorSnapshotProvider(
            platformDetector: FakeSnapshotPlatformDetector(platform: .m4),
            hidReader: StaticSnapshotHIDReader(values: [
                "pACC MTR Temp Sensor0": 61,
                "GPU MTR Temp Sensor0": 55,
                "NAND CH0 temp": 38,
                "gas gauge battery": 30,
                "PMU2 tcal": 52,
                "SOC MTR Temp Sensor0": 49,
                "mystery thermal": 44,
            ]),
            smcReader: StaticSnapshotSMCReader(values: [
                "Te05": 47,
                "Tg0G": 53,
                "TH0x": 41,
                "TB1T": 31,
                "TW0P": 42,
                "TL0P": 37,
                "TZZZ": 45,
            ]),
            catalog: AppleSiliconSensorCatalog(),
            cacheDuration: 0,
            clock: { Date(timeIntervalSince1970: 100) }
        )

        let snapshot = provider.readSnapshot()

        XCTAssertEqual(snapshot.detectedPlatform, .m4)
        XCTAssertEqual(snapshot.readings.filter { $0.domain == .cpu }.map(\.rawKey).sorted(), [
            "Te05",
            "pACC MTR Temp Sensor0",
        ])
        XCTAssertEqual(snapshot.readings.filter { $0.domain == .gpu }.map(\.rawKey).sorted(), [
            "GPU MTR Temp Sensor0",
            "Tg0G",
        ])
        XCTAssertEqual(snapshot.readings.filter { $0.domain == .ssd }.map(\.rawKey).sorted(), [
            "NAND CH0 temp",
            "TH0x",
        ])
        XCTAssertEqual(snapshot.readings.filter { $0.domain == .battery }.map(\.rawKey).sorted(), [
            "TB1T",
            "gas gauge battery",
        ])
        XCTAssertEqual(snapshot.readings.filter { $0.domain == .system }.map(\.rawKey).sorted(), [
            "TL0P",
            "TW0P",
        ])
        XCTAssertEqual(snapshot.readings.filter { $0.domain == .sensor }.map(\.rawKey).sorted(), [
            "PMU2 tcal",
            "SOC MTR Temp Sensor0",
            "TZZZ",
            "mystery thermal",
        ])
        XCTAssertTrue(snapshot.readings.first { $0.rawKey == "pACC MTR Temp Sensor0" }?.averageCandidate == true)
        XCTAssertTrue(snapshot.readings.first { $0.rawKey == "GPU MTR Temp Sensor0" }?.averageCandidate == true)
        XCTAssertFalse(snapshot.readings.first { $0.rawKey == "PMU2 tcal" }?.averageCandidate ?? true)
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

private struct FakeSnapshotPlatformDetector: ApplePlatformDetecting {
    let platform: ApplePlatform?

    func detect() -> ApplePlatform? {
        platform
    }
}

private struct StaticSnapshotHIDReader: AppleSiliconTemperatureReading {
    let values: [String: Double]

    func readTemperatureValues() -> [String: Double] {
        values
    }
}

private struct StaticSnapshotSMCReader: SMCValueReading {
    let values: [String: Double]

    func getAllKeys() -> [String] {
        Array(values.keys)
    }

    func getValue(_ key: String) -> Double? {
        values[key]
    }
}
