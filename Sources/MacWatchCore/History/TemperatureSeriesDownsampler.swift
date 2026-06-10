import Foundation

public struct TemperatureSeriesDownsampler: Sendable {
    public init() {}

    public func reduce(
        samples: [TemperatureSample],
        gaps: [TimelineEvent],
        maxPoints: Int
    ) -> [TemperatureSample] {
        guard maxPoints > 0, samples.count > maxPoints else {
            return samples.sorted(by: TemperatureSeriesDownsampler.sampleOrder)
        }

        let sortedSamples = samples.sorted(by: TemperatureSeriesDownsampler.sampleOrder)
        let invalidSamples = sortedSamples.filter { sample in
            sample.quality != .valid || sample.valueCelsius == nil
        }
        let validSamples = sortedSamples.filter { sample in
            sample.quality == .valid && sample.valueCelsius != nil
        }

        let validBudget = max(1, maxPoints - min(invalidSamples.count, maxPoints - 1))
        let reducedValid = reduceValidSamples(
            validSamples,
            gaps: gaps,
            maxPoints: validBudget
        )

        var merged = (invalidSamples + reducedValid)
            .uniqued(by: \.id)
            .sorted(by: TemperatureSeriesDownsampler.sampleOrder)

        if merged.count > maxPoints {
            merged = evenlySpaced(samples: merged, maxPoints: maxPoints)
        }

        return merged
    }

    public func validSegments(
        samples: [TemperatureSample],
        gaps: [TimelineEvent]
    ) -> [[TemperatureSample]] {
        let validSamples = samples
            .filter { $0.quality == .valid && $0.valueCelsius != nil }
            .sorted(by: TemperatureSeriesDownsampler.sampleOrder)
        guard validSamples.isEmpty == false else {
            return []
        }

        let sortedGaps = gaps
            .filter(isGapEvent)
            .sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.startedAt < rhs.startedAt
            }

        guard sortedGaps.isEmpty == false else {
            return [validSamples]
        }

        var segments: [[TemperatureSample]] = []
        var current: [TemperatureSample] = []
        var gapIndex = 0

        for sample in validSamples {
            while gapIndex < sortedGaps.count {
                let gap = sortedGaps[gapIndex]
                let gapEnd = gap.endedAt ?? gap.startedAt

                if sample.timestamp < gap.startedAt {
                    break
                }

                if current.isEmpty == false {
                    segments.append(current)
                    current = []
                }

                gapIndex += 1
                if sample.timestamp <= gapEnd {
                    break
                }
            }

            current.append(sample)
        }

        if current.isEmpty == false {
            segments.append(current)
        }

        return segments
    }

    private func reduceValidSamples(
        _ validSamples: [TemperatureSample],
        gaps: [TimelineEvent],
        maxPoints: Int
    ) -> [TemperatureSample] {
        guard validSamples.count > maxPoints else {
            return validSamples
        }

        let segments = validSegments(samples: validSamples, gaps: gaps)
        guard segments.isEmpty == false else {
            return Array(validSamples.prefix(maxPoints))
        }

        var chosenIDs = Set<UUID>()
        var chosenSamples: [TemperatureSample] = []

        for segment in segments {
            for sample in importantSamples(in: segment) {
                if chosenIDs.insert(sample.id).inserted {
                    chosenSamples.append(sample)
                }
            }
        }

        if chosenSamples.count >= maxPoints {
            return compress(
                samples: chosenSamples,
                mandatorySamples: importantSamples(in: validSamples),
                maxPoints: maxPoints
            )
        }

        let remainingBudget = maxPoints - chosenSamples.count
        let remainingCandidates = validSamples.filter { chosenIDs.contains($0.id) == false }
        let extraSamples = evenlySpaced(samples: remainingCandidates, maxPoints: remainingBudget)

        for sample in extraSamples where chosenIDs.insert(sample.id).inserted {
            chosenSamples.append(sample)
        }

        return chosenSamples.sorted(by: TemperatureSeriesDownsampler.sampleOrder)
    }

    private func importantSamples(in segment: [TemperatureSample]) -> [TemperatureSample] {
        guard let first = segment.first, let last = segment.last else {
            return []
        }

        let minSample = segment.min(by: compareByValueThenTime)
        let maxSample = segment.max(by: compareByValueThenTime)

        return [first, last, minSample, maxSample]
            .compactMap { $0 }
            .uniqued(by: \.id)
    }

    private func compress(
        samples: [TemperatureSample],
        mandatorySamples: [TemperatureSample],
        maxPoints: Int
    ) -> [TemperatureSample] {
        let required = prioritizedMandatorySamples(
            from: mandatorySamples,
            maxPoints: maxPoints
        )
        let requiredIDs = Set(required.map(\.id))

        guard required.count < maxPoints else {
            return required.sorted(by: TemperatureSeriesDownsampler.sampleOrder)
        }

        let remainingBudget = maxPoints - required.count
        let remainingCandidates = samples.filter { requiredIDs.contains($0.id) == false }
        let extras = evenlySpaced(samples: remainingCandidates, maxPoints: remainingBudget)

        return (required + extras)
            .uniqued(by: \.id)
            .sorted(by: TemperatureSeriesDownsampler.sampleOrder)
    }

    private func prioritizedMandatorySamples(
        from samples: [TemperatureSample],
        maxPoints: Int
    ) -> [TemperatureSample] {
        guard maxPoints > 0 else {
            return []
        }
        guard let first = samples.min(by: compareByTime),
              let last = samples.max(by: compareByTime),
              let minSample = samples.min(by: compareByValueThenTime),
              let maxSample = samples.max(by: compareByValueThenTime) else {
            return []
        }

        return [first, maxSample, minSample, last]
            .uniqued(by: \.id)
            .prefix(maxPoints)
            .map { $0 }
    }

    private func evenlySpaced(
        samples: [TemperatureSample],
        maxPoints: Int
    ) -> [TemperatureSample] {
        guard maxPoints > 0, samples.isEmpty == false else {
            return []
        }
        guard samples.count > maxPoints else {
            return samples.sorted(by: TemperatureSeriesDownsampler.sampleOrder)
        }

        let sorted = samples.sorted(by: TemperatureSeriesDownsampler.sampleOrder)
        if maxPoints == 1 {
            return [sorted[sorted.count / 2]]
        }

        var result: [TemperatureSample] = []
        result.reserveCapacity(maxPoints)

        for index in 0..<maxPoints {
            let ratio = Double(index) / Double(maxPoints - 1)
            let sampleIndex = Int((ratio * Double(sorted.count - 1)).rounded())
            result.append(sorted[sampleIndex])
        }

        return result.uniqued(by: \.id).sorted(by: TemperatureSeriesDownsampler.sampleOrder)
    }

    private func compareByValueThenTime(_ lhs: TemperatureSample, _ rhs: TemperatureSample) -> Bool {
        let lhsValue = lhs.valueCelsius ?? -.infinity
        let rhsValue = rhs.valueCelsius ?? -.infinity
        if lhsValue == rhsValue {
            return TemperatureSeriesDownsampler.sampleOrder(lhs, rhs)
        }
        return lhsValue < rhsValue
    }

    private func compareByTime(_ lhs: TemperatureSample, _ rhs: TemperatureSample) -> Bool {
        TemperatureSeriesDownsampler.sampleOrder(lhs, rhs)
    }

    private func isGapEvent(_ event: TimelineEvent) -> Bool {
        switch event.eventType {
        case .appStarted,
             .appTerminating,
             .systemSleepEnded,
             .historyCleared:
            return false
        case .systemSleepStarted,
             .probeReadFailed,
             .probeUnsupported,
             .probeStale,
             .historyWriteFailed:
            return true
        }
    }

    private static func sampleOrder(_ lhs: TemperatureSample, _ rhs: TemperatureSample) -> Bool {
        if lhs.timestamp == rhs.timestamp {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.timestamp < rhs.timestamp
    }
}

private extension Array {
    func uniqued<Value: Hashable>(by keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen = Set<Value>()
        return filter { element in
            seen.insert(element[keyPath: keyPath]).inserted
        }
    }
}
