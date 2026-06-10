import SwiftUI
import StatsAdapter
import Darwin

@main
struct MacWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let windowCommandCenter = WindowCommandCenter.shared

    init() {
        if CommandLine.arguments.contains("--probe-temperature-once") {
            let output = TemperatureProbeDiagnostics.readOnceJSONLines()
            if output.isEmpty == false {
                print(output)
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appDelegate.runtime)
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
