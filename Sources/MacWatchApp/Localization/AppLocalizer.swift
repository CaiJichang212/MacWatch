import Foundation
import MacWatchCore
import SwiftUI

struct AppLocalizer: Equatable {
    let language: AppLanguage
    let locale: Locale

    private let bundle: Bundle

    init(
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        let localization = Self.resolveLocalization(
            language: language,
            preferredLanguages: preferredLanguages
        )
        self.language = language
        self.locale = Locale(identifier: localization)
        self.bundle = Self.bundle(localization: localization)
    }

    static let english = AppLocalizer(language: .english, preferredLanguages: ["en"])
    static let chinese = AppLocalizer(language: .zhHans, preferredLanguages: ["zh-Hans"])

    func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = string(key)
        guard arguments.isEmpty == false else {
            return format
        }
        return String(format: format, locale: locale, arguments: arguments)
    }

    func metricTitle(for domain: TemperatureDomain) -> String {
        switch domain {
        case .cpu:
            return string("metric.cpu")
        case .gpu:
            return string("metric.gpu")
        case .ssd:
            return string("metric.ssd")
        case .battery:
            return string("metric.battery")
        case .system:
            return string("metric.system")
        case .sensor:
            return string("metric.sensor")
        }
    }

    func menuBarMetricLabel(_ metric: MenuBarDisplayMetric) -> String {
        switch metric {
        case .hottest:
            return string("metric.hottest")
        case .cpu:
            return string("metric.cpu")
        case .gpu:
            return string("metric.gpu")
        case .ssd:
            return string("metric.ssd")
        case .battery:
            return string("metric.battery")
        }
    }

    func detailMetricOptionLabel(isAverage: Bool) -> String {
        isAverage ? string("metric.average") : string("metric.hottest")
    }

    func languageLabel(_ language: AppLanguage) -> String {
        switch language {
        case .system:
            return string("language.system")
        case .zhHans:
            return string("language.zhHans")
        case .english:
            return string("language.english")
        }
    }

    func temperatureUnitLabel(_ unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return string("unit.celsius")
        case .fahrenheit:
            return string("unit.fahrenheit")
        }
    }

    func refreshIntervalLabel(_ interval: RefreshInterval) -> String {
        switch interval {
        case .fiveSeconds:
            return string("refresh.5seconds")
        case .tenSeconds:
            return string("refresh.10seconds")
        case .thirtySeconds:
            return string("refresh.30seconds")
        }
    }

    func rangeLabel(_ range: TemperatureHistoryRange) -> String {
        switch range {
        case .fifteenMinutes:
            return string("range.15minutes")
        case .oneHour:
            return string("range.1hour")
        case .sixHours:
            return string("range.6hours")
        case .allSession:
            return string("range.session")
        }
    }

    func shortRangeLabel(_ range: TemperatureHistoryRange) -> String {
        switch range {
        case .fifteenMinutes:
            return string("range.short.15minutes")
        case .oneHour:
            return string("range.short.1hour")
        case .sixHours:
            return string("range.short.6hours")
        case .allSession:
            return string("range.short.session")
        }
    }

    func statusText(sample: TemperatureSample?, capability: TemperatureCapability?) -> String {
        TemperatureFormatter.statusText(sample: sample, capability: capability, localizer: self)
    }

    func reasonText(sample: TemperatureSample?, capability: TemperatureCapability?) -> String? {
        TemperatureFormatter.reasonText(sample: sample, capability: capability, localizer: self)
    }

    func firstRunSupportMessage(context: FirstRunGuideContext) -> String {
        if context.isSupportedTargetMachine {
            return string("firstRun.support.inScope")
        }

        if context.isAppleSilicon {
            return string("firstRun.support.notMacBookAir")
        }

        return string("firstRun.support.notAppleSilicon")
    }

    static func resolve(language: AppLanguage) -> AppLocalizer {
        AppLocalizer(language: language)
    }

    private static func resolveLocalization(
        language: AppLanguage,
        preferredLanguages: [String]
    ) -> String {
        switch language {
        case .system:
            let resolved = Bundle.preferredLocalizations(
                from: ["zh-Hans", "en"],
                forPreferences: preferredLanguages
            ).first ?? "en"
            return resolved.hasPrefix("zh") ? "zh-Hans" : "en"
        case .zhHans:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }

    private static func bundle(localization: String) -> Bundle {
        let expectedDirectoryName = "\(localization).lproj"
        guard let path = Bundle.module.paths(forResourcesOfType: "lproj", inDirectory: nil).first(where: {
            URL(fileURLWithPath: $0).lastPathComponent.compare(
                expectedDirectoryName,
                options: [.caseInsensitive]
            ) == .orderedSame
        }),
              let bundle = Bundle(path: path) else {
            return .module
        }
        return bundle
    }
}

extension MacWatchRuntime {
    var localizer: AppLocalizer {
        AppLocalizer.resolve(language: settings.language)
    }
}

struct RuntimeLocalizedRoot<Content: View>: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.environment(\.locale, runtime.localizer.locale)
    }
}
