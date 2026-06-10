import SwiftUI

@main
struct MacWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        Settings {
            SettingsView()
        }
    }
}
