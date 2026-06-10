import AppKit
import MacWatchCore

enum MenuBarTemperatureFormatter {
    static func title(forCelsius valueCelsius: Double) -> String {
        "\(Int(valueCelsius.rounded()))°C"
    }

    static func title(forUnavailableMetric domain: TemperatureDomain) -> String {
        "--°C"
    }

    static func title(for sample: TemperatureSample?) -> String {
        guard let sample,
              sample.quality == .valid,
              let valueCelsius = sample.valueCelsius else {
            return title(forUnavailableMetric: .cpu)
        }

        return title(forCelsius: valueCelsius)
    }
}

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let commandHandler: MenuBarCommandHandler
    private var liveState: LiveTemperatureState?

    init(
        openMainWindow: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        quitApplication: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        commandHandler = MenuBarCommandHandler(
            openMainWindow: openMainWindow,
            openSettings: openSettings,
            quitApplication: quitApplication
        )
        super.init()
        configureStatusItem()
    }

    func update(liveState: LiveTemperatureState?) {
        self.liveState = liveState
        statusItem.button?.title = MenuBarTemperatureFormatter.title(for: liveState?.hottestValidSample)
        statusItem.menu = buildMenu()
    }

    private func configureStatusItem() {
        statusItem.button?.title = MenuBarTemperatureFormatter.title(forUnavailableMetric: .cpu)
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let cpuItem = NSMenuItem(
            title: cpuStatusText(),
            action: nil,
            keyEquivalent: ""
        )
        cpuItem.isEnabled = false
        menu.addItem(cpuItem)

        let updatedItem = NSMenuItem(
            title: updatedAtText(),
            action: nil,
            keyEquivalent: ""
        )
        updatedItem.isEnabled = false
        menu.addItem(updatedItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open MacWatch", action: #selector(MenuBarCommandHandler.openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(MenuBarCommandHandler.openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacWatch", action: #selector(MenuBarCommandHandler.quitApplication), keyEquivalent: "q"))

        for item in menu.items {
            item.target = commandHandler
        }

        return menu
    }

    private func cpuStatusText() -> String {
        let sample = liveState?.samplesByMetricName[TemperatureMetricName.cpuHottest]
        guard let sample else {
            return "CPU: waiting for data"
        }

        switch sample.quality {
        case .valid:
            return "CPU: \(MenuBarTemperatureFormatter.title(for: sample))"
        case .unsupported:
            return "CPU: unsupported"
        case .readFailed:
            return "CPU: read failed"
        case .stale:
            return "CPU: stale"
        }
    }

    private func updatedAtText() -> String {
        guard let updatedAt = liveState?.updatedAt else {
            return "Updated: --"
        }

        return "Updated: \(Self.timeFormatter.string(from: updatedAt))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}
