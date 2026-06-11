import Foundation

public enum TemperatureMetricName {
    public static let cpuHottest = "cpu.temperature.hottest"
    public static let cpuAverage = "cpu.temperature.average"
    public static let gpuHottest = "gpu.temperature.hottest"
    public static let gpuAverage = "gpu.temperature.average"
    public static let ssdInternal = "ssd.temperature.internal"
    public static let battery = "battery.temperature"
    public static let systemHottest = "system.temperature.hottest"
    public static let sensorTemperatureRaw = "sensor.temperature.raw"

    public static func participatesInGlobalHottest(_ metricName: String) -> Bool {
        metricName != cpuAverage && metricName != gpuAverage
    }
}
