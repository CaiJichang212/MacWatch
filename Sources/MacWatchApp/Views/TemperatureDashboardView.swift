import MacWatchCore
import SwiftUI

struct TemperatureDashboardView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime
    @State private var selectedTrendDomain: TemperatureDomain = .cpu

    var body: some View {
        let snapshot = TemperatureDashboardSnapshot(liveState: runtime.liveState)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("MacWatch")
                    .font(.largeTitle)
                    .bold()

                summaryCard(snapshot: snapshot)

                domainGrid(snapshot: snapshot)

                TemperatureTrendView(
                    title: "\(title(for: selectedTrendDomain)) Session Trend",
                    series: runtime.series(
                        domain: selectedTrendDomain,
                        metricName: metricName(for: selectedTrendDomain),
                        range: .oneHour
                    ),
                    fallbackText: snapshot.rows.first(where: { $0.domain == selectedTrendDomain })?.statusText ?? "No samples yet"
                )

                TemperatureDetailView(domain: selectedTrendDomain)
            }
            .padding(24)
        }
    }

    private func summaryCard(snapshot: TemperatureDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Hottest Temperature")
                .font(.headline)

            Text(snapshot.hottestTitle)
                .font(.system(size: 40, weight: .semibold, design: .rounded))

            Text("Updated: \(runtime.liveState?.updatedAt.map(Self.timestampFormatter.string(from:)) ?? "--")")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func domainGrid(snapshot: TemperatureDashboardSnapshot) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
            ],
            spacing: 14
        ) {
            ForEach(snapshot.rows) { row in
                Button {
                    selectedTrendDomain = row.domain
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.title)
                            .font(.headline)
                        Text(row.statusText)
                            .font(.title3.weight(.semibold))
                        Text(row.detailText)
                            .foregroundStyle(.secondary)
                        if let rawKey = row.rawKey {
                            Text("Raw Key: \(rawKey)")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
                    .padding(16)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                selectedTrendDomain == row.domain
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.2),
                                lineWidth: selectedTrendDomain == row.domain ? 2 : 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func title(for domain: TemperatureDomain) -> String {
        TemperatureDashboardSnapshot.title(for: domain)
    }

    private func metricName(for domain: TemperatureDomain) -> String {
        TemperatureDashboardSnapshot.metricName(for: domain)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}

struct TemperatureDashboardSnapshot: Equatable {
    struct Row: Identifiable, Equatable {
        let domain: TemperatureDomain
        let title: String
        let statusText: String
        let detailText: String
        let rawKey: String?

        var id: TemperatureDomain { domain }
    }

    let hottestTitle: String
    let rows: [Row]

    init(liveState: LiveTemperatureState?) {
        hottestTitle = MenuBarTemperatureFormatter.title(for: liveState?.hottestValidSample)
        rows = Self.supportedDomains.map { domain in
            let metricName = Self.metricName(for: domain)
            let sample = liveState?.samplesByMetricName[metricName]
            let capability = liveState?.capabilitiesByDomain[domain]

            let statusText: String
            let detailText: String
            let rawKey: String?

            if let sample {
                rawKey = sample.rawKey
                switch sample.quality {
                case .valid:
                    statusText = MenuBarTemperatureFormatter.title(for: sample)
                    detailText = sample.source.rawValue
                case .unsupported:
                    statusText = "Unsupported"
                    detailText = sample.errorCode ?? capability?.reasonCode ?? "unsupported"
                case .readFailed:
                    statusText = "Read failed"
                    detailText = sample.errorCode ?? capability?.reasonCode ?? "readFailed"
                case .stale:
                    statusText = "Stale"
                    detailText = sample.errorCode ?? capability?.reasonCode ?? "stale"
                }
            } else if let capability {
                rawKey = capability.rawKey
                if capability.supported == false || capability.readable == false {
                    statusText = capability.reasonCode == "unsupported" ? "Unsupported" : "Read failed"
                    detailText = capability.source.rawValue
                } else {
                    statusText = "Waiting"
                    detailText = capability.source.rawValue
                }
            } else {
                rawKey = nil
                statusText = "Waiting"
                detailText = "No capability yet"
            }

            return Row(
                domain: domain,
                title: Self.title(for: domain),
                statusText: statusText,
                detailText: detailText,
                rawKey: rawKey
            )
        }
    }

    static let supportedDomains: [TemperatureDomain] = [
        .cpu,
        .gpu,
        .memory,
        .ssd,
        .battery,
    ]

    static func title(for domain: TemperatureDomain) -> String {
        switch domain {
        case .cpu:
            return "CPU"
        case .gpu:
            return "GPU"
        case .memory:
            return "Memory"
        case .ssd:
            return "SSD/NAND"
        case .battery:
            return "Battery"
        case .system:
            return "System"
        case .sensor:
            return "Sensor"
        }
    }

    static func metricName(for domain: TemperatureDomain) -> String {
        switch domain {
        case .cpu:
            return TemperatureMetricName.cpuHottest
        case .gpu:
            return TemperatureMetricName.gpuHottest
        case .memory:
            return TemperatureMetricName.memoryProximity
        case .ssd:
            return TemperatureMetricName.ssdInternal
        case .battery:
            return TemperatureMetricName.battery
        case .system:
            return TemperatureMetricName.systemHottest
        case .sensor:
            return "sensor.temperature.raw"
        }
    }
}
