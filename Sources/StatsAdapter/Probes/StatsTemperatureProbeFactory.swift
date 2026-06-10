import MacWatchCore

public struct StatsTemperatureProbeFactory {
    public init() {}

    public func makeCPUOnlyProbes() -> [any TemperatureProbe] {
        [CPUTemperatureProbe()]
    }

    public func makeFastProbes() -> [any TemperatureProbe] {
        [
            CPUTemperatureProbe(),
            GPUTemperatureProbe(),
        ]
    }

    public func makeSlowProbes() -> [any TemperatureProbe] {
        [
            MemoryTemperatureProbe(),
            SSDTemperatureProbe(),
            BatteryTemperatureProbe(),
        ]
    }

    public func makeDefaultProbes() -> [any TemperatureProbe] {
        makeFastProbes() + makeSlowProbes()
    }
}
