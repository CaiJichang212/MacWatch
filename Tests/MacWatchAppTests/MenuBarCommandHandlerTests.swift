import XCTest
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
