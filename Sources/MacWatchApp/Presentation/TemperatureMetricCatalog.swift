import MacWatchCore

struct TemperatureMetricDescriptor: Identifiable, Equatable {
    let id: TemperatureDomain
    let domain: TemperatureDomain
    let metricName: String
    let averageMetricName: String?
    let title: String
    let menuBarMetric: MenuBarDisplayMetric?
    let isMVPCompatibilityRequired: Bool

    var detailMetricOptions: [TemperatureMetricOption] {
        guard let averageMetricName else {
            return [TemperatureMetricOption(label: "Hottest", metricName: metricName)]
        }
        return [
            TemperatureMetricOption(label: "Hottest", metricName: metricName),
            TemperatureMetricOption(label: "Average", metricName: averageMetricName),
        ]
    }
}

struct TemperatureMetricOption: Identifiable, Equatable {
    let label: String
    let metricName: String

    var id: String { metricName }
}

enum TemperatureMetricCatalog {
    static let overviewMetrics: [TemperatureMetricDescriptor] = [
        TemperatureMetricDescriptor(
            id: .cpu,
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            averageMetricName: TemperatureMetricName.cpuAverage,
            title: "CPU",
            menuBarMetric: .cpu,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .gpu,
            domain: .gpu,
            metricName: TemperatureMetricName.gpuHottest,
            averageMetricName: TemperatureMetricName.gpuAverage,
            title: "GPU",
            menuBarMetric: .gpu,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .ssd,
            domain: .ssd,
            metricName: TemperatureMetricName.ssdInternal,
            averageMetricName: nil,
            title: "SSD/NAND",
            menuBarMetric: .ssd,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .battery,
            domain: .battery,
            metricName: TemperatureMetricName.battery,
            averageMetricName: nil,
            title: "Battery",
            menuBarMetric: .battery,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .system,
            domain: .system,
            metricName: TemperatureMetricName.systemHottest,
            averageMetricName: nil,
            title: "System",
            menuBarMetric: nil,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .sensor,
            domain: .sensor,
            metricName: TemperatureMetricName.sensorTemperatureRaw,
            averageMetricName: nil,
            title: "Sensor",
            menuBarMetric: nil,
            isMVPCompatibilityRequired: true
        ),
    ]

    static let compatibilityMetrics = overviewMetrics

    static func requiredMetric(for domain: TemperatureDomain) -> TemperatureMetricDescriptor {
        overviewMetrics.first(where: { $0.domain == domain })
            ?? TemperatureMetricDescriptor(
                id: domain,
                domain: domain,
                metricName: TemperatureMetricName.systemHottest,
                averageMetricName: nil,
                title: domain.rawValue.capitalized,
                menuBarMetric: nil,
                isMVPCompatibilityRequired: false
            )
    }

    static func menuBarMetric(for displayMetric: MenuBarDisplayMetric) -> TemperatureMetricDescriptor? {
        overviewMetrics.first(where: { $0.menuBarMetric == displayMetric })
    }
}
