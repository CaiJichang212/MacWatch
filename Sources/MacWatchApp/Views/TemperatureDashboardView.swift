import MacWatchCore
import SwiftUI

struct TemperatureDashboardView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    let onSelectMetric: (TemperatureDomain) -> Void
    let onOpenCompatibility: () -> Void

    @State private var trendDomain: TemperatureDomain = .cpu
    @State private var trendSeries: TemperatureSeries?

    var body: some View {
        let localizer = runtime.localizer
        let snapshot = TemperatureOverviewSnapshot(
            liveState: runtime.liveState,
            settings: runtime.settings,
            localizer: localizer
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard(snapshot: snapshot, localizer: localizer)
                metricGrid(snapshot: snapshot, localizer: localizer)
                trendSummary(snapshot: snapshot, descriptor: selectedDescriptor, localizer: localizer)
                unavailableCard(snapshot: snapshot, localizer: localizer)
            }
            .padding(20)
        }
        .navigationTitle(localizer.string("dashboard.title"))
        .onAppear {
            AcceptanceCoordinator.shared.recordViewAppeared(.dashboard)
        }
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

    private func summaryCard(snapshot: TemperatureOverviewSnapshot, localizer: AppLocalizer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizer.string("dashboard.currentHottestTemperature"))
                .font(.headline)

            Text(snapshot.hottestValueText)
                .font(.system(size: 40, weight: .semibold, design: .rounded))

            Text(localizer.string(
                "dashboard.updated",
                formattedTimestamp(snapshot.updatedAt, locale: localizer.locale)
            ))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metricGrid(snapshot: TemperatureOverviewSnapshot, localizer: AppLocalizer) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 14),
            ],
            spacing: 14
        ) {
            ForEach(snapshot.rows) { row in
                Button {
                    onSelectMetric(row.domain)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(row.title)
                                .font(.headline)
                            Spacer()
                            if let primaryValueText = row.primaryValueText {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(primaryValueText)
                                        .font(.title3.weight(.semibold))
                                    if let averageValueText = row.averageValueText {
                                        Text(localizer.string("popup.average", averageValueText))
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if let statusText = row.abnormalStatusText {
                            Text(statusText)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(row.isStale ? .secondary : .primary)

                            if let reasonText = row.reasonText {
                                Text(reasonText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func trendSummary(
        snapshot: TemperatureOverviewSnapshot,
        descriptor: TemperatureMetricDescriptor,
        localizer: AppLocalizer
    ) -> some View {
        let fallbackText = snapshot.rows.first(where: { $0.domain == descriptor.domain })?.abnormalStatusText
            ?? localizer.string("status.waiting")

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localizer.string("dashboard.recentTrend1Hour"))
                    .font(.headline)

                Spacer()

                Picker(localizer.string("dashboard.metric"), selection: $trendDomain) {
                    ForEach(TemperatureMetricCatalog.overviewMetrics) { metric in
                        Text(metric.localizedTitle(localizer)).tag(metric.domain)
                    }
                }
                .pickerStyle(.menu)

                Button(localizer.string("dashboard.details")) {
                    onSelectMetric(descriptor.domain)
                }
            }

            TemperatureTrendView(
                title: descriptor.localizedTitle(localizer),
                series: trendSeries,
                fallbackText: fallbackText,
                unit: runtime.settings.temperatureUnit,
                localizer: localizer
            )
        }
    }

    private func unavailableCard(snapshot: TemperatureOverviewSnapshot, localizer: AppLocalizer) -> some View {
        guard snapshot.unavailableMetricTitles.isEmpty == false else {
            return AnyView(EmptyView())
        }

        return AnyView(
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localizer.string("dashboard.unavailableMetrics"))
                    .font(.headline)
                Spacer()
                Button(localizer.string("navigation.compatibility")) {
                    onOpenCompatibility()
                }
            }

            Text(snapshot.unavailableMetricTitles.joined(separator: ", "))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        )
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

    private func formattedTimestamp(_ timestamp: Date?, locale: Locale) -> String {
        TemperatureTimestampFormatter.shortTimeText(timestamp, locale: locale)
    }
}

private struct TrendQueryKey: Equatable {
    let sessionID: UUID?
    let domain: TemperatureDomain
    let metricName: String
    let historyRevision: Int
}
