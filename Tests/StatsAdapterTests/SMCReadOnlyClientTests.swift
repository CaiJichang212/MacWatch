import IOKit
import XCTest
@testable import StatsAdapter

final class SMCReadOnlyClientTests: XCTestCase {
    func testReadsSMCKeyCountWhenAppleSMCServiceIsAvailable() throws {
        guard Self.hasAppleSMCService() else {
            throw XCTSkip("AppleSMC service is not available in this environment.")
        }

        let client = SMCReadOnlyClient()

        let keyCount = client.getValue("#KEY")

        XCTAssertNotNil(keyCount)
        XCTAssertGreaterThan(keyCount ?? 0, 0)
    }

    private static func hasAppleSMCService() -> Bool {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC"),
            &iterator
        )
        guard result == kIOReturnSuccess else {
            return false
        }
        defer {
            if iterator != 0 {
                IOObjectRelease(iterator)
            }
        }

        let service = IOIteratorNext(iterator)
        if service != 0 {
            IOObjectRelease(service)
            return true
        }
        return false
    }
}
