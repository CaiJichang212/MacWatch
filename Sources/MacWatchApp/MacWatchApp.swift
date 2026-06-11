import StatsAdapter
import Darwin
import AppKit

@main
final class MacWatchApp {
    private static var appDelegate: AppDelegate?

    static func main() {
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

        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
