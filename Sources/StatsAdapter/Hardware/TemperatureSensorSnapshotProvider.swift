import Foundation

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
