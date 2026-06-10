import Foundation
import XCTest

final class AcceptanceCLITests: XCTestCase {
    func testProbeStatusAcceptanceScenarioEmitsStableJSONReport() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executableURL = rootURL
            .appendingPathComponent(".build/arm64-apple-macosx/debug/MacWatchApp")
        let result = try runProcess(
            executable: executableURL.path,
            arguments: [
                "--acceptance-run",
                "probe-status",
            ],
            currentDirectoryURL: rootURL,
            timeout: 10
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)

        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["scenario"] as? String, "probe-status")
        XCTAssertEqual(json["passed"] as? Bool, true)
        XCTAssertNotNil(json["startedAt"] as? String)
        XCTAssertNotNil(json["durationMs"] as? NSNumber)
        XCTAssertNotNil(json["metrics"] as? [String: Any])
        XCTAssertNotNil(json["failures"] as? [Any])
    }
}
