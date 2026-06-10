import MacWatchCore
import SwiftUI

struct TemperatureDetailView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    let domain: TemperatureDomain
    @State private var selectedRange: TemperatureHistoryRange = .oneHour

    var body: some View {
        let metricName = TemperatureDashboardSnapshot.metricName(for: domain)
        let series = runtime.series(
            domain: domain,
            metricName: metricName,
            range: selectedRange,
            maxPoints: 2_000
        )
        let fallback = TemperatureDashboardSnapshot(liveState: runtime.liveState)
            .rows
            .first(where: { $0.domain == domain })?
            .statusText ?? "No samples yet"
        let snapshot = TemperatureDetailSnapshot(
            domainTitle: TemperatureDashboardSnapshot.title(for: domain),
            series: series,
            fallbackText: fallback
        )

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.title)
                        .font(.title2.weight(.semibold))
                    Text(snapshot.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Range", selection: $selectedRange) {
                    ForEach(TemperatureHistoryRange.allCases, id: \.self) { range in
                        Text(rangeLabel(range)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }

            HStack(alignment: .firstTextBaseline, spacing: 24) {
                statBlock(label: "Current", value: snapshot.currentValueText)
                statBlock(label: "Max", value: snapshot.maximumText)
                statBlock(label: "Min", value: snapshot.minimumText)
                statBlock(label: "Avg", value: snapshot.averageText)
                statBlock(label: "Peak", value: snapshot.peakTimeText)
            }

            TemperatureTrendView(
                title: "\(snapshot.title) Trend",
                series: series,
                fallbackText: fallback
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

struct TemperatureDetailSnapshot: Equatable {
    let title: String
    let currentValueText: String
    let statusText: String
    let maximumText: String
    let minimumText: String
    let averageText: String
    let peakTimeText: String

    init(domainTitle: String, series: TemperatureSeries?, fallbackText: String) {
        self.title = domainTitle

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        guard let series else {
            currentValueText = "--°C"
            statusText = fallbackText
            maximumText = "--"
            minimumText = "--"
            averageText = "--"
            peakTimeText = "--"
            return
        }

        let latestValid = series.samples
            .filter { $0.quality == .valid && $0.valueCelsius != nil }
            .max { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.timestamp < rhs.timestamp
            }

        currentValueText = latestValid.map(MenuBarTemperatureFormatter.title(for:)) ?? "--°C"
        maximumText = Self.formatValue(series.statistics.maximumCelsius)
        minimumText = Self.formatValue(series.statistics.minimumCelsius)
        averageText = Self.formatValue(series.statistics.averageCelsius)
        peakTimeText = series.statistics.peakAt.map(formatter.string(from:)) ?? "--"

        if series.statistics.validSampleCount > 0 {
            let sampleWord = series.statistics.validSampleCount == 1 ? "sample" : "samples"
            statusText = "\(series.statistics.validSampleCount) \(sampleWord)"
        } else {
            statusText = fallbackText
        }
    }

    private static func formatValue(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return MenuBarTemperatureFormatter.title(forCelsius: value)
    }
}
