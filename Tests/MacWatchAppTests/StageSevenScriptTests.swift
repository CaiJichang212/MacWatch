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
        try createFakeLocalizationBundle(nextTo: fakeBinary)

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
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: outputBundle.appendingPathComponent("MacWatch_MacWatchApp.bundle/en.lproj/Localizable.strings").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: outputBundle.appendingPathComponent("MacWatch_MacWatchApp.bundle/zh-hans.lproj/Localizable.strings").path
        ))
    }

    func testPackageAppScriptPrintsOnlyBundlePathWhenBuildCommandWritesOutput() throws {
        let rootURL = repositoryRootURL()
        let tempDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeBinary = tempDirectory.appendingPathComponent("MacWatchApp")
        try Data("binary".utf8).write(to: fakeBinary)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeBinary.path
        )
        try createFakeLocalizationBundle(nextTo: fakeBinary)

        let outputBundle = tempDirectory.appendingPathComponent("MacWatch.app")
        let result = try runProcess(
            executable: "/bin/bash",
            arguments: [
                "scripts/package_app.sh",
                "--configuration",
                "release",
                "--binary",
                fakeBinary.path,
                "--output",
                outputBundle.path,
            ],
            environment: [
                "MACWATCH_TEST_MOCK_BUILD_OUTPUT": "Building for production...\nBuild complete!",
            ],
            currentDirectoryURL: rootURL,
            timeout: 10
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
        let stdoutLines = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.isEmpty == false }
        XCTAssertEqual(stdoutLines, [outputBundle.path])
    }

    func testPackageAppScriptRejectsBinaryWithoutResourceBundle() throws {
        let rootURL = repositoryRootURL()
        let tempDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fakeBinary = tempDirectory.appendingPathComponent("MacWatchApp")
        try Data("binary".utf8).write(to: fakeBinary)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeBinary.path
        )

        let result = try runProcess(
            executable: "/bin/bash",
            arguments: [
                "scripts/package_app.sh",
                "--skip-build",
                "--binary",
                fakeBinary.path,
                "--output",
                tempDirectory.appendingPathComponent("MacWatch.app").path,
            ],
            currentDirectoryURL: rootURL,
            timeout: 10
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.combinedOutput.contains("Missing resource bundle"))
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

    func testPreflightDistributionScriptAcceptsExplicitIdentityAndNotaryProfile() throws {
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
                "--identity",
                "Developer ID Application: Example Team",
                "--notary-profile",
                "macwatch-notary",
                bundleURL.path,
            ],
            environment: [
                "MACWATCH_TEST_MOCK_CODESIGNING_IDENTITIES": "1) ABC \"Developer ID Application: Example Team\"",
                "MACWATCH_TEST_MOCK_CODESIGN_OUTPUT": "Authority=Developer ID Application: Example Team",
                "MACWATCH_TEST_MOCK_SPCTL_OUTPUT": "\(bundleURL.path): accepted",
            ],
            currentDirectoryURL: rootURL,
            timeout: 10
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)

        let data = try XCTUnwrap(result.stdout.data(using: String.Encoding.utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["status"] as? String, "passed")
        XCTAssertEqual(json["signature"] as? String, "developerID")
        XCTAssertEqual(json["notaryProfileConfigured"] as? Bool, true)
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

    func testStageSevenAcceptanceScriptAcceptsReleaseConfigurationAndFailsResourceProbeWithNoSamples() throws {
        let rootURL = repositoryRootURL()
        let tempDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let summaryURL = tempDirectory.appendingPathComponent("stage7-summary.json")
        let result = try runProcess(
            executable: "/bin/bash",
            arguments: [
                "scripts/run_stage7_acceptance.sh",
                "--configuration",
                "release",
                "--summary-json",
                summaryURL.path,
            ],
            environment: [
                "MACWATCH_TEST_SKIP_BUILD": "1",
                "MACWATCH_TEST_MOCK_ACCEPTANCE": "1",
                "MACWATCH_TEST_MOCK_RESOURCE_SAMPLES": "",
                "MACWATCH_TEST_MOCK_CODESIGNING_IDENTITIES": "0 valid identities found",
            ],
            currentDirectoryURL: rootURL,
            timeout: 20
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)

        let data = try Data(contentsOf: summaryURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try XCTUnwrap(json["results"] as? [[String: Any]])
        let resourceResult = try XCTUnwrap(results.first { $0["name"] as? String == "resources" })
        let report = try XCTUnwrap(resourceResult["report"] as? [String: Any])
        XCTAssertEqual(resourceResult["status"] as? String, "failed")
        XCTAssertEqual(report["reason"] as? String, "noResourceSamples")
        XCTAssertEqual(report["configuration"] as? String, "release")
    }

    func testStageSevenAcceptanceScriptUsesPhysicalFootprintForResourceMemory() throws {
        let rootURL = repositoryRootURL()
        let tempDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let summaryURL = tempDirectory.appendingPathComponent("stage7-summary.json")
        let result = try runProcess(
            executable: "/bin/bash",
            arguments: [
                "scripts/run_stage7_acceptance.sh",
                "--configuration",
                "release",
                "--summary-json",
                summaryURL.path,
            ],
            environment: [
                "MACWATCH_TEST_SKIP_BUILD": "1",
                "MACWATCH_TEST_MOCK_ACCEPTANCE": "1",
                "MACWATCH_TEST_MOCK_RESOURCE_SAMPLES": "0.4 143360 105.1M\n0.8 142000 106.0M",
                "MACWATCH_TEST_MOCK_CODESIGNING_IDENTITIES": "0 valid identities found",
            ],
            currentDirectoryURL: rootURL,
            timeout: 20
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)

        let data = try Data(contentsOf: summaryURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try XCTUnwrap(json["results"] as? [[String: Any]])
        let resourceResult = try XCTUnwrap(results.first { $0["name"] as? String == "resources" })
        let report = try XCTUnwrap(resourceResult["report"] as? [String: Any])
        XCTAssertEqual(resourceResult["status"] as? String, "passed")
        XCTAssertEqual(report["memorySource"] as? String, "physicalFootprint")
        XCTAssertEqual(report["peakMemoryMB"] as? Double, 106.0)
        XCTAssertEqual(report["peakRSSMemoryMB"] as? Double, 140.0)
    }

    func testStageSevenAcceptanceScriptNormalizesCpuByLogicalCoreCount() throws {
        let rootURL = repositoryRootURL()
        let tempDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let summaryURL = tempDirectory.appendingPathComponent("stage7-summary.json")
        let result = try runProcess(
            executable: "/bin/bash",
            arguments: [
                "scripts/run_stage7_acceptance.sh",
                "--configuration",
                "release",
                "--summary-json",
                summaryURL.path,
            ],
            environment: [
                "MACWATCH_TEST_SKIP_BUILD": "1",
                "MACWATCH_TEST_MOCK_ACCEPTANCE": "1",
                "MACWATCH_TEST_MOCK_RESOURCE_SAMPLES": "6.0 143360 45.1M\n6.0 142000 45.0M",
                "MACWATCH_TEST_MOCK_LOGICAL_CPU_COUNT": "10",
                "MACWATCH_TEST_MOCK_CODESIGNING_IDENTITIES": "0 valid identities found",
            ],
            currentDirectoryURL: rootURL,
            timeout: 20
        )

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)

        let data = try Data(contentsOf: summaryURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try XCTUnwrap(json["results"] as? [[String: Any]])
        let resourceResult = try XCTUnwrap(results.first { $0["name"] as? String == "resources" })
        let report = try XCTUnwrap(resourceResult["report"] as? [String: Any])
        XCTAssertEqual(resourceResult["status"] as? String, "passed")
        XCTAssertEqual(report["rawAverageCpuPercent"] as? Double, 6.0)
        XCTAssertEqual(report["averageCpuPercent"] as? Double, 0.6)
        XCTAssertEqual(report["cpuNormalizationFactor"] as? Int, 10)
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

    private func createFakeLocalizationBundle(nextTo binaryURL: URL) throws {
        let bundleURL = binaryURL
            .deletingLastPathComponent()
            .appendingPathComponent("MacWatch_MacWatchApp.bundle")

        for localization in ["en", "zh-hans"] {
            let localizationURL = bundleURL.appendingPathComponent("\(localization).lproj")
            try FileManager.default.createDirectory(
                at: localizationURL,
                withIntermediateDirectories: true
            )
            try Data("\"test\" = \"test\";".utf8).write(
                to: localizationURL.appendingPathComponent("Localizable.strings")
            )
        }
    }
}
