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

    init(liveState: LiveTemperatureState?) {
        rows = TemperatureMetricCatalog.compatibilityMetrics.map { descriptor in
            let sample = liveState?.samplesByMetricName[descriptor.metricName]
            let capability = liveState?.capabilitiesByDomain[descriptor.domain]

            return Row(
                domain: descriptor.domain,
                title: descriptor.title,
                statusText: TemperatureFormatter.statusText(sample: sample, capability: capability),
                sourceText: TemperatureFormatter.sourceText(sample: sample, capability: capability),
                reasonText: TemperatureFormatter.reasonText(sample: sample, capability: capability),
                rawKey: sample?.rawKey ?? capability?.rawKey,
                updatedAt: sample?.timestamp ?? capability?.updatedAt
            )
        }
    }
}
