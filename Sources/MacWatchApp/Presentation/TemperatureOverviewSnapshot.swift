import Foundation
import MacWatchCore

struct TemperatureOverviewSnapshot: Equatable {
    struct Row: Identifiable, Equatable {
        let domain: TemperatureDomain
        let metricName: String
        let title: String
        let valueText: String
        let statusText: String
        let sourceText: String
        let reasonText: String?
        let updatedAt: Date?
        let rawKey: String?
        let isStale: Bool

        var id: TemperatureDomain { domain }

        var updatedAtText: String {
            TemperatureTimestampFormatter.shortTimeText(updatedAt)
        }
    }

    let hottestValueText: String
    let hottestUpdatedAt: Date?
    let rows: [Row]
    let availableMetricCount: Int
    let unavailableMetricTitles: [String]

    init(
        liveState: LiveTemperatureState?,
        settings: AppSettings
    ) {
        hottestValueText = liveState?.hottestValidSample.flatMap {
            guard let value = $0.valueCelsius else {
                return nil
            }
            return TemperatureFormatter.text(celsius: value, unit: settings.temperatureUnit)
        } ?? TemperatureFormatter.placeholder(unit: settings.temperatureUnit)
        hottestUpdatedAt = liveState?.hottestValidSample?.timestamp

        rows = TemperatureMetricCatalog.overviewMetrics.map { descriptor in
            let sample = liveState?.samplesByMetricName[descriptor.metricName]
            let capability = liveState?.capabilitiesByDomain[descriptor.domain]
            let lastValidSample = liveState?.lastValidSamplesByMetricName[descriptor.metricName]

            return Row(
                domain: descriptor.domain,
                metricName: descriptor.metricName,
                title: descriptor.title,
                valueText: TemperatureFormatter.valueText(
                    sample: sample,
                    lastValidSample: lastValidSample,
                    unit: settings.temperatureUnit
                ),
                statusText: TemperatureFormatter.statusText(sample: sample, capability: capability),
                sourceText: TemperatureFormatter.sourceText(sample: sample, capability: capability),
                reasonText: TemperatureFormatter.reasonText(sample: sample, capability: capability),
                updatedAt: sample?.timestamp ?? capability?.updatedAt,
                rawKey: sample?.rawKey ?? capability?.rawKey,
                isStale: TemperatureFormatter.isStale(sample: sample)
            )
        }

        availableMetricCount = rows.filter { row in
            liveState?.samplesByMetricName[row.metricName]?.quality == .valid
        }.count
        unavailableMetricTitles = rows
            .filter { $0.statusText != "Valid" }
            .map(\.title)
    }
}
