import MacWatchCore
import SwiftUI

struct FirstRunGuideView: View {
    let context: FirstRunGuideContext
    let language: AppLanguage
    let onContinue: (FirstRunGuideConfiguration) -> Void

    @State private var configuration: FirstRunGuideConfiguration

    init(
        context: FirstRunGuideContext,
        initialSettings: AppSettings,
        onContinue: @escaping (FirstRunGuideConfiguration) -> Void
    ) {
        self.context = context
        self.language = initialSettings.language
        self.onContinue = onContinue
        _configuration = State(initialValue: FirstRunGuideConfiguration(settings: initialSettings))
    }

    var body: some View {
        let localizer = AppLocalizer.resolve(language: language)

        VStack(alignment: .leading, spacing: 18) {
            Text(localizer.string("firstRun.title"))
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text(localizer.string("firstRun.intro"))
                .font(.body)

            VStack(alignment: .leading, spacing: 12) {
                Text(localizer.string("firstRun.deviceRecognition"))
                    .font(.headline)
                Text(localizer.string("firstRun.model", context.modelIdentifier ?? "--"))
                    .font(.body)
                Text(localizer.string("firstRun.chip", context.chipName ?? "--"))
                    .font(.body)
                Text(localizer.string(
                    "firstRun.compatibilityStatus",
                    context.isSupportedTargetMachine
                        ? localizer.string("firstRun.compatibility.inScope")
                        : localizer.string("firstRun.compatibility.outOfScope")
                ))
                    .font(.body)
                Text(localizer.firstRunSupportMessage(context: context))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text(localizer.string("firstRun.privacy"))
                .font(.headline)
            Text(localizer.string("firstRun.privacyBody"))
                .font(.body)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(localizer.string("firstRun.initialConfiguration"))
                    .font(.headline)

                Picker(localizer.string("firstRun.temperatureUnit"), selection: $configuration.temperatureUnit) {
                    Text(localizer.temperatureUnitLabel(.celsius)).tag(TemperatureUnit.celsius)
                    Text(localizer.temperatureUnitLabel(.fahrenheit)).tag(TemperatureUnit.fahrenheit)
                }
                .pickerStyle(.segmented)

                Picker(localizer.string("firstRun.menuBarDisplay"), selection: $configuration.menuBarDisplayMetric) {
                    Text(localizer.menuBarMetricLabel(.hottest)).tag(MenuBarDisplayMetric.hottest)
                    Text(localizer.menuBarMetricLabel(.cpu)).tag(MenuBarDisplayMetric.cpu)
                    Text(localizer.menuBarMetricLabel(.gpu)).tag(MenuBarDisplayMetric.gpu)
                    Text(localizer.menuBarMetricLabel(.ssd)).tag(MenuBarDisplayMetric.ssd)
                    Text(localizer.menuBarMetricLabel(.battery)).tag(MenuBarDisplayMetric.battery)
                }

                Picker(localizer.string("firstRun.refreshInterval"), selection: $configuration.refreshInterval) {
                    Text(localizer.refreshIntervalLabel(.fiveSeconds)).tag(RefreshInterval.fiveSeconds)
                    Text(localizer.refreshIntervalLabel(.tenSeconds)).tag(RefreshInterval.tenSeconds)
                    Text(localizer.refreshIntervalLabel(.thirtySeconds)).tag(RefreshInterval.thirtySeconds)
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button(localizer.string("firstRun.startMonitoring")) {
                    onContinue(configuration)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            AcceptanceCoordinator.shared.recordViewAppeared(.firstRunGuide)
        }
        .padding(28)
        .frame(minWidth: 520)
    }
}
