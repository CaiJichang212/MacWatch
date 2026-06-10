import MacWatchCore

struct TemperatureMetricDescriptor: Identifiable, Equatable {
    let id: TemperatureDomain
    let domain: TemperatureDomain
    let metricName: String
    let title: String
    let menuBarMetric: MenuBarDisplayMetric?
    let isMVPCompatibilityRequired: Bool
}

enum TemperatureMetricCatalog {
    static let overviewMetrics: [TemperatureMetricDescriptor] = [
        TemperatureMetricDescriptor(
            id: .cpu,
            domain: .cpu,
            metricName: TemperatureMetricName.cpuHottest,
            title: "CPU",
            menuBarMetric: .cpu,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .gpu,
            domain: .gpu,
            metricName: TemperatureMetricName.gpuHottest,
            title: "GPU",
            menuBarMetric: .gpu,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .memory,
            domain: .memory,
            metricName: TemperatureMetricName.memoryProximity,
            title: "Memory",
            menuBarMetric: .memory,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .ssd,
            domain: .ssd,
            metricName: TemperatureMetricName.ssdInternal,
            title: "SSD/NAND",
            menuBarMetric: .ssd,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .battery,
            domain: .battery,
            metricName: TemperatureMetricName.battery,
            title: "Battery",
            menuBarMetric: .battery,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .system,
            domain: .system,
            metricName: TemperatureMetricName.systemHottest,
            title: "System",
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
                title: domain.rawValue.capitalized,
                menuBarMetric: nil,
                isMVPCompatibilityRequired: false
            )
    }

    static func menuBarMetric(for displayMetric: MenuBarDisplayMetric) -> TemperatureMetricDescriptor? {
        overviewMetrics.first(where: { $0.menuBarMetric == displayMetric })
    }
}
