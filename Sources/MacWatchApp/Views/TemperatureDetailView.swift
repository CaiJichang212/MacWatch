import MacWatchCore
import SwiftUI

struct TemperatureDetailView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    let descriptor: TemperatureMetricDescriptor
    @State private var selectedRange: TemperatureHistoryRange = .oneHour
    @State private var selectedMetricName: String
    @State private var hasAppliedDefaultRange = false
    @State private var series: TemperatureSeries?

    init(descriptor: TemperatureMetricDescriptor) {
        self.descriptor = descriptor
        _selectedMetricName = State(initialValue: descriptor.metricName)
    }

    init(domain: TemperatureDomain) {
        self.init(descriptor: TemperatureMetricCatalog.requiredMetric(for: domain))
    }

    var body: some View {
        let localizer = runtime.localizer
        let fallback = TemperatureOverviewSnapshot(
            liveState: runtime.liveState,
            settings: runtime.settings,
            localizer: localizer
        )
        .rows
        .first(where: { $0.domain == descriptor.domain })?
        .abnormalStatusText ?? localizer.string("status.waiting")
        let selectedDescriptor = selectedDetailDescriptor
        let snapshot = TemperatureDetailSnapshot(
            descriptor: selectedDescriptor,
            series: series,
            currentSample: runtime.liveState?.samplesByMetricName[effectiveSelectedMetricName],
            currentCapability: runtime.liveState?.capabilitiesByDomain[descriptor.domain],
            lastValidSample: runtime.liveState?.lastValidSamplesByMetricName[effectiveSelectedMetricName],
            fallbackText: fallback,
            settings: runtime.settings,
            localizer: localizer
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.title)
                            .font(.title2.weight(.semibold))
                        Text(snapshot.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if descriptor.detailMetricOptions.count > 1 {
                        Picker(localizer.string("detail.metric"), selection: $selectedMetricName) {
                            ForEach(descriptor.detailMetricOptions) { option in
                                Text(localizedDetailOptionLabel(for: option.metricName, localizer: localizer)).tag(option.metricName)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    Picker(localizer.string("detail.range"), selection: $selectedRange) {
                        ForEach(TemperatureHistoryRange.allCases, id: \.self) { range in
                            Text(rangeLabel(range, localizer: localizer)).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                statGrid(snapshot: snapshot, localizer: localizer)

                metaCard(snapshot: snapshot, localizer: localizer)

                TemperatureTrendView(
                    title: localizer.string("detail.trendTitle", snapshot.title),
                    series: series,
                    fallbackText: snapshot.trendFallbackText,
                    unit: runtime.settings.temperatureUnit,
                    localizer: localizer
                )
            }
            .padding(24)
        }
        .navigationTitle(descriptor.localizedTitle(localizer))
        .task {
            guard hasAppliedDefaultRange == false else {
                return
            }
            selectedRange = runtime.settings.defaultTrendRange
            hasAppliedDefaultRange = true
        }
        .onChange(of: descriptor) { newDescriptor in
            selectedMetricName = newDescriptor.metricName
            series = nil
        }
        .task(id: detailQueryKey) {
            let expectedKey = detailQueryKey
            let loaded = await runtime.loadSeries(
                domain: descriptor.domain,
                metricName: effectiveSelectedMetricName,
                range: selectedRange,
                maxPoints: 2_000
            )
            guard Task.isCancelled == false, expectedKey == detailQueryKey else {
                return
            }
            series = loaded
        }
    }

    private func statGrid(snapshot: TemperatureDetailSnapshot, localizer: AppLocalizer) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 12
        ) {
            statCard(label: localizer.string("detail.current"), value: snapshot.currentValueText)
            statCard(label: localizer.string("detail.maximum"), value: snapshot.maximumText)
            statCard(label: localizer.string("detail.minimum"), value: snapshot.minimumText)
            statCard(label: localizer.string("detail.average"), value: snapshot.averageText)
            statCard(label: localizer.string("detail.peakTime"), value: snapshot.peakTimeText)
            statCard(label: localizer.string("detail.source"), value: snapshot.sourceText)
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

    private func metaCard(snapshot: TemperatureDetailSnapshot, localizer: AppLocalizer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizer.string("detail.sampling"))
                .font(.headline)
            Text(localizer.string("detail.realtimeInterval", Int(runtime.effectiveRealtimeInterval(for: descriptor.domain))))
                .foregroundStyle(.secondary)
            Text(localizer.string("detail.state", snapshot.statusText))
                .foregroundStyle(.secondary)
            Text(localizer.string("detail.samplesInRange", snapshot.sampleSummaryText))
                .foregroundStyle(.secondary)
            if let rawKeyText = snapshot.rawKeyText {
                Text(localizer.string("detail.rawKey", rawKeyText))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func rangeLabel(_ range: TemperatureHistoryRange, localizer: AppLocalizer) -> String {
        localizer.shortRangeLabel(range)
    }

    private var detailQueryKey: DetailQueryKey {
        DetailQueryKey(
            sessionID: runtime.currentSession?.id,
            domain: descriptor.domain,
            metricName: effectiveSelectedMetricName,
            range: selectedRange,
            historyRevision: runtime.historyRevision
        )
    }

    private var effectiveSelectedMetricName: String {
        descriptor.resolvedDetailMetricName(selectedMetricName)
    }

    private var selectedDetailDescriptor: TemperatureMetricDescriptor {
        let metricName = effectiveSelectedMetricName
        return TemperatureMetricDescriptor(
            id: descriptor.id,
            domain: descriptor.domain,
            metricName: metricName,
            averageMetricName: nil,
            menuBarMetric: descriptor.menuBarMetric,
            isMVPCompatibilityRequired: descriptor.isMVPCompatibilityRequired
        )
    }

    private func localizedDetailOptionLabel(for metricName: String, localizer: AppLocalizer) -> String {
        descriptor.localizedDetailOptionLabel(for: metricName, localizer: localizer)
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
    let rawKeyText: String?
    let trendFallbackText: String

    init(
        descriptor: TemperatureMetricDescriptor,
        series: TemperatureSeries?,
        currentSample: TemperatureSample?,
        currentCapability: TemperatureCapability?,
        lastValidSample: TemperatureSample?,
        fallbackText: String,
        settings: AppSettings,
        localizer: AppLocalizer = .english
    ) {
        let metricTitle = descriptor.localizedTitle(localizer)
        let optionSuffix = descriptor.metricName == TemperatureMetricCatalog.requiredMetric(for: descriptor.domain).metricName
            ? nil
            : descriptor.localizedDetailOptionLabel(for: descriptor.metricName, localizer: localizer)
        self.title = optionSuffix.map { "\(metricTitle) \($0)" } ?? metricTitle
        currentValueText = TemperatureFormatter.valueText(
            sample: currentSample,
            lastValidSample: lastValidSample,
            unit: settings.temperatureUnit
        )
        let liveStatus = TemperatureFormatter.statusText(
            sample: currentSample,
            capability: currentCapability,
            localizer: localizer
        )
        statusText = liveStatus == localizer.string("status.waiting") ? fallbackText : liveStatus

        guard let series else {
            sampleSummaryText = fallbackText
            maximumText = "--"
            minimumText = "--"
            averageText = "--"
            peakTimeText = "--"
            sourceText = TemperatureFormatter.sourceText(sample: currentSample, capability: currentCapability)
            rawKeyText = TemperatureFormatter.rawKeyText(sample: currentSample, capability: currentCapability)
            trendFallbackText = fallbackText
            return
        }
        let validSampleCount = series.statistics.validSampleCount
        sampleSummaryText = Self.sampleSummaryText(
            validSampleCount: validSampleCount,
            localizer: localizer
        )
        maximumText = Self.formatValue(series.statistics.maximumCelsius, unit: settings.temperatureUnit)
        minimumText = Self.formatValue(series.statistics.minimumCelsius, unit: settings.temperatureUnit)
        averageText = Self.formatValue(series.statistics.averageCelsius, unit: settings.temperatureUnit)
        peakTimeText = TemperatureTimestampFormatter.shortTimeText(series.statistics.peakAt, locale: localizer.locale)
        sourceText = TemperatureFormatter.sourceText(sample: currentSample, capability: currentCapability)
        rawKeyText = TemperatureFormatter.rawKeyText(sample: currentSample, capability: currentCapability)
        trendFallbackText = validSampleCount == 0 ? localizer.string("detail.noSamplesInSelectedRange") : fallbackText
    }

    init(domainTitle: String, series: TemperatureSeries?, fallbackText: String) {
        self.init(
            descriptor: TemperatureMetricDescriptor(
                id: series?.domain ?? .cpu,
                domain: series?.domain ?? .cpu,
                metricName: series?.metricName ?? TemperatureMetricName.cpuHottest,
                averageMetricName: nil,
                menuBarMetric: nil,
                isMVPCompatibilityRequired: false
            ),
            series: series,
            currentSample: nil,
            currentCapability: nil,
            lastValidSample: nil,
            fallbackText: fallbackText,
            settings: .default,
            localizer: .english
        )
    }

    private static func formatValue(_ value: Double?, unit: TemperatureUnit) -> String {
        guard let value else {
            return "--"
        }
        return TemperatureFormatter.text(celsius: value, unit: unit)
    }

    private static func sampleSummaryText(validSampleCount: Int, localizer: AppLocalizer) -> String {
        let key = validSampleCount == 1 ? "detail.sampleCount.one" : "detail.sampleCount.other"
        return localizer.string(key, validSampleCount)
    }
}

private struct DetailQueryKey: Equatable {
    let sessionID: UUID?
    let domain: TemperatureDomain
    let metricName: String
    let range: TemperatureHistoryRange
    let historyRevision: Int
}
