import MacWatchCore

public struct StatsTemperatureProbeFactory {
    private let temperatureSensorSnapshotProvider: StatsTemperatureSensorSnapshotProvider

    public init(
        temperatureSensorSnapshotProvider: StatsTemperatureSensorSnapshotProvider = StatsTemperatureSensorSnapshotProvider()
    ) {
        self.temperatureSensorSnapshotProvider = temperatureSensorSnapshotProvider
    }

    public func makeCPUOnlyProbes() -> [any TemperatureProbe] {
        [CPUTemperatureProbe(snapshotProvider: temperatureSensorSnapshotProvider)]
    }

    public func makeFastProbes() -> [any TemperatureProbe] {
        [
            CPUTemperatureProbe(snapshotProvider: temperatureSensorSnapshotProvider),
            GPUTemperatureProbe(snapshotProvider: temperatureSensorSnapshotProvider),
        ]
    }

    public func makeSlowProbes() -> [any TemperatureProbe] {
        [
            SSDTemperatureProbe(snapshotProvider: temperatureSensorSnapshotProvider),
            BatteryTemperatureProbe(snapshotProvider: temperatureSensorSnapshotProvider),
        ]
    }

    public func makeSystemProbes() -> [any TemperatureProbe] {
        [
            SystemTemperatureProbe(snapshotProvider: temperatureSensorSnapshotProvider),
        ]
    }

    public func makeSensorProbes() -> [any TemperatureProbe] {
        [
            SensorTemperatureProbe(snapshotProvider: temperatureSensorSnapshotProvider),
        ]
    }

    public func makeDefaultProbes() -> [any TemperatureProbe] {
        makeFastProbes() + makeSlowProbes() + makeSystemProbes() + makeSensorProbes()
    }

    public func invalidateTemperatureSnapshots() {
        temperatureSensorSnapshotProvider.invalidateSnapshot()
    }
}
