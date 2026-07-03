import MacWatchCore

struct TemperatureMetricDescriptor: Identifiable, Equatable {
    let id: TemperatureDomain
    let domain: TemperatureDomain
    let metricName: String
    let averageMetricName: String?
    let menuBarMetric: MenuBarDisplayMetric?
    let isMVPCompatibilityRequired: Bool

    var detailMetricOptions: [TemperatureMetricOption] {
        guard let averageMetricName else {
            return [TemperatureMetricOption(kind: .hottest, metricName: metricName)]
        }
        return [
            TemperatureMetricOption(kind: .hottest, metricName: metricName),
            TemperatureMetricOption(kind: .average, metricName: averageMetricName),
        ]
    }

    func resolvedDetailMetricName(_ selectedMetricName: String) -> String {
        guard detailMetricOptions.contains(where: { $0.metricName == selectedMetricName }) else {
            return metricName
        }
        return selectedMetricName
    }

    func detailOptionLabel(for metricName: String) -> String {
        detailMetricOptions.first { $0.metricName == metricName }?.kind.rawValue ?? TemperatureMetricOption.Kind.hottest.rawValue
    }

    func localizedTitle(_ localizer: AppLocalizer) -> String {
        localizer.metricTitle(for: domain)
    }

    func localizedDetailOptionLabel(for metricName: String, localizer: AppLocalizer) -> String {
        let option = detailMetricOptions.first { $0.metricName == metricName }?.kind ?? .hottest
        return localizer.detailMetricOptionLabel(isAverage: option == .average)
    }
}

struct TemperatureMetricOption: Identifiable, Equatable {
    enum Kind: String {
        case hottest
        case average
    }

    let kind: Kind
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
            menuBarMetric: .cpu,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .gpu,
            domain: .gpu,
            metricName: TemperatureMetricName.gpuHottest,
            averageMetricName: TemperatureMetricName.gpuAverage,
            menuBarMetric: .gpu,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .ssd,
            domain: .ssd,
            metricName: TemperatureMetricName.ssdInternal,
            averageMetricName: nil,
            menuBarMetric: .ssd,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .battery,
            domain: .battery,
            metricName: TemperatureMetricName.battery,
            averageMetricName: nil,
            menuBarMetric: .battery,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .system,
            domain: .system,
            metricName: TemperatureMetricName.systemHottest,
            averageMetricName: nil,
            menuBarMetric: nil,
            isMVPCompatibilityRequired: true
        ),
        TemperatureMetricDescriptor(
            id: .sensor,
            domain: .sensor,
            metricName: TemperatureMetricName.sensorTemperatureRaw,
            averageMetricName: nil,
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
                menuBarMetric: nil,
                isMVPCompatibilityRequired: false
            )
    }

    static func menuBarMetric(for displayMetric: MenuBarDisplayMetric) -> TemperatureMetricDescriptor? {
        overviewMetrics.first(where: { $0.menuBarMetric == displayMetric })
    }
}
