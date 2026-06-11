import AppKit
import MacWatchCore
import XCTest
@testable import MacWatchApp

final class AppDelegateTests: XCTestCase {
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
}
