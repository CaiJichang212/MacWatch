import MacWatchCore

public struct StatsTemperatureProbeFactory {
    private let temperatureSensorSnapshotProvider: TemperatureSensorSnapshotProvider

    public init(
        temperatureSensorSnapshotProvider: TemperatureSensorSnapshotProvider = TemperatureSensorSnapshotProvider()
    ) {
        self.temperatureSensorSnapshotProvider = temperatureSensorSnapshotProvider
    }

    public func makeCPUOnlyProbes() -> [any TemperatureProbe] {
        [CPUTemperatureProbe(hidReader: temperatureSensorSnapshotProvider)]
    }

    public func makeFastProbes() -> [any TemperatureProbe] {
        [
            CPUTemperatureProbe(hidReader: temperatureSensorSnapshotProvider),
            GPUTemperatureProbe(hidReader: temperatureSensorSnapshotProvider),
        ]
    }

    public func makeSlowProbes() -> [any TemperatureProbe] {
        [
            MemoryTemperatureProbe(),
            SSDTemperatureProbe(hidReader: temperatureSensorSnapshotProvider),
            BatteryTemperatureProbe(hidReader: temperatureSensorSnapshotProvider),
        ]
    }

    public func makeSystemProbes() -> [any TemperatureProbe] {
        [
            SystemTemperatureProbe(hidReader: temperatureSensorSnapshotProvider),
        ]
    }

    public func makeSensorProbes() -> [any TemperatureProbe] {
        [
            SensorTemperatureProbe(hidReader: temperatureSensorSnapshotProvider),
        ]
    }

    public func makeDefaultProbes() -> [any TemperatureProbe] {
        makeFastProbes() + makeSlowProbes() + makeSystemProbes() + makeSensorProbes()
    }

    public func invalidateTemperatureSnapshots() {
        temperatureSensorSnapshotProvider.invalidateSnapshot()
    }
}
