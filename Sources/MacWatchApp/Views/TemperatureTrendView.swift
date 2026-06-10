import Charts
import MacWatchCore
import SwiftUI

struct TemperatureTrendView: View {
    let title: String
    let series: TemperatureSeries?
    let fallbackText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if let series, validSamples(series).isEmpty == false {
                Chart {
                    ForEach(Array(segmentedSamples(series).enumerated()), id: \.offset) { _, segment in
                        ForEach(segment) { sample in
                            if let valueCelsius = sample.valueCelsius {
                                LineMark(
                                    x: .value("Time", sample.timestamp),
                                    y: .value("Temperature", valueCelsius)
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }
                    }
                }
                .frame(height: 220)

                if series.gaps.isEmpty == false {
                    Text("Trend contains gaps caused by sleep or read failures.")
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
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func segmentedSamples(_ series: TemperatureSeries) -> [[TemperatureSample]] {
        let samples = validSamples(series)
        guard samples.isEmpty == false else {
            return []
        }

        guard series.gaps.isEmpty == false else {
            return [samples]
        }

        let gaps = series.gaps.sorted { $0.startedAt < $1.startedAt }
        var segments: [[TemperatureSample]] = []
        var currentSegment: [TemperatureSample] = []
        var gapIndex = 0

        for sample in samples {
            while gapIndex < gaps.count,
                  (gaps[gapIndex].endedAt ?? gaps[gapIndex].startedAt) < sample.timestamp {
                if currentSegment.isEmpty == false {
                    segments.append(currentSegment)
                    currentSegment = []
                }
                gapIndex += 1
            }

            currentSegment.append(sample)
        }

        if currentSegment.isEmpty == false {
            segments.append(currentSegment)
        }

        return segments
    }

    private func validSamples(_ series: TemperatureSeries) -> [TemperatureSample] {
        series.samples.filter { $0.quality == .valid && $0.valueCelsius != nil }
    }
}
