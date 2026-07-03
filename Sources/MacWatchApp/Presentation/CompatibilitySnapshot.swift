import Foundation
import MacWatchCore

struct CompatibilitySnapshot: Equatable {
    struct Row: Identifiable, Equatable {
        let domain: TemperatureDomain
        let title: String
        let statusText: String
        let sourceText: String
        let reasonText: String?
        let rawKey: String?
        let updatedAt: Date?

        var id: TemperatureDomain { domain }
    }

    let rows: [Row]

    init(liveState: LiveTemperatureState?, localizer: AppLocalizer = .english) {
        rows = TemperatureMetricCatalog.compatibilityMetrics.map { descriptor in
            let sample = liveState?.samplesByMetricName[descriptor.metricName]
            let capability = liveState?.capabilitiesByDomain[descriptor.domain]

            return Row(
                domain: descriptor.domain,
                title: descriptor.localizedTitle(localizer),
                statusText: TemperatureFormatter.statusText(
                    sample: sample,
                    capability: capability,
                    localizer: localizer
                ),
                sourceText: TemperatureFormatter.sourceText(sample: sample, capability: capability),
                reasonText: TemperatureFormatter.reasonText(
                    sample: sample,
                    capability: capability,
                    localizer: localizer
                ),
                rawKey: TemperatureFormatter.rawKeyText(sample: sample, capability: capability),
                updatedAt: sample?.timestamp ?? capability?.updatedAt
            )
        }
    }
}
