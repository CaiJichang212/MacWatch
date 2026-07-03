import Charts
import MacWatchCore
import SwiftUI

struct TemperatureTrendView: View {
    let title: String
    let series: TemperatureSeries?
    let fallbackText: String
    let unit: TemperatureUnit
    let localizer: AppLocalizer

    @State private var highlightedSample: TemperatureSample?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if let series, validSamples(series).isEmpty == false {
                Chart {
                    ForEach(TemperatureTrendSegments.renderSegments(for: series)) { segment in
                        ForEach(segment.samples) { sample in
                            if let valueCelsius = sample.valueCelsius {
                                LineMark(
                                    x: .value("Time", sample.timestamp),
                                    y: .value("Temperature", chartValue(valueCelsius)),
                                    series: .value("Segment", segment.id)
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }
                    }

                    if let highlightedSample,
                       let valueCelsius = highlightedSample.valueCelsius {
                        RuleMark(x: .value("Selected Time", highlightedSample.timestamp))
                            .foregroundStyle(.secondary.opacity(0.4))
                        PointMark(
                            x: .value("Selected Time", highlightedSample.timestamp),
                            y: .value("Selected Temperature", chartValue(valueCelsius))
                        )
                        .symbolSize(60)
                    }
                }
                .frame(height: 240)
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    let frame = geometry[proxy.plotAreaFrame]
                                    let relativeX = location.x - frame.origin.x
                                    guard relativeX >= 0,
                                          relativeX <= proxy.plotAreaSize.width,
                                          let date: Date = proxy.value(atX: relativeX) else {
                                        highlightedSample = nil
                                        return
                                    }
                                    highlightedSample = TemperatureTrendHoverResolver.nearestSample(
                                        to: date,
                                        in: validSamples(series)
                                    )
                                case .ended:
                                    highlightedSample = nil
                                }
                            }
                    }
                }

                if let highlightedSample {
                    HStack {
                        Text(Self.timeFormatter(locale: localizer.locale).string(from: highlightedSample.timestamp))
                        if let valueCelsius = highlightedSample.valueCelsius {
                            Text(TemperatureFormatter.text(celsius: valueCelsius, unit: unit))
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if series.gaps.isEmpty == false {
                    Text(localizer.string("trend.gaps"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(fallbackText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func validSamples(_ series: TemperatureSeries) -> [TemperatureSample] {
        series.samples.filter { $0.quality == .valid && $0.valueCelsius != nil }
    }

    private func chartValue(_ celsius: Double) -> Double {
        switch unit {
        case .celsius:
            return celsius
        case .fahrenheit:
            return celsius * 9 / 5 + 32
        }
    }

    private static func timeFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }
}

enum TemperatureTrendSegments {
    static func segments(for series: TemperatureSeries) -> [[TemperatureSample]] {
        TemperatureSeriesDownsampler().validSegments(
            samples: series.samples,
            gaps: series.gaps
        )
    }

    static func renderSegments(for series: TemperatureSeries) -> [TemperatureTrendRenderSegment] {
        segments(for: series).enumerated().map { offset, samples in
            TemperatureTrendRenderSegment(
                id: "\(series.metricName)-segment-\(offset)",
                samples: samples
            )
        }
    }
}

struct TemperatureTrendRenderSegment: Identifiable, Equatable {
    let id: String
    let samples: [TemperatureSample]
}

enum TemperatureTrendHoverResolver {
    static func nearestSample(to timestamp: Date, in samples: [TemperatureSample]) -> TemperatureSample? {
        samples.min(by: { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(timestamp)) < abs(rhs.timestamp.timeIntervalSince(timestamp))
        })
    }
}
