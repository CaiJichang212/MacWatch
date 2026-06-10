import SwiftUI
import StatsAdapter
import Darwin

@main
struct MacWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let windowCommandCenter = WindowCommandCenter.shared

    init() {
        do {
            let cliArguments = try MacWatchCLIArguments(arguments: CommandLine.arguments)
            AcceptanceCoordinator.shared.configure(scenario: cliArguments.acceptanceScenario)

            if cliArguments.shouldProbeTemperatureOnce {
                let output = TemperatureProbeDiagnostics.readOnceJSONLines()
                if output.isEmpty == false {
                    print(output)
                }
                exit(0)
            }

            if let scenario = cliArguments.acceptanceScenario, scenario.requiresApplicationLaunch == false {
                let report = AcceptanceImmediateRunner.runSynchronously(scenario)
                AcceptanceReportWriter.writeAndExit(report)
            }
        } catch {
            AcceptanceReportWriter.writeErrorAndExit(error.localizedDescription)
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
                .environmentObject(appDelegate.runtime)
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
