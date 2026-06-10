import Foundation
import XCTest

final class StageSevenScriptTests: XCTestCase {
    func testPackageAppScriptCreatesBundleLayout() throws {
        let rootURL = repositoryRootURL()
        let tempDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeBinary = tempDirectory.appendingPathComponent("MacWatchApp")
        try Data("binary".utf8).write(to: fakeBinary)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeBinary.path
        )

        let outputBundle = tempDirectory.appendingPathComponent("MacWatch.app")
        let result = try runProcess(
            executable: "/bin/bash",
            arguments: [
                "scripts/package_app.sh",
                "--skip-build",
                "--binary",
                fakeBinary.path,
                "--output",
                outputBundle.path,
            ],
            currentDirectoryURL: rootURL,
            timeout: 10
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputBundle.appendingPathComponent("Contents/MacOS/MacWatchApp").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputBundle.appendingPathComponent("Contents/Info.plist").path))
    }

    func testPreflightDistributionScriptReportsBlockedWithoutIdentity() throws {
        let rootURL = repositoryRootURL()
        let tempDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let bundleURL = tempDirectory.appendingPathComponent("MacWatch.app")
        try FileManager.default.createDirectory(
            at: bundleURL.appendingPathComponent("Contents/MacOS"),
            withIntermediateDirectories: true
        )
        try Data("binary".utf8).write(to: bundleURL.appendingPathComponent("Contents/MacOS/MacWatchApp"))

        let result = try runProcess(
            executable: "/bin/bash",
            arguments: [
                "scripts/preflight_distribution.sh",
                bundleURL.path,
            ],
            environment: [
                "MACWATCH_TEST_MOCK_CODESIGNING_IDENTITIES": "0 valid identities found",
            ],
            currentDirectoryURL: rootURL,
            timeout: 10
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)

        let data = try XCTUnwrap(result.stdout.data(using: String.Encoding.utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["status"] as? String, "blocked")
        XCTAssertEqual(json["reason"] as? String, "missingDeveloperIDIdentity")
    }

    func testStageSevenAcceptanceScriptWritesSummaryJSON() throws {
        let rootURL = repositoryRootURL()
        let tempDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let summaryURL = tempDirectory.appendingPathComponent("stage7-summary.json")
        let result = try runProcess(
            executable: "/bin/bash",
            arguments: [
                "scripts/run_stage7_acceptance.sh",
                "--summary-json",
                summaryURL.path,
            ],
            environment: [
                "MACWATCH_TEST_SKIP_BUILD": "1",
                "MACWATCH_TEST_MOCK_ACCEPTANCE": "1",
                "MACWATCH_TEST_MOCK_CODESIGNING_IDENTITIES": "0 valid identities found",
            ],
            currentDirectoryURL: rootURL,
            timeout: 20
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
        XCTAssertTrue(FileManager.default.fileExists(atPath: summaryURL.path))

        let data = try Data(contentsOf: summaryURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["results"] as? [[String: Any]])
        XCTAssertNotNil(json["summary"] as? [String: Any])
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
