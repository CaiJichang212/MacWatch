import MacWatchCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime
    @State private var isShowingClearConfirmation = false

    var body: some View {
        let localizer = runtime.localizer

        Form {
            Section(localizer.string("settings.general")) {
                Toggle(
                    localizer.string("settings.launchMainWindowOnStart"),
                    isOn: Binding(
                        get: { runtime.settings.launchMainWindowOnStart },
                        set: { value in
                            runtime.updateSettings { $0.launchMainWindowOnStart = value }
                        }
                    )
                )

                Picker(
                    localizer.string("settings.language"),
                    selection: Binding(
                        get: { runtime.settings.language },
                        set: { value in
                            runtime.updateSettings { $0.language = value }
                        }
                    )
                ) {
                    Text(localizer.languageLabel(.system)).tag(AppLanguage.system)
                    Text(localizer.languageLabel(.zhHans)).tag(AppLanguage.zhHans)
                    Text(localizer.languageLabel(.english)).tag(AppLanguage.english)
                }
            }

            Section(localizer.string("settings.temperature")) {
                Picker(
                    localizer.string("settings.unit"),
                    selection: Binding(
                        get: { runtime.settings.temperatureUnit },
                        set: { value in
                            runtime.updateSettings { $0.temperatureUnit = value }
                        }
                    )
                ) {
                    Text(localizer.temperatureUnitLabel(.celsius)).tag(TemperatureUnit.celsius)
                    Text(localizer.temperatureUnitLabel(.fahrenheit)).tag(TemperatureUnit.fahrenheit)
                }

                Picker(
                    localizer.string("settings.refreshInterval"),
                    selection: Binding(
                        get: { runtime.settings.refreshInterval },
                        set: { value in
                            runtime.updateSettings { $0.refreshInterval = value }
                        }
                    )
                ) {
                    Text(localizer.refreshIntervalLabel(.fiveSeconds)).tag(RefreshInterval.fiveSeconds)
                    Text(localizer.refreshIntervalLabel(.tenSeconds)).tag(RefreshInterval.tenSeconds)
                    Text(localizer.refreshIntervalLabel(.thirtySeconds)).tag(RefreshInterval.thirtySeconds)
                }

                Picker(
                    localizer.string("settings.defaultTrendRange"),
                    selection: Binding(
                        get: { runtime.settings.defaultTrendRange },
                        set: { value in
                            runtime.updateSettings { $0.defaultTrendRange = value }
                        }
                    )
                ) {
                    Text(localizer.rangeLabel(.fifteenMinutes)).tag(TemperatureHistoryRange.fifteenMinutes)
                    Text(localizer.rangeLabel(.oneHour)).tag(TemperatureHistoryRange.oneHour)
                    Text(localizer.rangeLabel(.sixHours)).tag(TemperatureHistoryRange.sixHours)
                    Text(localizer.rangeLabel(.allSession)).tag(TemperatureHistoryRange.allSession)
                }

                Picker(
                    localizer.string("settings.menuBarMetric"),
                    selection: Binding(
                        get: { runtime.settings.menuBarDisplayMetric },
                        set: { value in
                            runtime.updateSettings { $0.menuBarDisplayMetric = value }
                        }
                    )
                ) {
                    Text(localizer.menuBarMetricLabel(.hottest)).tag(MenuBarDisplayMetric.hottest)
                    Text(localizer.menuBarMetricLabel(.cpu)).tag(MenuBarDisplayMetric.cpu)
                    Text(localizer.menuBarMetricLabel(.gpu)).tag(MenuBarDisplayMetric.gpu)
                    Text(localizer.menuBarMetricLabel(.ssd)).tag(MenuBarDisplayMetric.ssd)
                    Text(localizer.menuBarMetricLabel(.battery)).tag(MenuBarDisplayMetric.battery)
                }
            }

            Section(localizer.string("settings.compatibility")) {
                CompatibilityView(compact: true)
            }

            Section(localizer.string("settings.history")) {
                Button(localizer.string("settings.clearCurrentSessionHistory"), role: .destructive) {
                    isShowingClearConfirmation = true
                }

                if let historyErrorMessage = runtime.historyErrorMessage {
                    Text(historyErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
        .alert(localizer.string("settings.clearCurrentSessionHistory.confirmTitle"), isPresented: $isShowingClearConfirmation) {
            Button(localizer.string("action.clear"), role: .destructive) {
                runtime.clearCurrentSessionHistory()
            }
            Button(localizer.string("action.cancel"), role: .cancel) {}
        } message: {
            Text(localizer.string("settings.clearCurrentSessionHistory.confirmMessage"))
        }
    }
}
