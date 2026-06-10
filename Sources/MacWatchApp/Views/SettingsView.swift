import MacWatchCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime
    @State private var isShowingClearConfirmation = false

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch main window on start",
                    isOn: Binding(
                        get: { runtime.settings.launchMainWindowOnStart },
                        set: { value in
                            runtime.updateSettings { $0.launchMainWindowOnStart = value }
                        }
                    )
                )
            }

            Section("Temperature") {
                Picker(
                    "Unit",
                    selection: Binding(
                        get: { runtime.settings.temperatureUnit },
                        set: { value in
                            runtime.updateSettings { $0.temperatureUnit = value }
                        }
                    )
                ) {
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }

                Picker(
                    "Refresh Interval",
                    selection: Binding(
                        get: { runtime.settings.refreshInterval },
                        set: { value in
                            runtime.updateSettings { $0.refreshInterval = value }
                        }
                    )
                ) {
                    Text("5 seconds").tag(RefreshInterval.fiveSeconds)
                    Text("10 seconds").tag(RefreshInterval.tenSeconds)
                    Text("30 seconds").tag(RefreshInterval.thirtySeconds)
                }

                Picker(
                    "Default Trend Range",
                    selection: Binding(
                        get: { runtime.settings.defaultTrendRange },
                        set: { value in
                            runtime.updateSettings { $0.defaultTrendRange = value }
                        }
                    )
                ) {
                    Text("15 minutes").tag(TemperatureHistoryRange.fifteenMinutes)
                    Text("1 hour").tag(TemperatureHistoryRange.oneHour)
                    Text("6 hours").tag(TemperatureHistoryRange.sixHours)
                    Text("Session").tag(TemperatureHistoryRange.allSession)
                }

                Picker(
                    "Menu Bar Metric",
                    selection: Binding(
                        get: { runtime.settings.menuBarDisplayMetric },
                        set: { value in
                            runtime.updateSettings { $0.menuBarDisplayMetric = value }
                        }
                    )
                ) {
                    Text("Hottest").tag(MenuBarDisplayMetric.hottest)
                    Text("CPU").tag(MenuBarDisplayMetric.cpu)
                    Text("GPU").tag(MenuBarDisplayMetric.gpu)
                    Text("Memory").tag(MenuBarDisplayMetric.memory)
                    Text("SSD/NAND").tag(MenuBarDisplayMetric.ssd)
                    Text("Battery").tag(MenuBarDisplayMetric.battery)
                }
            }

            Section("Compatibility") {
                CompatibilityView(compact: true)
            }

            Section("History") {
                Button("Clear Current Session History", role: .destructive) {
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
        .alert("Clear current session history?", isPresented: $isShowingClearConfirmation) {
            Button("Clear", role: .destructive) {
                runtime.clearCurrentSessionHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing trend samples for this app session will be removed.")
        }
    }
}
