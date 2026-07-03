import XCTest
import AppKit
@testable import MacWatchApp

final class MenuBarCommandHandlerTests: XCTestCase {
    func testOpenMainWindowInvokesInjectedAction() {
        var openCalls = 0
        let handler = MenuBarCommandHandler(
            openMainWindow: { openCalls += 1 },
            openSettings: {},
            quitApplication: {}
        )

        handler.openMainWindow()

        XCTAssertEqual(openCalls, 1)
    }

    func testOpenSettingsInvokesInjectedAction() {
        var settingsCalls = 0
        let handler = MenuBarCommandHandler(
            openMainWindow: {},
            openSettings: { settingsCalls += 1 },
            quitApplication: {}
        )

        handler.openSettings()

        XCTAssertEqual(settingsCalls, 1)
    }

    func testQuitInvokesInjectedAction() {
        var quitCalls = 0
        let handler = MenuBarCommandHandler(
            openMainWindow: {},
            openSettings: {},
            quitApplication: { quitCalls += 1 }
        )

        handler.quitApplication()

        XCTAssertEqual(quitCalls, 1)
    }
}

final class WindowCommandCenterTests: XCTestCase {
    func testOpenMainWindowUsesRegisteredAction() {
        let commandCenter = WindowCommandCenter()
        var openCalls = 0
        commandCenter.registerOpenMainWindowAction {
            openCalls += 1
        }

        commandCenter.openMainWindow()

        XCTAssertEqual(openCalls, 1)
    }

    func testOpenMainWindowDeliversRequestedRoute() {
        let commandCenter = WindowCommandCenter()
        var receivedRoute: MainWindowRoute?
        commandCenter.registerNavigationAction { route in
            receivedRoute = route
        }

        commandCenter.openMainWindow(route: .compatibility)

        XCTAssertEqual(receivedRoute, .compatibility)
    }
}

@MainActor
final class AppMenuControllerTests: XCTestCase {
    private var previousMainMenu: NSMenu?
    private var previousWindowsMenu: NSMenu?

    override func setUp() {
        super.setUp()
        previousMainMenu = NSApp.mainMenu
        previousWindowsMenu = NSApp.windowsMenu
        NSApp.mainMenu = nil
        NSApp.windowsMenu = nil
    }

    override func tearDown() {
        NSApp.mainMenu = previousMainMenu
        NSApp.windowsMenu = previousWindowsMenu
        super.tearDown()
    }

    func testInstallAddsOnlyApprovedShortcuts() throws {
        let controller = AppMenuController(
            commandHandler: MenuBarCommandHandler(openMainWindow: {}, openSettings: {}, quitApplication: {})
        )

        controller.install(localizer: .english)

        let mainMenu = try XCTUnwrap(NSApp.mainMenu)
        let keyEquivalents = mainMenu.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .filter { $0.keyEquivalent.isEmpty == false }
            .map { "\($0.keyEquivalentModifierMask.rawValue)-\($0.keyEquivalent)" }

        XCTAssertEqual(Set(keyEquivalents), [
            "\(NSEvent.ModifierFlags.command.rawValue)-,",
            "\(NSEvent.ModifierFlags.command.rawValue)-q",
            "\(NSEvent.ModifierFlags.command.rawValue)-w",
        ])
        XCTAssertEqual(keyEquivalents.count, 3)
    }

    func testInstallRefreshesLocalizedTitles() throws {
        let controller = AppMenuController(
            commandHandler: MenuBarCommandHandler(openMainWindow: {}, openSettings: {}, quitApplication: {})
        )

        controller.install(localizer: .english)
        controller.install(localizer: .chinese)

        let mainMenu = try XCTUnwrap(NSApp.mainMenu)
        let appMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
        let windowMenu = try XCTUnwrap(mainMenu.items.last?.submenu)

        XCTAssertEqual(appMenu.item(at: 0)?.title, "设置…")
        XCTAssertEqual(appMenu.item(at: 2)?.title, "退出 MacWatch")
        XCTAssertEqual(windowMenu.item(at: 0)?.title, "关闭窗口")
    }
}
