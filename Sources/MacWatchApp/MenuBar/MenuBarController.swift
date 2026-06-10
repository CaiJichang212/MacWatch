import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let commandHandler: MenuBarCommandHandler

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

    private func configureStatusItem() {
        statusItem.button?.title = "MacWatch"
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open MacWatch", action: #selector(MenuBarCommandHandler.openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(MenuBarCommandHandler.openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacWatch", action: #selector(MenuBarCommandHandler.quitApplication), keyEquivalent: "q"))

        for item in menu.items {
            item.target = commandHandler
        }

        return menu
    }
}
