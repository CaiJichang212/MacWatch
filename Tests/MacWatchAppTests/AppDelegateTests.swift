import AppKit
import MacWatchCore
import XCTest
@testable import MacWatchApp

final class AppDelegateTests: XCTestCase {
    func testLaunchingAppCreatesMonitoringSession() throws {
        let repository = InMemorySessionHistoryRepository()
        let appDelegate = AppDelegate(
            sessionHistoryRepository: repository,
            shouldSetupMenuBarOnLaunch: false,
            shouldRegisterObserversOnLaunch: false
        )

        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let session = try repository.currentSession()
        XCTAssertNotNil(session)
        XCTAssertEqual(
            try repository.timelineEvents(sessionID: session?.id ?? UUID()).map(\.eventType),
            [.appStarted]
        )
    }
}
