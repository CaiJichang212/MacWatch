import MacWatchCore
import SwiftUI

struct TemperatureDashboardView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    let onSelectMetric: (TemperatureDomain) -> Void
    let onOpenCompatibility: () -> Void

    @State private var trendDomain: TemperatureDomain = .cpu
    @State private var trendSeries: TemperatureSeries?

    var body: some View {
        let snapshot = TemperatureOverviewSnapshot(
            liveState: runtime.liveState,
            settings: runtime.settings
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard(snapshot: snapshot)
                metricGrid(snapshot: snapshot)
                trendSummary(snapshot: snapshot, descriptor: selectedDescriptor)
                unavailableCard(snapshot: snapshot)
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .task(id: trendQueryKey) {
            let expectedKey = trendQueryKey
            let loaded = await runtime.loadSeries(
                domain: selectedDescriptor.domain,
                metricName: selectedDescriptor.metricName,
                range: .oneHour,
                maxPoints: 240
            )
            guard Task.isCancelled == false, expectedKey == trendQueryKey else {
                return
            }
            trendSeries = loaded
        }
    }

    private func summaryCard(snapshot: TemperatureOverviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Hottest Temperature")
                .font(.headline)

            Text(snapshot.hottestValueText)
                .font(.system(size: 40, weight: .semibold, design: .rounded))

            HStack(spacing: 16) {
                Text("Updated: \(formattedTimestamp(snapshot.hottestUpdatedAt))")
                Text("Available: \(snapshot.availableMetricCount)/\(TemperatureMetricCatalog.overviewMetrics.count)")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricGrid(snapshot: TemperatureOverviewSnapshot) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
            ],
            spacing: 14
        ) {
            ForEach(snapshot.rows) { row in
                Button {
                    onSelectMetric(row.domain)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(row.title)
                                .font(.headline)
                            Spacer()
                            Text(row.valueText)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(row.statusText == "Valid" ? .primary : .secondary)
                        }

                        Text(row.statusText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(row.isStale ? .secondary : .primary)

                        Text("Source: \(row.sourceText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text("Updated: \(formattedTimestamp(row.updatedAt))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let reasonText = row.reasonText {
                            Text(reasonText)
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func trendSummary(
        snapshot: TemperatureOverviewSnapshot,
        descriptor: TemperatureMetricDescriptor
    ) -> some View {
        let fallbackText = snapshot.rows.first(where: { $0.domain == descriptor.domain })?.statusText ?? "Waiting"

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent 1 Hour Trend")
                    .font(.headline)

                Spacer()

                Picker("Metric", selection: $trendDomain) {
                    ForEach(TemperatureMetricCatalog.overviewMetrics) { metric in
                        Text(metric.title).tag(metric.domain)
                    }
                }
                .pickerStyle(.menu)

                Button("Details") {
                    onSelectMetric(descriptor.domain)
                }
            }

            TemperatureTrendView(
                title: descriptor.title,
                series: trendSeries,
                fallbackText: fallbackText,
                unit: runtime.settings.temperatureUnit
            )
        }
    }

    private func unavailableCard(snapshot: TemperatureOverviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Unavailable Metrics")
                    .font(.headline)
                Spacer()
                Button("Compatibility") {
                    onOpenCompatibility()
                }
            }

            if snapshot.unavailableMetricTitles.isEmpty {
                Text("All tracked metrics currently have valid readings.")
                    .foregroundStyle(.secondary)
            } else {
                Text(snapshot.unavailableMetricTitles.joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var selectedDescriptor: TemperatureMetricDescriptor {
        TemperatureMetricCatalog.requiredMetric(for: trendDomain)
    }

    private var trendQueryKey: TrendQueryKey {
        TrendQueryKey(
            sessionID: runtime.currentSession?.id,
            domain: selectedDescriptor.domain,
            metricName: selectedDescriptor.metricName,
            historyRevision: runtime.historyRevision
        )
    }

    private func formattedTimestamp(_ timestamp: Date?) -> String {
        TemperatureTimestampFormatter.shortTimeText(timestamp)
    }
}

private struct TrendQueryKey: Equatable {
    let sessionID: UUID?
    let domain: TemperatureDomain
    let metricName: String
    let historyRevision: Int
}
