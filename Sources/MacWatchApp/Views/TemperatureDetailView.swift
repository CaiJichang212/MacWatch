import MacWatchCore
import SwiftUI

struct TemperatureDetailView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    let descriptor: TemperatureMetricDescriptor
    @State private var selectedRange: TemperatureHistoryRange = .oneHour
    @State private var hasAppliedDefaultRange = false
    @State private var series: TemperatureSeries?

    init(descriptor: TemperatureMetricDescriptor) {
        self.descriptor = descriptor
    }

    init(domain: TemperatureDomain) {
        self.init(descriptor: TemperatureMetricCatalog.requiredMetric(for: domain))
    }

    var body: some View {
        let fallback = TemperatureOverviewSnapshot(
            liveState: runtime.liveState,
            settings: runtime.settings
        )
        .rows
        .first(where: { $0.domain == descriptor.domain })?
        .statusText ?? "Waiting"
        let snapshot = TemperatureDetailSnapshot(
            descriptor: descriptor,
            series: series,
            currentSample: runtime.liveState?.samplesByMetricName[descriptor.metricName],
            currentCapability: runtime.liveState?.capabilitiesByDomain[descriptor.domain],
            lastValidSample: runtime.liveState?.lastValidSamplesByMetricName[descriptor.metricName],
            fallbackText: fallback,
            settings: runtime.settings
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.title)
                            .font(.title2.weight(.semibold))
                        Text(snapshot.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("Range", selection: $selectedRange) {
                        ForEach(TemperatureHistoryRange.allCases, id: \.self) { range in
                            Text(rangeLabel(range)).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                statGrid(snapshot: snapshot)

                metaCard(snapshot: snapshot)

                TemperatureTrendView(
                    title: "\(snapshot.title) Trend",
                    series: series,
                    fallbackText: fallback,
                    unit: runtime.settings.temperatureUnit
                )
            }
            .padding(24)
        }
        .navigationTitle(descriptor.title)
        .task {
            guard hasAppliedDefaultRange == false else {
                return
            }
            selectedRange = runtime.settings.defaultTrendRange
            hasAppliedDefaultRange = true
        }
        .task(id: detailQueryKey) {
            let expectedKey = detailQueryKey
            let loaded = await runtime.loadSeries(
                domain: descriptor.domain,
                metricName: descriptor.metricName,
                range: selectedRange,
                maxPoints: 2_000
            )
            guard Task.isCancelled == false, expectedKey == detailQueryKey else {
                return
            }
            series = loaded
        }
    }

    private func statGrid(snapshot: TemperatureDetailSnapshot) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 12
        ) {
            statCard(label: "Current", value: snapshot.currentValueText)
            statCard(label: "Max", value: snapshot.maximumText)
            statCard(label: "Min", value: snapshot.minimumText)
            statCard(label: "Average", value: snapshot.averageText)
            statCard(label: "Peak Time", value: snapshot.peakTimeText)
            statCard(label: "Source", value: snapshot.sourceText)
        }
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metaCard(snapshot: TemperatureDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sampling")
                .font(.headline)
            Text("Realtime interval: \(Int(runtime.effectiveRealtimeInterval(for: descriptor.domain)))s")
                .foregroundStyle(.secondary)
            Text("State: \(snapshot.statusText)")
                .foregroundStyle(.secondary)
            Text("Samples in range: \(snapshot.sampleSummaryText)")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func rangeLabel(_ range: TemperatureHistoryRange) -> String {
        switch range {
        case .fifteenMinutes:
            return "15m"
        case .oneHour:
            return "1h"
        case .sixHours:
            return "6h"
        case .allSession:
            return "Session"
        }
    }

    private var detailQueryKey: DetailQueryKey {
        DetailQueryKey(
            sessionID: runtime.currentSession?.id,
            domain: descriptor.domain,
            metricName: descriptor.metricName,
            range: selectedRange,
            historyRevision: runtime.historyRevision
        )
    }
}

struct TemperatureDetailSnapshot: Equatable {
    let title: String
    let currentValueText: String
    let statusText: String
    let sampleSummaryText: String
    let maximumText: String
    let minimumText: String
    let averageText: String
    let peakTimeText: String
    let sourceText: String

    init(
        descriptor: TemperatureMetricDescriptor,
        series: TemperatureSeries?,
        currentSample: TemperatureSample?,
        currentCapability: TemperatureCapability?,
        lastValidSample: TemperatureSample?,
        fallbackText: String,
        settings: AppSettings
    ) {
        self.title = descriptor.title
        currentValueText = TemperatureFormatter.valueText(
            sample: currentSample,
            lastValidSample: lastValidSample,
            unit: settings.temperatureUnit
        )
        let liveStatus = TemperatureFormatter.statusText(sample: currentSample, capability: currentCapability)
        statusText = liveStatus == "Waiting" ? fallbackText : liveStatus

        guard let series else {
            sampleSummaryText = fallbackText
            maximumText = "--"
            minimumText = "--"
            averageText = "--"
            peakTimeText = "--"
            sourceText = TemperatureFormatter.sourceText(sample: currentSample, capability: currentCapability)
            return
        }
        sampleSummaryText = Self.sampleSummaryText(
            validSampleCount: series.statistics.validSampleCount,
            fallbackText: fallbackText
        )
        maximumText = Self.formatValue(series.statistics.maximumCelsius, unit: settings.temperatureUnit)
        minimumText = Self.formatValue(series.statistics.minimumCelsius, unit: settings.temperatureUnit)
        averageText = Self.formatValue(series.statistics.averageCelsius, unit: settings.temperatureUnit)
        peakTimeText = TemperatureTimestampFormatter.shortTimeText(series.statistics.peakAt)
        sourceText = TemperatureFormatter.sourceText(sample: currentSample, capability: currentCapability)
    }

    init(domainTitle: String, series: TemperatureSeries?, fallbackText: String) {
        self.init(
            descriptor: TemperatureMetricDescriptor(
                id: series?.domain ?? .cpu,
                domain: series?.domain ?? .cpu,
                metricName: series?.metricName ?? TemperatureMetricName.cpuHottest,
                title: domainTitle,
                menuBarMetric: nil,
                isMVPCompatibilityRequired: false
            ),
            series: series,
            currentSample: nil,
            currentCapability: nil,
            lastValidSample: nil,
            fallbackText: fallbackText,
            settings: .default
        )
    }

    private static func formatValue(_ value: Double?, unit: TemperatureUnit) -> String {
        guard let value else {
            return "--"
        }
        return TemperatureFormatter.text(celsius: value, unit: unit)
    }

    private static func sampleSummaryText(validSampleCount: Int, fallbackText: String) -> String {
        guard validSampleCount > 0 else {
            return fallbackText
        }

        let sampleWord = validSampleCount == 1 ? "sample" : "samples"
        return "\(validSampleCount) \(sampleWord)"
    }
}

private struct DetailQueryKey: Equatable {
    let sessionID: UUID?
    let domain: TemperatureDomain
    let metricName: String
    let range: TemperatureHistoryRange
    let historyRevision: Int
}
