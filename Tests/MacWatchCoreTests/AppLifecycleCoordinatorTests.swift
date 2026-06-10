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
}
