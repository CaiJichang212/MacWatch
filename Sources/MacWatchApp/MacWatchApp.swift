import SwiftUI

@main
struct MacWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let windowCommandCenter = WindowCommandCenter.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .background(
                    MainWindowBridge(windowCommandCenter: windowCommandCenter)
                )
        }
        Settings {
            SettingsView()
        }
    }
}

private struct MainWindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    let windowCommandCenter: WindowCommandCenter

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                windowCommandCenter.registerOpenMainWindowAction {
                    openWindow(id: "main")
                }
            }
    }
}
