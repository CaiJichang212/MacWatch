import Foundation
import MacWatchCore

struct TemperatureOverviewSnapshot: Equatable {
    struct Row: Identifiable, Equatable {
        let domain: TemperatureDomain
        let metricName: String
        let title: String
        let primaryValueText: String?
        let averageValueText: String?
        let abnormalStatusText: String?
        let sourceText: String
        let reasonText: String?
        let rawKey: String?
        let isStale: Bool

        var id: TemperatureDomain { domain }

        var isNormal: Bool { abnormalStatusText == nil }
    }

    let hottestValueText: String
    let updatedAt: Date?
    let rows: [Row]
    let availableMetricCount: Int
    let unavailableMetricTitles: [String]

    init(
        liveState: LiveTemperatureState?,
        settings: AppSettings,
        localizer: AppLocalizer = .english
    ) {
        hottestValueText = liveState?.hottestValidSample.flatMap {
            guard let value = $0.valueCelsius else {
                return nil
            }
            return TemperatureFormatter.text(celsius: value, unit: settings.temperatureUnit)
        } ?? TemperatureFormatter.placeholder(unit: settings.temperatureUnit)
        updatedAt = liveState?.updatedAt

        rows = TemperatureMetricCatalog.overviewMetrics.map { descriptor in
            let sample = liveState?.samplesByMetricName[descriptor.metricName]
            let averageSample = descriptor.averageMetricName.flatMap { liveState?.samplesByMetricName[$0] }
            let capability = liveState?.capabilitiesByDomain[descriptor.domain]
            let lastValidSample = liveState?.lastValidSamplesByMetricName[descriptor.metricName]
            let lastValidAverageSample = descriptor.averageMetricName.flatMap {
                liveState?.lastValidSamplesByMetricName[$0]
            }
            let isNormal = sample?.quality == .valid
            let isAverageValid = averageSample?.quality == .valid

            return Row(
                domain: descriptor.domain,
                metricName: descriptor.metricName,
                title: descriptor.localizedTitle(localizer),
                primaryValueText: isNormal ? TemperatureFormatter.valueText(
                    sample: sample,
                    lastValidSample: lastValidSample,
                    unit: settings.temperatureUnit
                ) : nil,
                averageValueText: isNormal && isAverageValid ? TemperatureFormatter.valueText(
                    sample: averageSample,
                    lastValidSample: lastValidAverageSample,
                    unit: settings.temperatureUnit
                ) : nil,
                abnormalStatusText: isNormal ? nil : TemperatureFormatter.statusText(
                    sample: sample,
                    capability: capability,
                    localizer: localizer
                ),
                sourceText: TemperatureFormatter.sourceText(sample: sample, capability: capability),
                reasonText: isNormal ? nil : TemperatureFormatter.reasonText(
                    sample: sample,
                    capability: capability,
                    localizer: localizer
                ),
                rawKey: TemperatureFormatter.rawKeyText(sample: sample, capability: capability),
                isStale: TemperatureFormatter.isStale(sample: sample)
            )
        }

        availableMetricCount = rows.filter { row in
            liveState?.samplesByMetricName[row.metricName]?.quality == .valid
        }.count
        unavailableMetricTitles = rows
            .filter { $0.isNormal == false }
            .map(\.title)
    }
}
