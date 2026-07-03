import AppKit

@MainActor
final class AppMenuController {
    private let commandHandler: MenuBarCommandHandler

    private var appMenuItem: NSMenuItem?
    private var settingsItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var windowMenuItem: NSMenuItem?
    private var closeWindowItem: NSMenuItem?

    init(commandHandler: MenuBarCommandHandler) {
        self.commandHandler = commandHandler
    }

    func install(localizer: AppLocalizer) {
        let application = NSApplication.shared

        if application.mainMenu == nil {
            let mainMenu = NSMenu()

            let appMenuHost = NSMenuItem()
            let appMenu = NSMenu(title: localizer.string("menu.app.title"))
            let settingsItem = NSMenuItem(
                title: localizer.string("menu.app.settings"),
                action: #selector(MenuBarCommandHandler.openSettings),
                keyEquivalent: ","
            )
            settingsItem.keyEquivalentModifierMask = [.command]
            settingsItem.target = commandHandler
            appMenu.addItem(settingsItem)
            appMenu.addItem(.separator())

            let quitItem = NSMenuItem(
                title: localizer.string("menu.app.quit"),
                action: #selector(MenuBarCommandHandler.quitApplication),
                keyEquivalent: "q"
            )
            quitItem.keyEquivalentModifierMask = [.command]
            quitItem.target = commandHandler
            appMenu.addItem(quitItem)
            appMenuHost.submenu = appMenu
            mainMenu.addItem(appMenuHost)

            let windowMenuHost = NSMenuItem()
            let windowMenu = NSMenu(title: localizer.string("menu.window.title"))
            let closeWindowItem = NSMenuItem(
                title: localizer.string("menu.window.close"),
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
            closeWindowItem.keyEquivalentModifierMask = [.command]
            closeWindowItem.target = nil
            windowMenu.addItem(closeWindowItem)
            windowMenuHost.submenu = windowMenu
            mainMenu.addItem(windowMenuHost)

            self.appMenuItem = appMenuHost
            self.settingsItem = settingsItem
            self.quitItem = quitItem
            self.windowMenuItem = windowMenuHost
            self.closeWindowItem = closeWindowItem

            application.mainMenu = mainMenu
            application.windowsMenu = windowMenu
        }

        appMenuItem?.submenu?.title = localizer.string("menu.app.title")
        settingsItem?.title = localizer.string("menu.app.settings")
        quitItem?.title = localizer.string("menu.app.quit")
        windowMenuItem?.submenu?.title = localizer.string("menu.window.title")
        closeWindowItem?.title = localizer.string("menu.window.close")
    }
}
