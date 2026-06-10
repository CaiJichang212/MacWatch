import MacWatchCore
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.default

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.headline)

            Toggle("Launch main window on start", isOn: $settings.launchMainWindowOnStart)

            Text("Stage 1 only exposes the startup window preference.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }
}
