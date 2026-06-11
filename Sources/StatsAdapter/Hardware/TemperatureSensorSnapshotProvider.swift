import Foundation
import MacWatchCore

public final class TemperatureSensorSnapshotProvider: AppleSiliconTemperatureReading, @unchecked Sendable {
    private let reader: any AppleSiliconTemperatureReading
    private let cacheDuration: TimeInterval
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var cachedAt: Date?
    private var cachedValues: [String: Double]?

    public init(
        reader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        cacheDuration: TimeInterval = 1,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reader = reader
        self.cacheDuration = max(0, cacheDuration)
        self.clock = clock
    }

    public func readTemperatureValues() -> [String: Double] {
        lock.withLock {
            let now = clock()
            if let cachedAt,
               let cachedValues,
               now.timeIntervalSince(cachedAt) < cacheDuration {
                return cachedValues
            }

            let values = reader.readTemperatureValues()
            cachedAt = now
            cachedValues = values
            return values
        }
    }

    public func invalidateSnapshot() {
        lock.withLock {
            cachedAt = nil
            cachedValues = nil
        }
    }
}

public struct StatsTemperatureSensorReading: Equatable, Sendable {
    public let rawKey: String
    public let displayName: String
    public let valueCelsius: Double
    public let source: TemperatureSource
    public let domain: TemperatureDomain
    public let averageCandidate: Bool

    public init(
        rawKey: String,
        displayName: String,
        valueCelsius: Double,
        source: TemperatureSource,
        domain: TemperatureDomain,
        averageCandidate: Bool
    ) {
        self.rawKey = rawKey
        self.displayName = displayName
        self.valueCelsius = valueCelsius
        self.source = source
        self.domain = domain
        self.averageCandidate = averageCandidate
    }
}

public struct StatsTemperatureSensorSnapshot: Equatable, Sendable {
    public let readings: [StatsTemperatureSensorReading]
    public let availableHIDKeys: [String]
    public let availableSMCKeys: [String]
    public let detectedPlatform: ApplePlatform?

    public init(
        readings: [StatsTemperatureSensorReading],
        availableHIDKeys: [String],
        availableSMCKeys: [String],
        detectedPlatform: ApplePlatform?
    ) {
        self.readings = readings
        self.availableHIDKeys = availableHIDKeys
        self.availableSMCKeys = availableSMCKeys
        self.detectedPlatform = detectedPlatform
    }

    public func readings(
        for domain: TemperatureDomain,
        averageOnly: Bool = false
    ) -> [StatsTemperatureSensorReading] {
        readings.filter { reading in
            reading.domain == domain && (averageOnly == false || reading.averageCandidate)
        }
    }
}

public protocol StatsTemperatureSensorSnapshotProviding: Sendable {
    func readSnapshot() -> StatsTemperatureSensorSnapshot
}

public final class StatsTemperatureSensorSnapshotProvider: StatsTemperatureSensorSnapshotProviding, @unchecked Sendable {
    private let platformDetector: any ApplePlatformDetecting
    private let hidReader: any AppleSiliconTemperatureReading
    private let smcReader: any SMCValueReading
    private let catalog: AppleSiliconSensorCatalog
    private let cacheDuration: TimeInterval
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var cachedAt: Date?
    private var cachedSnapshot: StatsTemperatureSensorSnapshot?

    public init(
        platformDetector: any ApplePlatformDetecting = ApplePlatformDetector(),
        hidReader: any AppleSiliconTemperatureReading = AppleSiliconHIDTemperatureReader(),
        smcReader: any SMCValueReading = SMCReadOnlyClient(),
        catalog: AppleSiliconSensorCatalog = AppleSiliconSensorCatalog(),
        cacheDuration: TimeInterval = 1,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.platformDetector = platformDetector
        self.hidReader = hidReader
        self.smcReader = smcReader
        self.catalog = catalog
        self.cacheDuration = max(0, cacheDuration)
        self.clock = clock
    }

    public func readSnapshot() -> StatsTemperatureSensorSnapshot {
        lock.withLock {
            let now = clock()
            if let cachedAt,
               let cachedSnapshot,
               now.timeIntervalSince(cachedAt) < cacheDuration {
                return cachedSnapshot
            }

            let snapshot = buildSnapshot()
            cachedAt = now
            cachedSnapshot = snapshot
            return snapshot
        }
    }

    public func invalidateSnapshot() {
        lock.withLock {
            cachedAt = nil
            cachedSnapshot = nil
        }
    }

    private func buildSnapshot() -> StatsTemperatureSensorSnapshot {
        let detectedPlatform = platformDetector.detect()
        let platform = detectedPlatform ?? .intel
        let hidValues = hidReader.readTemperatureValues()
        let smcKeys = smcReader.getAllKeys().sorted()
        var readings: [StatsTemperatureSensorReading] = []

        for (rawKey, value) in hidValues.sorted(by: { $0.key < $1.key }) {
            guard TemperatureSample.isValidTemperatureValue(value) else {
                continue
            }
            readings.append(hidReading(rawKey: rawKey, value: value))
        }

        for rawKey in smcKeys {
            guard let value = smcReader.getValue(rawKey),
                  TemperatureSample.isValidTemperatureValue(value),
                  let reading = smcReading(rawKey: rawKey, value: value, platform: platform) else {
                continue
            }
            readings.append(reading)
        }

        return StatsTemperatureSensorSnapshot(
            readings: readings,
            availableHIDKeys: hidValues.keys.sorted(),
            availableSMCKeys: smcKeys,
            detectedPlatform: detectedPlatform
        )
    }

    private func hidReading(rawKey: String, value: Double) -> StatsTemperatureSensorReading {
        let domain: TemperatureDomain
        let averageCandidate: Bool

        if catalog.isCPUHIDKey(rawKey) {
            domain = .cpu
            averageCandidate = true
        } else if catalog.isGPUHIDKey(rawKey) {
            domain = .gpu
            averageCandidate = true
        } else if catalog.isSSDHIDKey(rawKey) {
            domain = .ssd
            averageCandidate = false
        } else if rawKey.localizedCaseInsensitiveContains("gas gauge battery") {
            domain = .battery
            averageCandidate = false
        } else {
            domain = .sensor
            averageCandidate = false
        }

        return StatsTemperatureSensorReading(
            rawKey: rawKey,
            displayName: catalog.displayName(forRawKey: rawKey),
            valueCelsius: value,
            source: .hidSensors,
            domain: domain,
            averageCandidate: averageCandidate
        )
    }

    private func smcReading(
        rawKey: String,
        value: Double,
        platform: ApplePlatform
    ) -> StatsTemperatureSensorReading? {
        let domain: TemperatureDomain
        let averageCandidate: Bool

        if catalog.smcCPUKeys(for: platform).contains(rawKey) {
            domain = .cpu
            averageCandidate = true
        } else if catalog.smcGPUKeys(for: platform).contains(rawKey) {
            domain = .gpu
            averageCandidate = true
        } else if catalog.smcSSDKeys().contains(rawKey) {
            domain = .ssd
            averageCandidate = false
        } else if catalog.smcBatteryKeys().contains(rawKey) {
            domain = .battery
            averageCandidate = false
        } else if catalog.smcSystemKeys().contains(rawKey) {
            domain = .system
            averageCandidate = false
        } else {
            return nil
        }

        return StatsTemperatureSensorReading(
            rawKey: rawKey,
            displayName: catalog.displayName(forRawKey: rawKey),
            valueCelsius: value,
            source: .smc,
            domain: domain,
            averageCandidate: averageCandidate
        )
    }
}
