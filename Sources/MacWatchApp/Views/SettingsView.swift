import MacWatchCore
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.default

    var body: some View {
        Form {
            Toggle("Launch main window on start", isOn: $settings.launchMainWindowOnStart)
        }
        .padding(20)
        .frame(width: 360)
    }
}
