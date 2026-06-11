import Foundation
import MacWatchCore

struct TemperatureDisplayText: Equatable {
    let text: String
    let statusSuffix: String?
    let isStale: Bool

    var fullText: String {
        guard let statusSuffix, statusSuffix.isEmpty == false else {
            return text
        }
        return "\(text) \(statusSuffix)"
    }
}

enum TemperatureFormatter {
    static func text(celsius: Double, unit: TemperatureUnit) -> String {
        let convertedValue: Double
        let suffix: String

        switch unit {
        case .celsius:
            convertedValue = celsius
            suffix = "°C"
        case .fahrenheit:
            convertedValue = celsius * 9 / 5 + 32
            suffix = "°F"
        }

        return "\(Int(convertedValue.rounded()))\(suffix)"
    }

    static func placeholder(unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return "--°C"
        case .fahrenheit:
            return "--°F"
        }
    }

    static func valueText(
        sample: TemperatureSample?,
        lastValidSample: TemperatureSample? = nil,
        unit: TemperatureUnit
    ) -> String {
        if let sample,
           sample.quality == .valid,
           let valueCelsius = sample.valueCelsius {
            return text(celsius: valueCelsius, unit: unit)
        }

        if let sample,
           sample.quality == .stale,
           let lastValidSample,
           let valueCelsius = lastValidSample.valueCelsius {
            return text(celsius: valueCelsius, unit: unit)
        }

        return placeholder(unit: unit)
    }

    static func statusText(sample: TemperatureSample?, capability: TemperatureCapability?) -> String {
        if let sample {
            switch sample.quality {
            case .valid:
                return "Valid"
            case .unsupported:
                return "Unsupported"
            case .readFailed:
                return "Read failed"
            case .stale:
                return "Stale"
            }
        }

        if let capability {
            if capability.supported == false {
                return "Unsupported"
            }
            if capability.readable == false {
                return "Read failed"
            }
        }

        return "Waiting"
    }

    static func reasonText(sample: TemperatureSample?, capability: TemperatureCapability?) -> String? {
        sample?.errorCode ?? capability?.reasonCode
    }

    static func sourceText(sample: TemperatureSample?, capability: TemperatureCapability?) -> String {
        sample?.source.rawValue ?? capability?.source.rawValue ?? "--"
    }

    static func rawKeyText(sample: TemperatureSample?, capability: TemperatureCapability?) -> String? {
        if let rawKey = sample?.rawKey, rawKey.isEmpty == false {
            return rawKey
        }

        if let sample {
            if let rawKeys = sample.attributes["rawKeys"], rawKeys.isEmpty == false {
                return rawKeys
            }
            if let attemptedRawKeys = sample.attributes["attemptedRawKeys"], attemptedRawKeys.isEmpty == false {
                return attemptedRawKeys
            }
        }

        return capability?.rawKey
    }

    static func isStale(sample: TemperatureSample?) -> Bool {
        sample?.quality == .stale
    }
}

enum MenuBarTitleFormatter {
    static func title(
        liveState: LiveTemperatureState?,
        settings: AppSettings
    ) -> TemperatureDisplayText {
        let sample: TemperatureSample?
        let lastValidSample: TemperatureSample?

        if settings.menuBarDisplayMetric == .hottest {
            let staleHottest = staleHottestSamples(in: liveState)
            sample = liveState?.hottestValidSample ?? staleHottest.sample
            lastValidSample = liveState?.hottestValidSample ?? staleHottest.lastValidSample
        } else if let descriptor = TemperatureMetricCatalog.menuBarMetric(for: settings.menuBarDisplayMetric) {
            sample = liveState?.samplesByMetricName[descriptor.metricName]
            lastValidSample = liveState?.lastValidSamplesByMetricName[descriptor.metricName]
        } else {
            sample = nil
            lastValidSample = nil
        }

        let isStale = TemperatureFormatter.isStale(sample: sample)
        let text = TemperatureFormatter.valueText(
            sample: sample,
            lastValidSample: lastValidSample,
            unit: settings.temperatureUnit
        )
        let suffix = isStale ? "stale" : nil
        let rawText = TemperatureDisplayText(text: text, statusSuffix: suffix, isStale: isStale)

        if rawText.fullText.count <= 30 {
            return rawText
        }

        return TemperatureDisplayText(text: text, statusSuffix: nil, isStale: isStale)
    }

    private static func staleHottestSamples(
        in liveState: LiveTemperatureState?
    ) -> (sample: TemperatureSample?, lastValidSample: TemperatureSample?) {
        guard let liveState else {
            return (nil, nil)
        }

        let lastValidSample = liveState.lastValidSamplesByMetricName.values.max { lhs, rhs in
            (lhs.valueCelsius ?? -.infinity) < (rhs.valueCelsius ?? -.infinity)
        }
        guard let lastValidSample,
              let sample = liveState.samplesByMetricName[lastValidSample.metricName],
              sample.quality == .stale else {
            return (nil, nil)
        }

        return (sample, lastValidSample)
    }
}
