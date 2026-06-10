import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let openMainWindowHandler: () -> Void
    private let openSettingsHandler: () -> Void
    private let quitApplicationHandler: () -> Void

    init(
        openMainWindow: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        quitApplication: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        openMainWindowHandler = openMainWindow
        openSettingsHandler = openSettings
        quitApplicationHandler = quitApplication
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        statusItem.button?.title = "MacWatch"
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open MacWatch", action: #selector(openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacWatch", action: #selector(quitApplication), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        return menu
    }

    @objc
    private func openMainWindow() {
        openMainWindowHandler()
    }

    @objc
    private func openSettings() {
        openSettingsHandler()
    }

    @objc
    private func quitApplication() {
        quitApplicationHandler()
    }
}
