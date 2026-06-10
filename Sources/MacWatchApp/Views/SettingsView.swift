import MacWatchCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime
    @State private var settings = AppSettings.default
    @State private var isShowingClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.headline)

            Toggle("Launch main window on start", isOn: $settings.launchMainWindowOnStart)

            Text("Startup behavior and current-session history actions.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            Button("Clear Current Session History", role: .destructive) {
                isShowingClearConfirmation = true
            }

            if let historyErrorMessage = runtime.historyErrorMessage {
                Text(historyErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 360)
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
