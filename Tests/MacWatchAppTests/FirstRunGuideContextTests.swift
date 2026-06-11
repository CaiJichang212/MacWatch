import XCTest
@testable import MacWatchApp

final class FirstRunGuideContextTests: XCTestCase {
    func testMac16_12IsRecognizedAsMacBookAirTargetModel() {
        let context = FirstRunGuideContext(
            modelIdentifier: "Mac16,12",
            chipName: "Apple M4",
            isAppleSilicon: true,
            isMacBookAir: FirstRunGuideContext.isMacBookAirModelIdentifier("Mac16,12")
        )

        XCTAssertTrue(context.isMacBookAir)
        XCTAssertTrue(context.isSupportedTargetMachine)
    }

    func testAppleSiliconMacBookAirModelIdentifiersAreRecognizedAcrossMSeries() {
        let identifiers = [
            "MacBookAir10,1",
            "Mac14,2",
            "Mac14,15",
            "Mac15,12",
            "Mac15,13",
            "Mac16,12",
            "Mac16,13",
            "Mac17,3",
            "Mac17,4",
        ]

        for identifier in identifiers {
            XCTAssertTrue(
                FirstRunGuideContext.isMacBookAirModelIdentifier(identifier),
                "\(identifier) should be treated as an MVP MacBook Air target"
            )
        }
    }

    func testLegacyMacBookAirIdentifierIsRecognizedByName() {
        XCTAssertTrue(FirstRunGuideContext.isMacBookAirModelIdentifier("MacBookAir10,1"))
    }

    func testNonAirIdentifierIsNotRecognizedAsMacBookAir() {
        XCTAssertFalse(FirstRunGuideContext.isMacBookAirModelIdentifier("Mac15,7"))
    }
}
