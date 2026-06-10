import XCTest
@testable import MacWatchCore

final class AppLifecycleCoordinatorTests: XCTestCase {
    func testRecordsLifecycleEventsInOrder() {
        let coordinator = AppLifecycleCoordinator()

        coordinator.record(.launched)
        coordinator.record(.willSleep)
        coordinator.record(.didWake)

        XCTAssertEqual(coordinator.events, [.launched, .willSleep, .didWake])
    }

    func testForwardsLifecycleEventsToInjectedHandler() {
        var forwarded: [AppLifecycleEvent] = []
        let coordinator = AppLifecycleCoordinator { event in
            forwarded.append(event)
        }

        coordinator.record(.launched)
        coordinator.record(.willSleep)
        coordinator.record(.didWake)
        coordinator.record(.willTerminate)

        XCTAssertEqual(coordinator.events, [.launched, .willSleep, .didWake, .willTerminate])
        XCTAssertEqual(forwarded, [.launched, .willSleep, .didWake, .willTerminate])
    }
}
