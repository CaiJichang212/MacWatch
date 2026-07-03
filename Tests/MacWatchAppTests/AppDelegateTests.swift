import AppKit
import MacWatchCore
import XCTest
@testable import MacWatchApp

final class AppDelegateTests: XCTestCase {
    override func tearDown() {
        NSApp.windows.forEach { $0.close() }
        NSApp.mainMenu = nil
        NSApp.windowsMenu = nil
        super.tearDown()
    }

    @MainActor
    func testResourceSteadyStateEnvironmentDisablesLaunchWindowAndFirstRunGuide() {
        setenv("MACWATCH_RESOURCE_STEADY_STATE", "1", 1)
        defer { unsetenv("MACWATCH_RESOURCE_STEADY_STATE") }

        let appDelegate = AppDelegate(
            sessionHistoryRepository: InMemorySessionHistoryRepository(),
            shouldSetupMenuBarOnLaunch: false,
            shouldRegisterObserversOnLaunch: false,
            shouldStartRuntimeOnLaunch: false,
            shouldOpenMainWindowOnLaunch: false
        )

        XCTAssertFalse(appDelegate.runtime.settings.launchMainWindowOnStart)
        XCTAssertFalse(appDelegate.runtime.shouldShowFirstRunGuide)
    }

    @MainActor
    func testLaunchingAppCreatesMonitoringSessionWithoutStartingRuntimeWhenDisabled() async throws {
        let repository = InMemorySessionHistoryRepository()
        let appDelegate = AppDelegate(
            sessionHistoryRepository: repository,
            shouldSetupMenuBarOnLaunch: false,
            shouldRegisterObserversOnLaunch: false,
            shouldStartRuntimeOnLaunch: false,
            shouldOpenMainWindowOnLaunch: false
        )

        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        let session = try repository.currentSession()
        XCTAssertNotNil(session)
        XCTAssertEqual(
            try repository.timelineEvents(sessionID: session?.id ?? UUID()).map(\.eventType),
            [.appStarted]
        )
        XCTAssertEqual(try repository.samples(sessionID: session?.id ?? UUID()).count, 0)
        XCTAssertEqual(try repository.capabilities(sessionID: session?.id ?? UUID()).count, 0)
    }

    @MainActor
    func testSettingsMenuReusesSingletonWindowAndRefreshesLocalizedTitle() async throws {
        let appDelegate = AppDelegate(
            sessionHistoryRepository: InMemorySessionHistoryRepository(),
            shouldSetupMenuBarOnLaunch: false,
            shouldRegisterObserversOnLaunch: false,
            shouldStartRuntimeOnLaunch: false,
            shouldOpenMainWindowOnLaunch: false
        )
        appDelegate.runtime.updateSettings { $0.language = .english }

        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let settingsItem = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu?.item(at: 0))
        XCTAssertEqual(settingsItem.keyEquivalent, ",")

        NSApp.sendAction(settingsItem.action!, to: settingsItem.target, from: nil)
        let firstWindow = try XCTUnwrap(
            NSApp.windows.first(where: { $0.title == appDelegate.runtime.localizer.string("window.settings.title") })
        )

        NSApp.sendAction(settingsItem.action!, to: settingsItem.target, from: nil)
        let settingsWindows = NSApp.windows.filter { $0.title == "Settings" }
        XCTAssertEqual(settingsWindows.count, 1)
        XCTAssertTrue(settingsWindows.first === firstWindow)

        firstWindow.performClose(nil)
        XCTAssertFalse(firstWindow.isVisible)

        NSApp.sendAction(settingsItem.action!, to: settingsItem.target, from: nil)
        XCTAssertTrue(firstWindow.isVisible)

        appDelegate.runtime.updateSettings { $0.language = .zhHans }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(firstWindow.title, "设置")
    }
}
